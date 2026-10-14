# Robacolor · app de iPhone

Robacolor copia los colores de una foto de referencia a tu foto o a tu vídeo y deja terminar el trabajo con herramientas de revelado y de etalonaje (ruedas Lift/Gamma/Gain, curvas, monitores de señal). Esta carpeta es la app de iPhone y iPad: la misma página que ya has probado, dentro de una app nativa (Capacitor 8), compilada en la nube con **Codemagic**, sin Mac. Es el mismo sistema que opos365 y Radar de Plazas.

**Qué añade la app respecto a la web**
- **Guardar foto** la añade directamente a Fotos (si no das permiso, abre la hoja de compartir).
- **Mis looks** se guardan en un archivo de la app, no en la memoria del navegador.
- Funciona sin conexión: las fuentes van dentro de la app y las fotos no salen del dispositivo.
- Comportamiento de app: sin zoom de página, doble toque para restablecer un control, iPhone en vertical.

Identificador de la app (Bundle ID): **`cat.gadivi.robacolor`**. No se puede cambiar una vez publicada. Si prefieres otro, cámbialo ahora en `capacitor.config.json` y en `codemagic.yaml`.

## 0. GitHub
El proyecto vive en el repositorio `robacolor` de GitHub. Codemagic compila la rama `main`.

## 1. Apple Developer (developer.apple.com → Certificates, Identifiers & Profiles)
1. **Identifiers → +** → *App IDs* → *App* → Continue.
   - Description: `Robacolor` · Bundle ID: *Explicit* `cat.gadivi.robacolor`.
   - No hace falta marcar ninguna *Capability* → Continue → Register.
2. **Profiles → +** → *App Store Connect* (Distribution) → App ID `cat.gadivi.robacolor` → el certificado **Apple Distribution** que ya usas → nombre `Robacolor App Store` → Generate.

## 2. App Store Connect (appstoreconnect.apple.com)
**Apps → + → Nueva app**: plataforma iOS · nombre `Robacolor` · idioma principal Español · Bundle ID `cat.gadivi.robacolor` · SKU `robacolor`.

El nombre de la tienda tiene que ser único. Si `Robacolor` está cogido, usa por ejemplo `Robacolor: copia el color`. Debajo del icono seguirá poniendo «Robacolor».

## 3. Codemagic (codemagic.io)
1. **Add application** → GitHub → `robacolor` → tipo *codemagic.yaml*.
2. **Team settings → codemagic.yaml settings → Code signing identities → iOS provisioning profiles → Fetch profiles** → marca `Robacolor App Store`.
3. En la app `robacolor` → **Start new build** → rama `main` → flujo **iOS (TestFlight)**. Tarda unos 20 minutos.
4. Cuando acabe, la compilación aparece en App Store Connect → TestFlight. Instálala desde **TestFlight** en el iPhone o el iPad.

Si falla, copia las líneas que salen entre «MOTIVO DEL ERROR» y pásamelas.

## Qué probar en TestFlight
Esto solo se puede comprobar en un iPhone real:
- Subir una referencia y una foto tuya desde la fototeca y desde la cámara.
- **Guardar foto**: tiene que pedir permiso la primera vez y aparecer en Fotos.
- Fluidez al mover los controles con una foto grande.
- Guardar un look, cerrar la app del todo y volver a abrirla: el look tiene que seguir ahí.

## Vídeo
«Subir» admite también vídeos. El look y los ajustes se convierten en una tabla 3D (LUT) que la tarjeta gráfica aplica a cada fotograma, así que la vista previa va en tiempo real.

- **Transporte:** reproducir, código de tiempo, barra de posición y marcas de **Entrada** y **Salida** para guardar solo un tramo.
- **Monitores:** histograma, forma de onda, parade RGB y vectorscopio del resultado (también con fotos).
- **Ruedas de color:** Lift, Gamma y Gain, cada una con su color y su nivel.
- **Guardar:** reproduce el tramo con el look y graba lo que sale, con su sonido. Tarda lo que dura el tramo; un segundo toque en «Guardar» lo detiene. Sale al tamaño del original, hasta 4K (3840 px de lado largo); debajo del vídeo se puede elegir 1080p o 720p si el teléfono no llega a grabar fluido o el archivo pesa demasiado (4K son unos 250 MB por minuto).
- **Exportar LUT:** guarda el look y los ajustes como archivo `.cube` (33 puntos) para usarlo en DaVinci Resolve, Premiere o Final Cut. No incluye viñeteado, granulado ni claridad.

Límites conocidos: la claridad no se aplica al vídeo; el selector de iOS puede entregar el vídeo ya comprimido (desde Archivos llega el original); y el guardado graba en tiempo real, no vuelve a codificar el original fotograma a fotograma.

Qué probar en el iPhone: que el vídeo se ve con el look al cargarlo, que suena al reproducir, que «Guardar» termina y el vídeo aparece en Fotos con sonido, y que no se salta fotogramas.

## Actualizar la app
Cada cambio que llega a la rama `main` lanza una compilación sola (si no arranca, en Codemagic → ajustes de la app → **Webhooks** se puede reactivar el aviso de GitHub). También se puede lanzar a mano: Codemagic → **Start new build** → **iOS (TestFlight)**. Al terminar hay que pulsar **Actualizar** en TestFlight. El número de compilación sube solo. Para cambiar la versión que se ve en la tienda (1.0.0 → 1.1.0), cambia `"version"` en `package.json`.

## Qué hay dentro

| Archivo / carpeta | Qué es |
|---|---|
| `web/robacolor.html` | La app: interfaz y todo el procesado de color. Es la misma página que la versión web |
| `native/native.js` | Capa nativa: guardar fotos y vídeos en Fotos, compartir el LUT y archivo de looks |
| `assets/` | Icono y pantalla de inicio (clara y oscura). Codemagic genera todos los tamaños |
| `scripts/prepare-www.mjs` | Monta `www/` con la página, las fuentes y la capa nativa |
| `scripts/patch-native.mjs` | Pone nombre, versión, permisos y orientación en el proyecto iOS |
| `codemagic.yaml` | Receta de compilación y subida a TestFlight |
| `capacitor.config.json` | Nombre de la app e identificador |

## Web pública (robacolor.com)

La portada, la política de privacidad y la app en el navegador (`/app/`) se publican solas en Cloudflare Pages con cada cambio en `site/` o `web/` (GitHub → **Actions** → *Publica la web*). Para montarla en local: `node scripts/build-site.mjs` → carpeta `dist-web/`.

Puesta en marcha (una sola vez):

1. **Dominio:** Cloudflare → **Domain Registration** → **Register domains** → `robacolor.com`. Si eliges otro, en GitHub → Settings → Secrets and variables → Actions → pestaña *Variables* → `DOMINIO` = el que compres.
2. **Llave de Cloudflare:** My Profile → **API Tokens** → *Create Token* → *Create Custom Token* → permiso **Account · Cloudflare Pages · Edit** → *Create* y copia la llave (solo se ve una vez).
3. **GitHub:** repositorio `robacolor` → Settings → Secrets and variables → **Actions** → *New repository secret* → nombre `CLOUDFLARE_API_TOKEN`, valor la llave.
4. GitHub → **Actions** → *Publica la web* → **Run workflow**. En 1–2 minutos está en `https://robacolor.pages.dev` y, al rato, en `https://robacolor.com`.
5. **Correo hola@robacolor.com** (sale en la privacidad): Cloudflare → robacolor.com → **Email** → **Email Routing** → regla `hola@robacolor.com` → tu Gmail.

La URL de la privacidad (`https://robacolor.com/privacidad`) es la que pide App Store Connect al publicar la app.

