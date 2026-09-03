# Fase 8 — Tests de la capa de app (2026-09-02)

Hasta hoy los 168 tests eran todos de `JSONCore`: la capa de app tenía **cero**. Es lo que el
plan marcaba como bloqueante para partir `AppModel` en tres — mover estado entre objetos sin red
debajo es cómo se rompen cosas que nadie nota hasta usarlas.

Son **30 tests** en `JsonToolingApp/JsonToolingAppTests/AppModelTests.swift`, en XCTest, el mismo
framework que el núcleo.

## Cómo se ejecutan

```
xcodebuild -project JsonToolingApp/JsonToolingApp.xcodeproj -scheme JsonToolingApp \
  -destination 'platform=macOS' test
```

`swift test` sigue corriendo los 168 de `JSONCore` sin arrancar Xcode; estos necesitan el
proyecto, porque prueban un target de app.

## El target venía mal configurado

Xcode lo creó desde la plantilla de **tvOS**: `SDKROOT = appletvos`,
`TVOS_DEPLOYMENT_TARGET = 26.5`, `TARGETED_DEVICE_FAMILY = 3`, sin dependencia de la app y sin
host. Así no compila contra `JsonTooling`. Se corrigió a mano en `project.pbxproj`: `macosx` /
14.0, `TEST_HOST` + `BUNDLE_LOADER` apuntando al binario de la app, `SWIFT_DEFAULT_ACTOR_ISOLATION
= MainActor` como el target de la app, una `PBXTargetDependency` sobre `JsonToolingApp` y la
entrada correspondiente en `Testables` del esquema compartido. Si algún día se recrea el target
desde Xcode, comprobar esas cinco cosas antes de nada.

## `UserDefaults` inyectado

`AppModel.init(defaults:)` recibe dónde leer y escribir las preferencias; por defecto,
`.standard`. Cada test usa un suite propio con un UUID y lo borra al terminar: sin eso, ejecutar
los tests pisaría la sangría, las claves ignoradas y los documentos recientes del usuario real.

Al hacerlo salió algo que no se sabía: **los `didSet` sí corren dentro de `init`**. Las
propiedades tienen valor por defecto en su declaración, así que cuando el cuerpo del init les
asigna lo cargado ya están todas inicializadas y los observadores se disparan. Consecuencias
reales, no teóricas: leer `showTree` lo volvía a escribir, y cargar una sangría guardada
distinta de la de por defecto **reformateaba el documento al arrancar**, antes de que el usuario
tocara nada. De ahí la bandera `isLoading`, que los desactiva mientras se carga.

## Qué se fija

- **Editor**: formatear con la sangría elegida, que cambiar la sangría reindente al momento (el
  bug del selector que no hacía nada), minificar sin degradar `7.50` ni `90071992547409931`,
  ordenar claves, escapar/desescapar como ida y vuelta, y que una acción sobre un documento
  inválido no toque el texto.
- **Estado**: el error con su línea, que el último árbol bueno se conserve al romper el JSON, y
  el texto y el nivel de la barra de estado.
- **Árbol y búsqueda**: cursor → nodo con sus ancestros abiertos, nodo → petición de scroll,
  búsqueda por clave que filtra el árbol y **no** encuentra la palabra dentro de una cadena,
  el salto entre coincidencias con vuelta al principio, la consulta de ruta y el aviso de ámbito
  equivocado, desplegar y plegar todo.
- **Comparar**: que reordenar claves y cambiar espaciado no sean diferencias, el lado inválido
  informado con su letra, las claves ignoradas, saltar de diferencia en diferencia con vuelta,
  la fila alineada derivada de la selección, la selección que se limpia sola e intercambiar lados.
- **Persistencia**: round-trip de sangría, claves ignoradas y panel; que arrancar la app **no**
  escriba preferencias que nadie ha tocado; recientes sin repetidos, con tope de 8 y persistidos.

## Dos cosas que hay que saber al escribir más

- Las rutas de `JSONNode` y `JSONChange` **no** llevan prefijo: la raíz es `$`, y sus hijos son
  `envio.metodo`, `lineas[0].precio`. No `$.envio.metodo`.
- `AppModel` difiere a propósito la búsqueda (`scheduleSearch`) y el resaltado de la diferencia
  seleccionada (`revealSelectedChange`) al siguiente turno del run loop, para no publicar cambios
  dentro de una actualización de vista. Desde un test hay que dejar drenar la cola principal:
  el helper `drainMainQueue()`.
- `statusText` y `statusLevel` dependen de `mode`; para probar los de Comparar hay que ponerlo
  en `.compare`.
