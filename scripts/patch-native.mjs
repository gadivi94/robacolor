// Ajusta el proyecto iOS que genera `npx cap add ios`: nombre, versión, permisos y orientación.
import fs from "node:fs";

const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const VERSION = process.env.APP_VERSION || pkg.version;
const BUILD = String(parseInt(process.env.BUILD_NUMBER || "1", 10));
const fallo = (m) => { console.error("✖ " + m); process.exit(1); };

const plist = "ios/App/App/Info.plist";
if (!fs.existsSync(plist)) fallo("No existe " + plist + " (¿falló npx cap add ios?)");
let p = fs.readFileSync(plist, "utf8");
const alFinal = (xml) => { p = p.replace(/<\/dict>\s*<\/plist>\s*$/, `${xml}</dict>\n</plist>\n`); };
const poner = (clave, xml) => {
  const re = new RegExp(`(<key>${clave}</key>\\s*)(<string>[^<]*</string>|<true/>|<false/>)`);
  if (re.test(p)) p = p.replace(re, `$1${xml}`); else alFinal(`\t<key>${clave}</key>\n\t${xml}\n`);
  if (!p.includes(`<key>${clave}</key>`)) fallo("No he podido escribir " + clave);
};
const ponerLista = (clave, valores) => {
  const xml = `<array>\n${valores.map((v) => `\t\t<string>${v}</string>\n`).join("")}\t</array>`;
  const re = new RegExp(`(<key>${clave.replace(/[~.]/g, "\\$&")}</key>\\s*)<array>[\\s\\S]*?</array>`);
  if (re.test(p)) p = p.replace(re, `$1${xml}`); else alFinal(`\t<key>${clave}</key>\n\t${xml}\n`);
  if (!p.includes(`<key>${clave}</key>`)) fallo("No he podido escribir " + clave);
};

poner("CFBundleDisplayName", "<string>StealColor</string>");
poner("CFBundleDevelopmentRegion", "<string>es</string>");
poner("CFBundleShortVersionString", `<string>${VERSION}</string>`);
poner("CFBundleVersion", `<string>${BUILD}</string>`);
poner("ITSAppUsesNonExemptEncryption", "<false/>");
poner("UIViewControllerBasedStatusBarAppearance", "<true/>");
// Permisos: iOS enseña estos textos la primera vez que la app los necesita
poner("NSPhotoLibraryAddUsageDescription", "<string>StealColor guarda en Fotos las imágenes que editas.</string>");
poner("NSPhotoLibraryUsageDescription", "<string>StealColor abre las fotos que eliges para copiar sus colores y editarlas. No salen de tu dispositivo.</string>");
poner("NSCameraUsageDescription", "<string>StealColor usa la cámara solo si decides hacer una foto para editarla o usarla como referencia.</string>");
// iPhone en vertical; iPad en cualquier orientación
ponerLista("UISupportedInterfaceOrientations", ["UIInterfaceOrientationPortrait"]);
ponerLista("UISupportedInterfaceOrientations~ipad", ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]);
fs.writeFileSync(plist, p);
console.log(`✔ iOS: StealColor ${VERSION} (${BUILD}), permisos de Fotos y cámara, iPhone en vertical`);
