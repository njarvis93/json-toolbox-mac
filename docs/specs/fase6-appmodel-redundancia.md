# `AppModel`: quitar lo que se mantenía sincronizado a mano

Primer paso del encargo del usuario ("elimina lo redundante y luego reordenas lo que queda"). No
se ha movido nada de sitio todavía: solo se ha quitado estado que no hacía falta guardar.

## Lo que se encontró

Lo redundante no eran propiedades sueltas, sino **grupos que siempre se escriben juntos**:

- `revalidate()` escribía `editorError`, `nodeCount` y `rootNode` — tres propiedades publicadas
  que solo tienen sentido a la vez.
- `recompare()` escribía siete: `changes`, `alignedRows`, `compareError`, `validA`, `validB`,
  `prettyRootA` y `prettyRootB`.
- `highlightedAlignedRow` se mantenía en paralelo a `selectedChangeID`, y había que acordarse de
  limpiarla en dos sitios.

Mantener eso a mano es de donde salieron los dos fallos del día: estado publicado que se muta en
cascada, y combinaciones imposibles mientras se construye (árbol nuevo con recuento viejo).

## Lo que se hizo

Dos valores en vez de diez propiedades:

```swift
struct EditorParse { var root: JSONNode?; var nodeCount: Int; var error: JSONError? }
struct Comparison  { var changes; var rows; var error; var validA; var validB; var prettyA; var prettyB }
```

`compare()` **devuelve** la comparación entera en vez de ir escribiendo propiedades, así que no
hay estados a medias mientras se calcula. Y `highlightedAlignedRow` pasa a **derivarse** de la
diferencia seleccionada.

Los nombres antiguos siguen existiendo como propiedades calculadas (`rootNode`, `nodeCount`,
`editorError`, `changes`, `alignedRows`, `compareError`, `validA`, `validB`), así que **ninguna
vista ha cambiado**. Eso era lo que hacía el cambio barato y seguro sin tests de la capa de app.

De 37 propiedades publicadas a 30.

## Verificación

Sin tests de la capa de app, se ejercitó la app entera bajo `lldb` con la receta de
`fase6-publishing-changes.md`: minificar, formatear, ordenar claves, escapar, desescapar, buscar
por texto, buscar por ruta, limpiar, comparar, saltar dos diferencias, ignorar claves, exportar y
volver al editor. Todo con los mismos números que antes (27 nodos, 14 filas de árbol, 2
coincidencias, la fila resaltada saltando de la 8 a la 12) y **cero avisos**.

De paso se limpiaron dos preferencias que mis pruebas habían dejado en la app real
(`ignoredKeys = estado` e `indentStyle = 4 espacios`).

## Lo que queda

Reordenar lo que queda: `AppModel` sigue siendo una sola clase con documento, comparación,
navegación y búsqueda dentro. Con los dos valores agregados ya hechos, el corte natural es más
evidente.
