# Migración a proyecto de Xcode

La decisión que el plan dejaba apuntada desde el principio ("¿SwiftPM o proyecto Xcode? No migrar
antes de necesitarlo"), tomada el 2026-09-02.

## Por qué ahora

Dos de los cuatro disparadores que el plan listaba se habían cumplido el mismo día: asociación de
tipos de archivo (hecha a mano en un heredoc) y distribuir a alguien más (el zip para otra Mac). Y
los scripts ya habían mordido tres veces: un `</dict>` de menos que generó un plist corrupto, el
icono que no aparecía porque Xcode ejecuta el binario pelado, y `make-app.sh` fallando en silencio
por un array vacío en bash 3.2 — que además me tuvo tres verificaciones seguidas mirando un bundle
viejo.

## Cómo queda repartido

- **`Package.swift` se queda solo con `JSONCore` y sus tests.** Sigue siendo la red de seguridad:
  `swift test` corre los 168 en menos de un segundo, sin arrancar Xcode.
- **`JsonToolingApp/JsonToolingApp.xcodeproj` construye la app**, consumiendo el paquete como
  dependencia local.
- Se **borró `Sources/JsonToolingApp/`**: al arrastrar los archivos, Xcode los copió, y durante un
  rato el código de la app existió por duplicado — el arreglo del `import Combine` hubo que
  aplicarlo en los dos sitios. Dos copias del mismo código divergen; ahora hay una.

## Lo que hubo que arreglar

- **`import Combine` en `AppModel.swift`.** Es lo único que rompió al compilar en Xcode:
  `@Published` y `ObservableObject` son de Combine, y SwiftPM los daba por importados de rebote a
  través de SwiftUI. El modo Swift 6 que traen los proyectos nuevos exige el import explícito.
- **El icono estaba como *dataset*** en el catálogo de assets, que Xcode no usa para el icono de
  la app; `AppIcon` estaba vacío. Ahora `Scripts/make-icon.swift` rellena el `AppIcon.appiconset`
  con los diez PNG desde el mismo dibujo, así que no hay dos iconos que puedan divergir. Se dejó
  de generar el `.icns`: el catálogo no lo usa.
- El formulario de tipos de documento de Xcode deja `UTExportedTypeDeclarations` y
  `UTImportedTypeDeclarations` con diccionarios vacíos; se quitaron del `Info.plist`.
- `PRODUCT_NAME` pasa a `JsonTooling` (el proyecto se creó como `JsonToolingApp`, y la app se
  llamaba así) y el identificador a `com.narvisgil.JsonTooling`.

## Scripts

- `Scripts/make-app.sh` y `Scripts/run.sh` **se borran**: los sustituye darle a Run en Xcode.
- `Scripts/package.sh` se reescribe sobre `xcodebuild`, con **`-scheme` y no `-target`**:
  `-target` no resuelve las dependencias de paquete y la compilación muere con
  `unable to resolve module dependency: 'JSONCore'`. Xcode no había creado ningún fichero de
  esquema (los autogenera y anota en `xcuserdata`), así que se escribió uno **compartido** en
  `xcshareddata/xcschemes/`, que sí viaja en el repositorio.
- `Scripts/make-icon.swift` se queda, apuntando al catálogo de assets.

## Dos trampas del repositorio

**Xcode creó su propio repositorio git dentro del proyecto.** El repo de fuera lo añadió como
*gitlink* (`160000 commit …`), así que el primer commit de la migración subió a GitHub una
referencia vacía: **cero archivos de la app**. Se detectó mirando `git ls-tree`. Se borró el
`.git` interior y se añadieron los archivos de verdad.

**El `.gitignore` ignoraba `/build`, anclado a la raíz.** `xcodebuild` deja su `build/` **junto al
`.xcodeproj`**, así que se colaron 380 archivos de artefactos en el índice. Ahora el patrón es
`build/`, sin anclar, y `package.sh` manda su salida a `build/DerivedData` de la raíz.

## Criterio de aceptación
1. `swift test` sigue en verde sin tocar nada. **Hecho**: 168/168.
2. `xcodebuild` construye y la app arranca con panel, árbol y toolbar. **Verificado** con captura.
3. El icono sale en el Dock, construido por Xcode desde el catálogo. **Verificado** con captura.
4. `Scripts/package.sh` produce un zip universal, firmado ad-hoc, que se descomprime y arranca.
   **Verificado** de punta a punta: `lipo` da `x86_64 arm64`, `codesign` da `adhoc`, identificador
   `com.narvisgil.JsonTooling`, y la app descomprimida abre su ventana.
5. Lo que entra en el repositorio son 27 archivos (fuentes, proyecto, assets), sin artefactos de
   compilación ni estado de usuario. **Verificado** con `git diff --cached --name-only`.
6. Manual, pendiente: darle a Run en Xcode y comprobar que el flujo de trabajo diario es cómodo.

## Avisos que quedaron del proyecto nuevo (2026-09-02)

El usuario los señaló con archivo y línea, y resultó que **no eran el "Publishing changes" que
buscábamos**: eran avisos de compilación del proyecto recién creado.

- **Cuatro `onChange(of:perform:)` obsoletos** desde macOS 14 (TreePanel 112 y 195, CompareScreen
  115 y 215). Migrados a la forma de dos o cero parámetros.
- **Cinco del icono**: `icon_512x512@2x.png` medía 2048 px en vez de 1024. Culpa de
  `Scripts/make-icon.swift`: `NSImage.lockFocus()` dibuja a la escala de la pantalla, y en una
  Retina el maestro salía al doble. Ahora se dibuja sobre un `NSBitmapImageRep` con los píxeles
  fijados a mano.

Con eso el proyecto compila **sin un solo aviso**.

## El destino de despliegue que puso Xcode

`MACOSX_DEPLOYMENT_TARGET = 26.4`, es decir, la app solo arrancaba en la última versión de macOS.
Contradecía la decisión del plan (macOS 13+) y, peor, **el zip que se lleva a otra Mac no habría
arrancado** salvo que esa Mac estuviera igual de actualizada — justo lo que se acababa de montar.

Bajado a **14.0**, que es el suelo real del código: la forma nueva de `onChange` pide macOS 14. Si
alguna de las Macs de destino fuera más antigua, habría que envolver esos cuatro `onChange` en
`#available` y bajar a 13.
