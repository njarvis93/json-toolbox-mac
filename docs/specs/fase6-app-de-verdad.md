# Spec: icono, doble clic y firma ad-hoc

Tres cosas de la Fase 6 que van juntas porque son lo mismo: que esto deje de ser un binario que
se lanza desde la terminal y se comporte como una app.

## Icono

Se **dibuja** en `Scripts/make-icon.swift` en vez de guardar solo un `.icns` opaco: así se puede
cambiar un color sin abrir un editor de imágenes, y se ve de dónde salen las medidas. El script
pinta el maestro de 1024, saca el resto de tamaños con `sips` y monta el `.icns` con `iconutil`.

Llaves `{ }` sobre un rectángulo redondeado con el gris azulado del editor en oscuro, y dentro dos
barras con los colores de clave y de cadena del resaltado. Se probó a 32 px, que es donde se
decide: con tres barras finas se fundían en una mancha, y con las llaves más grandes tocaban los
bordes. Dos barras gruesas y llaves algo menores sí se leen.

## Doble clic en un `.json`

`CFBundleDocumentTypes` en el `Info.plist` que monta `Scripts/make-app.sh`, y
`application(_:open:)` en el `AppDelegate`.

**`LSHandlerRank` es `Alternate`, no `Owner`**, a conciencia: reclamar todos los `.json` del
sistema le quitaría la asociación al editor que ya la tenga. Así la app aparece en "Abrir con", y
quien la quiera por defecto la pone desde Obtener información → Abrir con → Cambiar todos.

Los archivos que llegan del Finder pueden hacerlo **antes** de que exista la ventana que engancha
el modelo, así que se guardan en `pendingURLs` y se abren en cuanto hay modelo (el `didSet` de
`model`). Sin eso, abrir la app arrastrando un archivo no cargaría nada.

## Firma ad-hoc

`codesign --force --sign -` sobre el bundle. Sin firma, cada build es una app distinta para
Gatekeeper y hay que volver a darle permisos (incluido el de grabación de pantalla, que en este
proyecto se usa para verificar). Se quita también la cuarentena por si el `.app` se ha movido con
un navegador, y se hace `touch` al bundle para que el Finder se entere del icono nuevo.

Sigue sin notarizar: es de uso personal y así estaba decidido desde el principio.

## El icono solo sale lanzando el `.app`

Lo preguntó el usuario: no veía el icono. La causa es que Xcode ejecuta el **binario pelado**,
sin `Info.plist` ni `Resources`, y macOS le pone el icono genérico "exec".

Se intentó arreglar poniéndolo en marcha con `NSApp.applicationIconImage`, cargando el `.icns`
como recurso del target. **Se midió y no funciona**: el log confirma que la imagen se carga y se
asigna (256×256), y el Dock sigue enseñando el genérico — macOS 26 lo ignora en un proceso sin
bundle. El código se quitó en vez de dejarlo ahí aparentando hacer algo.

Así que para verlo con icono hay que lanzar el bundle: `Scripts/run.sh` (compila, empaqueta y
abre) o directamente `open build/JsonTooling.app`.

## Llevarla a otro Mac

`Scripts/package.sh` deja un zip listo en `build/`:

- **binario universal** (Apple Silicon + Intel), con `UNIVERSAL=1` sobre `make-app.sh`; sin eso
  sale solo la arquitectura de la máquina que compila, y en el otro Mac no arranca;
- comprimido con `ditto` y no con `zip`, que estropea enlaces y permisos del bundle;
- con un `LEEME.txt` dentro, porque en el Mac de destino **Gatekeeper la bloquea la primera vez**:
  la app está firmada ad-hoc pero no notarizada, y notarizar necesita cuenta de desarrollador de
  pago. Se resuelve con `xattr -dr com.apple.quarantine` o con clic derecho → Abrir.

Sigue siendo lo que decía el plan desde el principio: distribución de uso personal, sin firma de
desarrollador ni notarización.

## Criterio de aceptación
1. `swift build`, `swift test` y `Scripts/make-app.sh` sin errores; `plutil -lint` del Info.plist
   correcto. **Hecho** (168/168, 2026-09-02).
2. El icono se lee a 32 px. **Verificado** renderizando a ese tamaño antes de darlo por bueno.
3. El icono sale en el Dock. **Verificado** con captura de pantalla real.
4. Abrir un `.json` con la app carga el documento, el título y el árbol. **Verificado** abriendo
   un archivo contra el bundle, que es lo que hace el Finder.
5. `codesign -dv` dice `Signature=adhoc`. **Verificado.**
6. El zip se descomprime en `JsonTooling/` con la app y el LEEME, la firma ad-hoc sobrevive al
   viaje y el binario tiene las dos arquitecturas. **Verificado** descomprimiendo el zip real.
7. Manual, pendiente: doble clic de verdad desde el Finder tras poner la app en Aplicaciones, y
   abrirla en el otro Mac.
