// Monta la web pública (dist-web/): la portada y la privacidad de site/, y la app en /app/ a partir de web/robacolor.html.
// Las fuentes se sirven desde la propia web (copias de @fontsource) si están instaladas; si no, se quedan las de Google.
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";

const OUT = "dist-web";
const fallo = (m) => { console.error("✖ " + m); process.exit(1); };
if (!existsSync("web/robacolor.html") || !existsSync("site/index.html")) fallo("Ejecútalo desde la raíz del repositorio");

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT + "/app", { recursive: true });
cpSync("site", OUT, { recursive: true });

// Fuentes locales
const FUENTES = [
  { familia: "Bricolage Grotesque", peso: "200 800", archivo: "node_modules/@fontsource-variable/bricolage-grotesque/files/bricolage-grotesque-latin-opsz-normal.woff2", formato: "woff2-variations" },
  { familia: "Instrument Sans", peso: "400 700", archivo: "node_modules/@fontsource-variable/instrument-sans/files/instrument-sans-latin-wght-normal.woff2", formato: "woff2-variations" },
  { familia: "DM Mono", peso: "400", archivo: "node_modules/@fontsource/dm-mono/files/dm-mono-latin-400-normal.woff2", formato: "woff2" },
  { familia: "DM Mono", peso: "500", archivo: "node_modules/@fontsource/dm-mono/files/dm-mono-latin-500-normal.woff2", formato: "woff2" },
];
const locales = FUENTES.every((f) => existsSync(f.archivo));
let fontCss = "";
if (locales) {
  mkdirSync(OUT + "/fonts", { recursive: true });
  for (const f of FUENTES) {
    const nombre = f.archivo.split("/").pop();
    cpSync(f.archivo, `${OUT}/fonts/${nombre}`);
    fontCss += `@font-face{font-family:'${f.familia}';font-style:normal;font-display:swap;font-weight:${f.peso};src:url(/fonts/${nombre}) format('${f.formato}')}\n`;
  }
} else console.warn("⚠ Sin @fontsource instalado: la web usará Google Fonts (npm install para servirlas desde la propia web)");
const GOOGLE = /<link rel="stylesheet" href="https:\/\/fonts\.googleapis\.com[^>]*>\s*/;
const fuentes = (html) => (locales ? html.replace(GOOGLE, `<style>\n${fontCss}</style>\n`) : html);

// Portada y demás páginas de site/
for (const f of readdirSync("site").filter((f) => f.endsWith(".html"))) {
  writeFileSync(`${OUT}/${f}`, fuentes(readFileSync(`site/${f}`, "utf8")));
}

// La app, envuelta en un documento completo
let app = readFileSync("web/robacolor.html", "utf8");
const titulo = (app.match(/<title>([^<]*)<\/title>/) || [null, "StealColor"])[1];
app = app.replace(/<title>[^<]*<\/title>\s*/, "");
const head = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${titulo}</title>
<meta name="description" content="Copia los colores de una foto que te gusta y aplícalos a tu foto o a tu vídeo.">
<meta name="theme-color" content="#ebecf1" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0e0f13" media="(prefers-color-scheme: dark)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="StealColor">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">
<style>
:root{color-scheme:light;padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px)}
body{margin:0;font:14px system-ui,-apple-system,sans-serif}
img{max-width:100%}
[hidden]{display:none!important}
</style>
`;
// el enlace de fuentes de la app pasa al <head>
const enlace = (app.match(GOOGLE) || [""])[0];
app = app.replace(GOOGLE, "");
const html = head + (locales ? `<style>\n${fontCss}</style>\n` : enlace) + "</head>\n<body>\n" + app + "\n</body>\n</html>\n";
writeFileSync(`${OUT}/app/index.html`, html);

const kb = (p) => (readFileSync(p).length / 1024).toFixed(0) + " KB";
console.log(`✔ ${OUT}/ listo · portada ${kb(OUT + "/index.html")} · app ${kb(OUT + "/app/index.html")} · fuentes ${locales ? "locales" : "de Google"}`);
