# Plan de desarrollo

Meta: lo que dice el proyecto — **leer, editar, convertir, parsear, comparar y embellecer JSON**,
nativo, ligero, con estética macOS. Hoy hay cubierto leer, parsear, embellecer, comparar, editar
de verdad, convertir a string escapado y a XML, y navegar la estructura con un árbol sincronizado
con el texto (Fases 1-2 cerradas, Fase 3 en su criterio de cierre, Fase 4 empezada); falta la comparación avanzada.
Añadida la Fase 8 el 2026-09-02, a petición del usuario: ordenar la arquitectura de la app, que
había crecido en una sola clase.

Cada fase termina con algo usable. El orden es por prioridad de uso real, ajustado el 2026-09-02
a petición del usuario (convertir pasó por delante de navegación/comparación avanzada).

---

## Fase 1 — Que arranque · *cerrada*

Nada de lo demás importa hasta que la app abra.

- [x] `swift build` y arreglar lo que salga. Compila JSONCore y JsonToolingApp sin errores
      (2026-09-01).
- [x] Verificar visualmente el editor (2026-09-01). Era, en efecto, el sitio más probable de
      estar mal: con permiso de Screen Recording concedido por el usuario, capturando la ventana
      real por su window id (`screencapture -l<id>`, no solo `swift build`) se confirmó que el
      editor no mostraba ningún texto — solo los números de línea. Causa real: `LineNumberRuler`
      era un `NSRulerView` asignado a `NSScrollView.verticalRulerView`; en cuanto ese ruler
      dibujaba algo (hasta un `rect.fill()` trivial, sin tocar layout), el `NSTextView` vecino
      dejaba de componerse en pantalla — el contenido seguía existiendo (`cacheDisplay(in:to:)`
      lo pintaba bien offscreen) pero la ventana real nunca lo mostraba. Fix: la numeración de
      líneas pasó a ser una `NSView` normal (`LineNumberGutter`), hermana del `NSScrollView` en
      vez de su ruler. Detalle completo del diagnóstico en `docs/specs/fase2-undo.md`. Pendiente
      explícitamente sin verificar: scroll con documentos grandes, documento vacío, archivo que
      termina en salto de línea — se probó solo con el JSON de ejemplo (12 líneas).
- [x] `swift test` — 44/44 tests en verde tras corregir `xcode-select` (2026-09-01).
- [x] `git init`, commit inicial y push a
      [njarvis93/json-toolbox-mac](https://github.com/njarvis93/json-toolbox-mac) (2026-09-01).

**Termina cuando**: la app abre, valida, formatea y compara los dos documentos de ejemplo.
Arranca, corre estable, pasa los 44 tests y el editor se ve de verdad (2026-09-01). Cerrada.

---

## Fase 2 — Editor de verdad · *cerrada*

Ahora mismo es un visor con botones. Le faltan las cosas que hacen que se pueda vivir dentro.

- [x] **Arreglar el undo.** Implementado vía `shouldChangeText(in:replacementString:)` +
      `textStorage.replaceCharacters` + `didChangeText()` en `JSONTextView.updateNSView`
      (2026-09-01). Esto destapó un bug bloqueante de verdad (el editor no mostraba texto,
      ver Fase 1) que ya está arreglado y verificado visualmente: el contenido, el resaltado de
      sintaxis y el resaltado de la línea de error en rojo se ven correctamente. ⌘Z tras
      Formatear/Minificar **confirmado a mano por el usuario** el 2026-09-02.
- [x] ⌘S sobre el archivo abierto, no solo "Guardar como". `AppModel.fileURL`/`isDirty` +
      `save()`/`saveAs()`, aviso al cerrar en `AppDelegate.applicationShouldTerminate`
      (2026-09-01). **Confirmado a mano por el usuario** el 2026-09-02
      (ver `docs/specs/fase2-guardar.md`).
- [x] Documentos recientes en el menú Archivo. `AppModel.recentDocuments` persistido en
      `UserDefaults` + submenú "Abrir reciente" (2026-09-01). Parcialmente verificado: al
      revisar `defaults read JsonTooling` en uso real del usuario, `recentDocuments` sí tenía el
      archivo que había abierto — el mecanismo de guardado funciona. El submenú "Abrir
      reciente" lo **confirmó a mano el usuario** el 2026-09-02
      (ver `docs/specs/fase2-recientes.md`).
- [x] Ir a línea (⌘L), y clic en el mensaje de error de la barra de estado → salta a esa posición.
      `AppModel.goTo(line:)` + `JSONTextView` scroll-to-line + `promptGoToLine()` (2026-09-01).
      **Estaba roto**: colgaba la app en un bucle de render al 100 % de CPU. Reportado por el
      usuario y arreglado el 2026-09-02 (petición con identidad + selección programática que no
      informa del cursor dentro del update), verificado con capturas de la ventana real y
      **confirmado a mano por el usuario** el 2026-09-02: ⌘L funciona. Detalle
      en `docs/specs/fase3-ir-a-linea-bucle.md`; comportamiento en `docs/specs/fase2-ir-a-linea.md`.
- [x] Recordar sangría y tamaño de ventana entre lanzamientos. **El selector de sangría no
      aplicaba nada al documento** (solo guardaba la preferencia y afectaba al siguiente
      Formatear): reportado por el usuario y arreglado el 2026-09-02. `indent` en `UserDefaults`
      (2026-09-01). El intento inicial de recordar el tamaño de ventana
      (`NSWindow.setFrameAutosaveName`) se quitó: era redundante con la restauración nativa de
      `WindowGroup` en SwiftUI y competía con ella por el mismo frame — ver
      `docs/specs/fase2-undo.md`. El round-trip de la sangría lo **confirmó a mano el usuario**
      el 2026-09-02 (ver `docs/specs/fase2-persistencia.md`).
- [x] Hueco en blanco en la pantalla Comparar (reportado por el usuario, con captura). Causa:
      `Divider()` entre dos vistas custom con `.frame(height:)` propio (`PaneHeader`, y también
      `DiffCell` en la vista de diferencias) — SwiftUI infla la altura del `HStack` que las
      envuelve. Fix: separador con altura fija en vez de `Divider()`. Verificado visualmente con
      capturas de ventana reales (2026-09-01). Detalle en `docs/specs/fase2-comparar-hueco.md`.
- [x] Toolbar con iconos nativos agrupados en píldora (`ControlGroup`, estilo Notas de macOS,
      a petición del usuario en vez del prototipo original) (2026-09-01). Verificado visualmente.

**Termina cuando**: se puede abrir un JSON, arreglarlo y guardarlo sin salir de la app. Hecho, y
con la pasada manual del usuario completa el 2026-09-02 (de ahí salió el bug de ⌘L:
`docs/specs/fase3-ir-a-linea-bucle.md`). Cerrada de verdad.

---

## Fase 3 — Convertir · *criterio de cierre cumplido; quedan los opcionales*

Reordenada por delante de navegación/comparación avanzada (2026-09-02, a petición del usuario):
es lo que más falta en el uso diario, y ninguna pieza bloquea a las demás.

- [x] **JSON ↔ string escapado.** Lo principal de la fase. `JSONEscaping` en JSONCore + menú
      **Convertir** con "Escapar como string" (⌃⌘E) y "Desescapar string" (⌃⌘U) (2026-09-02).
      Lo escapado sigue siendo JSON válido (una cadena en la raíz), así que se queda en el editor
      sin ponerlo en rojo. Desescapar acepta tanto el literal con comillas como el cuerpo suelto
      copiado de un log. 12 tests en verde y **confirmado a mano por el usuario** el 2026-09-02
      (ver `docs/specs/fase3-escapado.md`).
- [x] **JSON ↔ XML.** `JSONXML` en JSONCore + "Copiar como XML" / "Pegar desde XML"
      (2026-09-02). Alcance decidido al llegar: **las dos direcciones**, con una convención
      explícita de tipos (`type="number|bool|null|object|array"`, arrays con `<item>`, claves no
      válidas como `<entry key="…">`) para que la ida y vuelta no pierda nada; el XML escrito a
      mano sin anotar se infiere por la forma y sus escalares llegan como cadenas. El XML va al
      portapapeles y no al editor: el editor es de JSON. Fuera de alcance a propósito:
      namespaces, texto mixto, CDATA. 17 tests en verde y **confirmado a mano por el usuario** el
      2026-09-02, con un documento que traía entero > 2^53, `7.50`, exponencial, emoji, claves no
      válidas como nombre XML, y XML pegado de fuera sin anotar (ver `docs/specs/fase3-xml.md` y
      `Ejemplos/`).
- [ ] JSON → YAML y YAML → JSON. Opcional, menor prioridad que lo anterior. **Decisión
      pendiente**: escribir un emisor/parser mínimo o aceptar Yams como primera dependencia
      externa. YAML completo es mucho más grande de lo que parece; probablemente convenga
      soportar un subconjunto propio y decirlo claramente.
- [ ] JSON ↔ CSV para arrays de objetos planos, con aplanado configurable de anidados. Opcional.
- [ ] Generar tipos: `struct` de Swift con `Codable`, y clases Java y Go. Opcional; necesita
      inferir tipos opcionales viendo varios elementos de un array (el árbol con rangos de la
      fase de navegación estructural no hace falta para esto).

**Termina cuando**: se puede convertir un JSON a string escapado y de vuelta sin salir de la app.
Lo demás (XML, YAML, CSV, generación de tipos) es una mejora incremental sobre eso, en ese orden.
Hecho el escapado y además el XML (2026-09-02): el criterio de cierre se cumple. Quedan abiertos
YAML, CSV y la generación de tipos, los tres marcados como opcionales desde el principio.

---

## Fase 4 — Navegación estructural · *cerrada*

La pieza que convierte "ver el texto" en "entender el documento". **Requiere un cambio en JSONCore**:

> Hoy `JSONValue` no guarda de dónde vino. Para sincronizar árbol y texto (clic en un nodo →
> selecciona su rango; cursor en el texto → resalta su nodo) cada valor necesita llevar su rango
> de tokens. Es un cambio que toca el parser entero, así que conviene hacerlo **antes** de que
> haya más código encima, y con los tests actuales de red.

- [x] `JSONValue` con rango asociado, o un árbol paralelo de nodos posicionados. **Árbol paralelo**
      (`JSONNode`), decidido al llegar: meter el rango dentro de `JSONValue` contaminaría la
      igualdad de la que depende `JSONDiff`. El parser construye valor y nodo en el mismo
      recorrido; las rutas usan el mismo formato que `JSONChange.path`, para poder saltar del
      diff al árbol en la Fase 5 (2026-09-02).
- [x] Vista de árbol colapsable en un panel lateral. Filas aplanadas a mano en vez de
      `OutlineGroup`: el despliegue tiene que poder abrirse desde fuera. ⌃⌘S y botón al principio
      del toolbar, donde macOS pone el de los paneles laterales — a petición del usuario, que
      quería el icono además del atajo (2026-09-02).
- [x] Sincronización bidireccional árbol ↔ texto (2026-09-02). Verificada en la app real, en los
      dos sentidos, con capturas de ventana. Lo fino está en qué nodo señala el cursor cuando
      está en la sangría: ver `docs/specs/fase4-arbol.md`.
- [x] Buscar por clave y por valor, con recuento de coincidencias. `JSONSearch` sobre el árbol,
      no sobre el texto: es lo que distingue la clave `precio` de la palabra "precio" dentro de
      una cadena. Ámbito Todo/Claves/Valores, sin distinguir mayúsculas ni tildes, ⌘F para buscar
      y ⌘G / ⇧⌘G para saltar; el árbol se filtra a las coincidencias y sus ancestros y se
      despliega solo (2026-09-02, ver `docs/specs/fase4-buscar.md`).
- [x] Consultas JSONPath (subconjunto: `$.a.b[0]`, `..clave`, filtros simples). Escrito a mano
      sobre el árbol, sin dependencia. Admite `$`, `.clave`, `['clave']`, `[2]`, `[-1]`, `.*`,
      `[*]`, `..clave`, `..*` y filtros `[?(@.clave op valor)]`. No hay campo nuevo: el ámbito
      del buscador gana la opción "Ruta", así que reutiliza recuento, ⌘G y árbol filtrado
      (2026-09-02, ver `docs/specs/fase4-jsonpath.md`). **Confirmado a mano por el usuario** el
      2026-09-02 sobre `Ejemplos/consultas.json`; de ahí salieron dos límites del subconjunto que
      no estaban escritos (filtro con ruta anidada y filtro sobre un objeto), ahora en la spec.

**Termina cuando**: se puede navegar un documento de 3.000 líneas sin hacer scroll a ciegas.
Hecho (2026-09-02): árbol sincronizado con el texto, búsqueda por clave/valor y consultas de ruta.
Cerrada, con la pasada manual del usuario hecha el 2026-09-02.

---

## Fase 5 — Comparación avanzada · *cerrada*

El diff estructural ya está; lo que falta es trabajar *con* las diferencias.

- [x] Clic en una fila de la tabla → salta y resalta esa línea en las dos columnas. El enganche
      sale gratis de la Fase 4: las rutas de `JSONChange` y `JSONNode` son el mismo formato, así
      que ruta → línea del documento formateado → fila alineada (2026-09-02).
- [x] Saltar a la diferencia siguiente/anterior (⌘G / ⇧⌘G), reusando el mismo par de atajos que
      las coincidencias del editor, con el título del menú según la pantalla (2026-09-02, ver
      `docs/specs/fase5-navegar-diferencias.md`).
- [x] **Emparejar elementos de array por clave, no por índice** (2026-09-02). Se coge la primera
      clave candidata que de verdad identifica —presente en todos los elementos, escalar y sin
      repetirse, en los dos arrays—; si no hay ninguna, se compara por posición como antes. El
      caso que lo motivaba pasa de **8 diferencias a 2**, con un test que fija las dos cifras.
      Reordenar sí es una diferencia (tipo `movido`), pero desplazarse por una inserción no: se
      mira el orden relativo con una subsecuencia común más larga. Ver
      `docs/specs/fase5-emparejar-arrays.md`.
- [x] Formatear cada entrada desde su cabecera en la vista de Entradas, más el selector de
      sangría en esa pantalla (2026-09-02, pedido por el usuario: pegar una respuesta minificada
      dejaba esa vista inservible, que es justo donde se miran arrays de objetos grandes).
- [x] Ignorar claves en la comparación (timestamps, versiones) con una lista editable
      (2026-09-02). Por nombre y a cualquier profundidad, en `DiffOptions.ignoredKeys`, con la
      lista en un popover del toolbar y **siempre visible** que se está ignorando algo: en el
      icono, en la línea de resumen y en el volcado exportado. Dos respuestas de API reales pasan
      de 5 diferencias a 1. Ver `docs/specs/fase5-ignorar-y-exportar.md`.
- [x] Exportar el diff como texto para pegarlo en un ticket (2026-09-02). Dos formatos a
      petición del usuario: **texto plano** con columnas alineadas y **Markdown** en tabla. En el
      toolbar de Comparar y en el menú Archivo; copia al portapapeles. Ver
      `docs/specs/fase5-ignorar-y-exportar.md`.

**Termina cuando**: comparar dos respuestas de API reales no produce ruido. Hecho (2026-09-02):
el emparejado por clave quita el ruido de las inserciones y la lista de claves ignoradas el de los
campos que cambian solos. **Confirmado a mano por el usuario** el 2026-09-02 con dos respuestas de
API (`Ejemplos/api-respuesta-A.json` y `-B`): 12 diferencias sin ignorar nada, 9 ignorando las tres
claves de `meta`, y la línea insertada al principio cuenta como dos diferencias y no cinco.

---

## Fase 6 — Acabado · *es lo siguiente*

Era la Fase 7; se intercambió con "levantar el techo de los 10 MB" el 2026-09-02 a petición del
usuario, porque el acabado se necesita antes que el rendimiento.

- [~] **Primera pasada de UI hecha el 2026-09-02**, a petición del usuario ("se ve desprolija"
      tras añadir el panel): material de barra lateral de verdad en el panel —panel y editor eran
      el mismo blanco en claro, medido—, iconos que significaban dos cosas a la vez, campo de
      búsqueda con aspecto de campo, filas del árbol con dos puntos y selección con margen, y
      limpieza de Comparar (título duplicado, enlaces de texto, texto de folleto). Detalle y lo
      que se dejó fuera en `docs/specs/fase6-pasada-ui.md`.
- [x] **Liquid Glass revisado el 2026-09-02.** La app ya lo tiene: compilando contra el SDK de
      macOS 26 los controles del toolbar adoptan el material solos. Las API (`glassEffect`,
      `GlassEffectContainer`, `.buttonStyle(.glass)`) están disponibles y se comprobó que
      compilan, pero no se usan: el cristal es para controles que flotan sobre el contenido, no
      apilado sobre superficies que ya son material. En la pasada salieron dos arreglos: el botón
      de Formatear deja de ser un círculo azul suelto y la tabla de diferencias se puede agrandar.
      Queda como referencia lo que había apuntado originalmente:
      revisar tamaños, sombras y proporciones del toolbar, los paneles y los controles —
      materiales translúcidos, radios de esquina y elevación consistentes con macOS actual — en
      vez de las medidas heredadas de `docs/prototipo-ux.html`. El toolbar con `ControlGroup` en
      píldora ya va en esa dirección; falta revisar el resto de la app con el mismo criterio.
- [x] Icono (2026-09-02). Se dibuja en `Scripts/make-icon.swift` en vez de guardar solo el
      `.icns`; probado a 32 px, que es donde se decide.
- [x] Asociar la app a `.json` para abrir con doble clic (2026-09-02). `LSHandlerRank` es
      `Alternate` y no `Owner` a conciencia: reclamar todos los `.json` del sistema le quitaría
      la asociación al editor que ya la tenga.
- [x] Firma ad-hoc y `xattr -d com.apple.quarantine` (2026-09-02), en `Scripts/make-app.sh`.
      Ver `docs/specs/fase6-app-de-verdad.md`.
- [x] Menú de Ayuda con los atajos (2026-09-02), en una ventana propia (⌘/). De paso salió que
      "Exportar diferencias" **no aparecía en el menú Archivo**: estaba en un
      `CommandGroup(after: .saveItem)` anclado a un grupo que se reemplaza ahí mismo, así que
      desaparecía sin decir nada. El botón del toolbar sí funcionaba, por eso no se notaba.

---

## Fase 7 — Levantar el techo de los 10 MB · *sin prioridad*

**Irrelevante por ahora (2026-09-02)** — no priorizar hasta que de verdad estorbe en uso real.
El límite actual es una decisión consciente, no una limitación de fondo:

- [ ] Resaltado incremental: retokenizar solo el rango visible más un margen, en vez del documento
      entero en cada pulsación. Sube el techo de los 512 KB actuales.
- [ ] Parseo y diff fuera del hilo principal, con cancelación al seguir escribiendo.
- [ ] Parseo incremental que reaproveche los tokens no tocados.

**Termina cuando**: un volcado de 50 MB se abre y se navega sin bloquear la ventana.

---

## Fase 8 — Arquitectura de la app · *cerrada*

Salió de una pregunta del usuario el 2026-09-02: `AppModel` "se siente mucho en una sola clase".
Tenía razón, y el orden que pidió es el correcto: **primero quitar lo redundante, luego reordenar
lo que queda**. Partir una clase que por dentro mantiene estado sincronizado a mano solo reparte
el problema entre más archivos.

- [x] **Quitar el estado que se mantenía sincronizado a mano** (2026-09-02). `revalidate()`
      escribía tres propiedades publicadas a la vez y `recompare()` siete; ahora son dos valores
      (`EditorParse` y `Comparison`), `compare()` devuelve la comparación entera en vez de irla
      escribiendo, y `highlightedAlignedRow` se deriva. De 37 propiedades publicadas a 30, sin
      tocar ni una vista. Ver `docs/specs/fase6-appmodel-redundancia.md`.
- [x] **Tests de la capa de app** (2026-09-02). El usuario creó el target y de ahí salieron
      **30 tests** en `AppModelTests.swift`: editor (formatear, minificar, sangría, ordenar,
      escapado), árbol y búsqueda, comparación y persistencia. El target venía de la plantilla
      de **tvOS** y no compilaba contra la app; se corrigió el `project.pbxproj` (host, SDK,
      dependencia) y el esquema. `UserDefaults` pasa a inyectarse en `AppModel` para que los
      tests no pisen las preferencias reales — y ahí salió que **los `didSet` sí corren dentro
      de `init`**: cargar una sangría guardada reformateaba el documento al arrancar. Ver
      `docs/specs/fase8-tests-de-app.md`.
- [x] **Partir `AppModel`** (2026-09-02). Salieron **cuatro** objetos y no tres: `Preferences`
      (todo lo que se persiste), `DocumentModel`, `ComparisonModel` y `NavigationModel`, con
      `AppModel` reducido de 860 a 163 líneas de coordinación. El cuarto es por la sangría, que
      comparten documento y comparación: dejarla en uno obligaba al otro a llevar una copia
      sincronizada a mano. El coste anticipado se pagó donde decía el plan —cada vista declara
      un `@ObservedObject` por objeto que lee— y además en los menús, que pasaron a ser vistas
      pequeñas porque `.commands` solo observa el `@StateObject` de la `App`. De paso salió que
      **`@Published` publica en `willSet`**, así que un `sink` sobre la sangría la lee vieja: los
      avisos van por `didSet`. 33 tests en verde y la app verificada en pantalla. Ver
      `docs/specs/fase8-partir-appmodel.md`.
Se descartó la alternativa barata que estaba apuntada (partir el archivo en extensiones por tema
sin tocar las vistas): con la red de tests puesta, el corte de verdad salió más barato de lo que
costaba dejar una sola clase.

**Termina cuando**: tocar una parte de la app no obliga a leer las otras dos. Hecho (2026-09-02).

## Decisión tomada: proyecto de Xcode (2026-09-02)

Era la decisión aparcada del principio. Se migró cuando se cumplieron dos de los cuatro
disparadores que estaban listados —asociación de tipos de archivo y distribuir a alguien más— y
después de que los scripts fallaran tres veces en un día.

`Package.swift` se queda con `JSONCore` y sus tests, que siguen corriendo con `swift test` sin
arrancar Xcode; `JsonToolingApp/JsonToolingApp.xcodeproj` construye la app consumiendo el paquete
como dependencia local. `Scripts/make-app.sh` y `run.sh` desaparecen, `package.sh` se reescribe
sobre `xcodebuild`. Detalle en `docs/specs/fase6-migracion-xcode.md`.

Lo que sigue **sin** hacerse, y por lo que habría que volver aquí: *entitlements*, sandbox y firma
con cuenta de desarrollador para notarizar.

## Lo que se decidió dejar fuera

Servidor local, plugins, sincronización, colaboración, temas personalizables. El proyecto es una
herramienta ligera de uso personal; cada una de esas cosas la convierte en otra cosa.
