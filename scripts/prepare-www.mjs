// Monta www/ para la app de iPhone: envuelve la página en un documento completo,
// cambia las fuentes de Google por copias locales (la app funciona sin conexión) y añade la capa nativa.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const fallo = (m) => { console.error("✖ " + m); process.exit(1); };
const ORIGEN = "web/robacolor.html";
if (!existsSync(ORIGEN)) fallo("No existe " + ORIGEN);
let pagina = readFileSync(ORIGEN, "utf8");

const titulo = (pagina.match(/<title>([^<]*)<\/title>/) || [null, "StealColor"])[1];
pagina = pagina.replace(/<title>[^<]*<\/title>\s*/, "");
const enlaceFuentes = /<link rel="stylesheet" href="https:\/\/fonts\.googleapis\.com[^>]*>\s*/;
if (!enlaceFuentes.test(pagina)) console.warn("⚠ No encuentro el enlace a Google Fonts (¿ha cambiado la página?)");
pagina = pagina.replace(enlaceFuentes, "");
if (/https?:\/\/(?!www\.w3\.org)/.test(pagina)) console.warn("⚠ La página sigue cargando algo de internet; la app debería funcionar sin conexión");

rmSync("www", { recursive: true, force: true });
mkdirSync("www/fonts", { recursive: true });
mkdirSync("www/native", { recursive: true });
cpSync("native/native.js", "www/native/native.js");

// Fuentes: mismas familias que en la web, copiadas de los paquetes @fontsource
const FUENTES = [
  { familia: "Bricolage Grotesque", peso: "200 800", archivo: "node_modules/@fontsource-variable/bricolage-grotesque/files/bricolage-grotesque-latin-opsz-normal.woff2", formato: "woff2-variations" },
  { familia: "Instrument Sans", peso: "400 700", archivo: "node_modules/@fontsource-variable/instrument-sans/files/instrument-sans-latin-wght-normal.woff2", formato: "woff2-variations" },
  { familia: "DM Mono", peso: "400", archivo: "node_modules/@fontsource/dm-mono/files/dm-mono-latin-400-normal.woff2", formato: "woff2" },
  { familia: "DM Mono", peso: "500", archivo: "node_modules/@fontsource/dm-mono/files/dm-mono-latin-500-normal.woff2", formato: "woff2" },
];
let css = "", copiadas = 0;
for (const f of FUENTES) {
  if (!existsSync(f.archivo)) { console.warn("⚠ Falta la fuente " + f.archivo + " (se usará la del sistema)"); continue; }
  const nombre = f.archivo.split("/").pop();
  cpSync(f.archivo, "www/fonts/" + nombre);
  css += `@font-face{font-family:'${f.familia}';font-style:normal;font-display:swap;font-weight:${f.peso};src:url(fonts/${nombre}) format('${f.formato}')}\n`;
  copiadas++;
}

const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="format-detection" content="telephone=no">
<title>${titulo}</title>
<style>
:root{color-scheme:light;padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px)}
body{margin:0;font:14px system-ui,-apple-system,sans-serif}
img{max-width:100%}
[hidden]{display:none!important}
${css}</style>
<script src="native/native.js"></script>
</head>
<body>
${pagina}
</body>
</html>
`;
writeFileSync("www/index.html", html);
console.log(`✔ www/ listo · ${(html.length / 1024).toFixed(0)} KB · ${copiadas}/${FUENTES.length} fuentes locales`);
