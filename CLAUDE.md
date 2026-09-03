# JsonTooling — contexto para Claude Code

App nativa de macOS para leer, validar, formatear y comparar JSON. Proyecto personal de Narvis.
Este archivo recoge lo que no se deduce leyendo el código.

## Cómo trabajar aquí

- **Compila y ejecuta los tests tú mismo** antes de dar nada por bueno. El núcleo:
  `swift test` (168 en verde el 2026-09-02, menos de un segundo, sin arrancar Xcode). La app:
  `xcodebuild -project JsonToolingApp/JsonToolingApp.xcodeproj -target JsonToolingApp build`.
  Los tests de la capa de app (33 en verde el 2026-09-02, `AppModelTests`) necesitan el proyecto:
  `xcodebuild -project JsonToolingApp/JsonToolingApp.xcodeproj -scheme JsonToolingApp -destination 'platform=macOS' test`.
- Respuestas directas y concisas. Nada de inflar lo que se ha verificado: si algo no se ha
  ejecutado, decirlo.
- **El formato lo comprueba CI** (`swift-format` con `.swift-format`, ajustado al estilo del
  proyecto: 4 espacios, 110 columnas). Antes de commitear: `./Scripts/format.sh`. El repositorio
  se formateó entero el 2026-09-03, así que a partir de ahí está a cero avisos.
- La cobertura de `JSONCore` tiene puerta al **80 %** (`./Scripts/coverage.sh 80`; hoy va por el
  91,83 %). La de la app se publica pero no bloquea: más de la mitad del target son vistas y
  paneles que no corren sin interfaz.
- CI es **una cadena** en `ci.yml`: puerta → tests → calidad → build, con `needs:`. La puerta
  (nombre de rama y `detect-secrets`) corre en **Linux** a propósito: son segundos y un minuto de
  macOS cuesta 10x. Los PR salen de `fix/…` o `feature/…`; a `main` solo se le corre la cadena si
  el push viene de un hotfix, porque lo demás llega por un PR que ya pasó. Cada eslabón corre en
  una máquina limpia, así que añadir pasos ahí cuesta reloj; si algo se puede comprobar en el
  eslabón que ya tiene el `.build` montado, va ahí. El informe de cobertura se calcula en tests
  y se juzga en calidad, pasándolo como artefacto en vez de arrastrar `.build` entre jobs.
- El proyecto está en git, en [njarvis93/json-toolbox-mac](https://github.com/njarvis93/json-toolbox-mac).

## Decisiones tomadas (no re-litigar sin motivo)

| | |
|---|---|
| Stack | Swift + SwiftUI, macOS 14+ (lo pide la forma nueva de `onChange`; el plan decía 13 y Xcode había puesto 26.4). `Package.swift` tiene **solo `JSONCore` y sus tests**; la app la construye `JsonToolingApp/JsonToolingApp.xcodeproj`, que consume el paquete como dependencia local (migrado el 2026-09-02, ver `docs/specs/fase6-migracion-xcode.md`). Sin dependencias externas. Nada de Electron/Tauri. |
| Alcance v1 | Editor con validación, beautify/minify, ordenar claves, comparar dos documentos, convertir a string escapado y a XML. |
| Fuera de v1 | Árbol navegable, JSONPath/jq, conversión YAML/CSV, generación de tipos. |
| Tamaño | Documentos < 10 MB: por encima se rechaza la importación. Resaltado apagado > 512 KB. |
| Licencia | **PolyForm Noncommercial 1.0.0** desde el 2026-09-03: código visible, no abierto, con el uso comercial reservado. Antes era MIT, y esas versiones siguen siendo MIT para quien ya las tuviera. |
| Distribución | Uso personal. Firma ad-hoc, sin notarización, sin sandbox. Se prueba con Run en Xcode; `Scripts/package.sh` hace el zip universal para otro Mac. No condicionar el diseño por App Store. |
| Estética | macOS real: toolbar unificada, regla de líneas, barra de estado, colores tipo Xcode en claro y oscuro. |

`docs/prototipo-ux.html` es el prototipo del que salió el diseño. Ábrelo en un navegador antes
de proponer cambios de UI: la app lo sigue deliberadamente.

## Las tres decisiones técnicas que sostienen JSONCore

Si alguna vez parece que se podría simplificar usando `JSONSerialization` o `Codable`, es que
se ha perdido el motivo:

1. **Parser propio con posiciones.** `JSONParser.validate` devuelve `mensaje + línea + columna`,
   con la columna en caracteres y no en bytes (`"añ"` no descuadra). Los errores del runtime no
   dan posición utilizable, y la regla lateral necesita saber qué línea pintar en rojo.
2. **Nunca pasar un número por `Double`.** `JSONValue.number(raw: String)` guarda el literal y el
   formateador reemite los tokens originales. Un round-trip `parse → stringify` degrada
   `90071992547409931` (> 2^53) y normaliza `7.50` a `7.5`. Hay tests que lo fijan; si fallan,
   se ha roto la razón de ser del formateador.
3. **Diff estructural, no textual.** `JSONDiff.compare` recorre árboles y devuelve rutas
   (`lineas[0].cantidad`). Reordenar claves, cambiar espaciado o escribir `1.50` en vez de `1.5`
   no son diferencias. Los arrays se emparejan por clave de identidad cuando la hay, y solo por
   posición cuando no (`docs/specs/fase5-emparejar-arrays.md`): sin eso, insertar un elemento al
   principio marcaba el array entero. `LineAlignment.align` va *encima*, sobre el texto ya formateado, y solo
   decide dónde meter huecos para que las columnas cuadren.

El árbol posicionado (`JSONNode`) va **aparte** de `JSONValue`, no dentro: `JSONDiff` compara
valores y dos documentos equivalentes con distinto espaciado tienen que seguir siendo iguales. El
parser construye los dos en el mismo recorrido. Sus rutas son las mismas que las de
`JSONChange.path` a propósito. Detalle en `docs/specs/fase4-arbol.md`.

`Token` publica también desplazamientos UTF-16 (`utf16Start`/`utf16End`) porque es lo que
necesita `NSAttributedString`; con bytes UTF-8 el resaltado se descuadra en cuanto hay un emoji.

Decisión discutible, tomada a conciencia: **las claves duplicadas se rechazan como error**. El
estándar las deja indefinidas y otras herramientas se quedan con la última. Para una herramienta
de inspección es más útil verlas. Si estorba en uso real, bajarlo a aviso.

## La app

Los archivos van por capa, y la capa dice qué es cada cosa (reorganizado el 2026-09-02, ver
`docs/specs/fase8-estructura.md`):

```
JsonToolingApp/
├── App/          arranque, escenas, AppDelegate y los grupos de menú
├── ViewModels/   AppModel, DocumentModel, ComparisonModel, NavigationModel, Preferences
├── Views/        ContentView, StatusBar + Editor/, Compare/, AppKit/
├── Support/      Theme, FileImport
└── Resources/    Assets.xcassets, Info.plist
```

El **modelo** de MVVM aquí es `JSONCore`, que ya vive fuera como paquete: por eso no hay
`Models/`, y por eso no hay `Services/` ni `Providers/` — esta app no tiene red, ni persistencia
más allá de `UserDefaults`, ni inyección de dependencias. Las carpetas del proyecto están
**sincronizadas con el disco** (`fileSystemSynchronizedGroups`), así que mover o añadir un archivo
no toca el `.pbxproj`; la excepción es `Info.plist`, cuya ruta está en `INFOPLIST_FILE`.

`JSONTextView` envuelve un `NSTextView` con **pila TextKit 1 explícita** (NSTextStorage +
NSLayoutManager + NSTextContainer construidos a mano), porque SwiftUI `TextEditor` no da ni regla
lateral ni atributos.

La numeración de líneas (`LineNumberGutter`) es una `NSView` normal, hermana del `NSScrollView`
dentro de un contenedor con Auto Layout — **no** un `NSScrollView.verticalRulerView`. Se probó así
primero y se descartó a conciencia: un `NSRulerView` propio asignado ahí hace que el `NSTextView`
vecino deje de componerse en pantalla en cuanto el ruler dibuja algo, incluso un `rect.fill()`
sin tocar texto ni layout — el contenido sigue existiendo (`cacheDisplay(in:to:)` lo pinta bien
offscreen) pero la ventana real nunca lo muestra mientras el ruler esté activo. No se sabe la
causa exacta dentro de AppKit/SwiftUI; el diagnóstico completo está en
`docs/specs/fase2-undo.md`. Si en algún momento se vuelve a intentar `verticalRulerView`,
verificarlo visualmente de verdad (capturando la ventana por su id con `screencapture -l<id>`,
no solo compilando) antes de darlo por bueno.

La vista lado a lado es **un solo `ScrollView`** con dos columnas dentro, para que el
desplazamiento vaya sincronizado por construcción en vez de coordinar dos scrolls.

**Nunca `Divider()` entre dos vistas `View` custom que fijan su propia altura con
`.frame(height:)`** (p. ej. dos `PaneHeader`, o dos `DiffCell`, a los lados de un `Divider()`
dentro de un `HStack`). SwiftUI no resuelve bien la altura del `HStack` en ese caso — el
`Divider()` pide una altura "greedy" y toda la fila se infla muy por encima de lo esperado,
dejando huecos en blanco alrededor del contenido real. No basta con cambiar `Divider()` por otra
forma sin altura explícita (un `Rectangle().frame(width:)` sin `height:` tiene el mismo problema);
hace falta darle una altura fija igual a la de los hermanos. Diagnóstico completo en
`docs/specs/fase2-comparar-hueco.md`. Si aparece un hueco así, no ir quitando cosas a ciegas:
un `GeometryReader` temporal en `.background()` con log a stderr da el número exacto en segundos.

**Nunca tocar el `NSTextView` desde `updateNSView` de forma que dispare un delegado que escriba
en el modelo.** `setSelectedRange` llama a `textViewDidChangeSelection` de forma síncrona, y ese
delegado informa del cursor escribiendo en `AppModel`: publicar cambios dentro de una
actualización de vista hace que SwiftUI vuelva a renderizar en el acto. "Ir a línea" se colgaba
así, al 100 % de CPU, porque además limpiaba su petición con un `DispatchQueue.main.async` que ya
no llegaba a ejecutarse. De ahí dos reglas: la selección programática pasa por
`Coordinator.setSelectionWithoutReporting`, y **toda petición que la vista deba atender una sola
vez lleva identidad propia** (`ScrollRequest.id`) en vez de limpiarse desde la vista. Diagnóstico
completo en `docs/specs/fase3-ir-a-linea-bucle.md`.

Dos cosas que cuestan encontrar al tocar la UI, ambas en `docs/specs/fase6-pasada-ui.md`: un
`List` de SwiftUI pinta su **propio fondo opaco** y tapa cualquier material que haya detrás (hace
falta `.scrollContentBackground(.hidden)`); y `screencapture -l<id>` compone la ventana **sin el
escritorio detrás**, así que un `NSVisualEffectView` con `.behindWindow` sale como un relleno
plano — para evaluarlo hay que capturar la región de pantalla con `screencapture -R`.

Dos cosas de los menús: la lista de atajos de `ShortcutsWindow` **se escribe a mano** (SwiftUI no
deja enumerar los `.keyboardShortcut`), así que al añadir un atajo hay que añadirlo ahí; y un
`CommandGroup(after: X)` anclado a un grupo que otro `CommandGroup(replacing: X)` sustituye
**desaparece del menú sin avisar** — pasó con "Exportar diferencias", que existía en el toolbar y
no en el menú.

Zona de mayor riesgo, por si algo se ve raro: `LineNumberGutter.draw`.

## Plan

`docs/PLAN.md` tiene el plan por fases hasta la app completa, con lo que bloquea a qué y las
decisiones que quedan abiertas. **Léelo antes de proponer en qué trabajar.**

El estado de la app son **cinco objetos** desde que se cerró la Fase 8
(`docs/specs/fase8-partir-appmodel.md`): `Preferences` (todo lo que se persiste — la sangría vive
ahí porque la comparten dos modelos), `DocumentModel`, `ComparisonModel`, `NavigationModel`, y un
`AppModel` de 163 líneas que solo coordina. Ningún modelo conoce a los otros: las tres cosas que
cruzan —el cursor, enseñar un nodo y los cambios de sangría o de claves ignoradas— son cierres que
engancha `AppModel` en su `init`.

Cuatro cosas que ahorran un rato al tocar esto:

- **SwiftUI no propaga los `ObservableObject` anidados.** Cada vista declara un `@ObservedObject`
  por objeto que lee y los saca del modelo en su `init`. En los menús no vale: `.commands` solo
  observa el `@StateObject` de la `App`, así que cada grupo es una vista pequeña
  (`FileCommands`, `FindCommands`…). Sin eso los elementos se quedan con el estado del arranque,
  y no da la cara al compilar.
- **`@Published` publica en `willSet`**, así que un `sink` sobre `preferences.$indent` lee la
  sangría **vieja** justo cuando va a reformatear con ella. Los avisos salen del `didSet`.
- **Los `didSet` sí corren dentro de `init`** —las propiedades ya están inicializadas cuando el
  cuerpo les asigna lo cargado—, de ahí la bandera `isLoading` de `Preferences`. Sin ella,
  arrancar con una sangría guardada reformateaba el documento solo.
- Las rutas de `JSONNode`/`JSONChange` no llevan prefijo: la raíz es `$` y sus hijos son
  `envio.metodo`, no `$.envio.metodo`.

Fases 1, 2 y 3 cerradas (2026-09-02). Fases 4 y 5 cerradas también. Queda la Fase 6 (acabado: Liquid
Glass, icono, asociar `.json`, firma ad-hoc, menú de Ayuda), los opcionales de la Fase 3 (YAML,
CSV, generar tipos) y la Fase 7, que el propio plan dice no priorizar hasta que estorbe.

La conversión (Fase 3) vive en `JSONEscaping` y `JSONXML`, encima del formateador: ninguna de las
dos toca el parser ni el árbol. El XML tiene una convención de tipos propia para que la ida y
vuelta no pierda nada — está escrita en `docs/specs/fase3-xml.md`, léela antes de tocarlo.
