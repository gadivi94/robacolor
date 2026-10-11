/* Robacolor · capa nativa de la app de iPhone (Capacitor). En la web no hace nada. */
(function () {
  var C = window.Capacitor;
  if (!(C && C.isNativePlatform && C.isNativePlatform())) return;
  var html = document.documentElement;
  html.classList.add("nativa");
  function plugin(nombre) { return (window.Capacitor.Plugins || {})[nombre]; }

  /* 1. Comportamiento de app: sin zoom de página, sin selección de texto ni menú al mantener pulsado,
        y una franja que tapa lo que pasa por debajo de la barra de estado. */
  try {
    var st = document.createElement("style");
    st.textContent =
      "html,body{-webkit-text-size-adjust:100%;touch-action:manipulation}" +
      ".nativa body{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}" +
      ".nativa input[type=text]{-webkit-user-select:text;user-select:text;font-size:16px}" +
      ".nativa::before{content:'';position:fixed;top:0;left:0;right:0;height:env(safe-area-inset-top,0px);background:var(--bg);z-index:20}" +
      ".nativa .wrap{padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}";
    (document.head || html).appendChild(st);
    document.addEventListener("gesturestart", function (e) { e.preventDefault(); }, { passive: false });
  } catch (e) {}

  /* 2. Guardar la foto: se escribe en un archivo temporal (por trozos, para no saturar el puente)
        y se añade al carrete. Si iOS no deja, se abre la hoja de compartir. */
  function base64(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  }
  async function escribirTemporal(blob, nombre) {
    var FS = plugin("Filesystem");
    if (!FS) throw new Error("Falta el plugin Filesystem");
    var bytes = new Uint8Array(await blob.arrayBuffer());
    var TROZO = 3 * 256 * 1024; // múltiplo de 3: cada trozo es base64 válido por sí solo
    var ruta = "robacolor/" + nombre, uri = "";
    for (var o = 0; o < bytes.length; o += TROZO) {
      var datos = base64(bytes.subarray(o, Math.min(bytes.length, o + TROZO)));
      if (o === 0) uri = (await FS.writeFile({ path: ruta, data: datos, directory: "CACHE", recursive: true })).uri;
      else await FS.appendFile({ path: ruta, data: datos, directory: "CACHE" });
    }
    return uri;
  }
  async function compartir(uri) {
    var SH = plugin("Share");
    if (!SH) return "failed";
    try { await SH.share({ files: [uri], dialogTitle: "Guardar o compartir la foto" }); return "shared"; }
    catch (e) { return "cancelled"; }
  }
  async function savePhoto(blob, nombre) {
    var uri;
    try { uri = await escribirTemporal(blob, nombre); } catch (e) { return "failed"; }
    var M = plugin("Media");
    if (M) { try { await M.savePhoto({ path: uri }); return "saved"; } catch (e) { /* sin permiso para Fotos: se ofrece compartir */ } }
    return compartir(uri);
  }

  async function saveVideo(blob, nombre) {
    var uri;
    try { uri = await escribirTemporal(blob, nombre); } catch (e) { return "failed"; }
    var M = plugin("Media");
    if (M) { try { await M.saveVideo({ path: uri }); return "saved"; } catch (e) { /* sin permiso para Fotos: se ofrece compartir */ } }
    return compartir(uri);
  }
  // Archivos de texto (el LUT .cube): se escriben y se abre la hoja de compartir para guardarlos donde se quiera
  async function shareText(texto, nombre) {
    var FS = plugin("Filesystem");
    if (!FS) return "failed";
    try {
      var r = await FS.writeFile({ path: "robacolor/" + nombre, data: texto, directory: "CACHE", encoding: "utf8", recursive: true });
      return compartir(r.uri);
    } catch (e) { return "failed"; }
  }

  /* 3. Mis looks: se guardan en un archivo de la app para que no dependan de la memoria del navegador */
  var LOOKS = { path: "robacolor-looks.json", directory: "LIBRARY", encoding: "utf8" };
  function readLooks() {
    var FS = plugin("Filesystem");
    if (!FS) return Promise.resolve(null);
    return FS.readFile(LOOKS).then(function (r) { return typeof r.data === "string" ? r.data : null; }).catch(function () { return null; });
  }
  function storeLooks(texto) {
    var FS = plugin("Filesystem");
    if (!FS) return Promise.resolve();
    return FS.writeFile({ path: LOOKS.path, directory: LOOKS.directory, encoding: LOOKS.encoding, data: texto }).catch(function () {});
  }

  /* 4. RAW: el plugin nativo abre el selector, revela la foto con el motor RAW de Apple y deja dos archivos
        en crudo (16 bits lineales). Aquí solo se convierten sus rutas en direcciones que la web puede leer. */
  async function pickRaw(origen, lado, espacio) {
    var R = plugin("RobacolorRaw");
    if (!R) throw new Error("Falta el plugin RAW");
    var r = await R.pick({ source: origen, preview: lado, full: 4096, space: espacio });
    r.previewUrl = window.Capacitor.convertFileSrc(r.preview);
    r.fullUrl = window.Capacitor.convertFileSrc(r.full);
    return r;
  }

  window.RobacolorNative = { savePhoto: savePhoto, saveVideo: saveVideo, shareText: shareText, readLooks: readLooks, storeLooks: storeLooks, pickRaw: plugin("RobacolorRaw") ? pickRaw : null };
})();
