# Spec: navegar las diferencias

Primer trozo de la Fase 5: clic en una fila de la tabla → salta y resalta esa línea en las dos
columnas, y ⌘G / ⇧⌘G para moverse entre diferencias.

## De una ruta a una fila de la pantalla

El enganche sale gratis por una decisión de la Fase 4: **las rutas de `JSONChange` y las de
`JSONNode` son el mismo formato**, a propósito. El camino es:

1. La diferencia trae su ruta (`envio.seguimiento`).
2. Se busca esa ruta en el árbol del documento **ya formateado** y se saca su línea.
3. Se busca la fila alineada que lleva ese número de línea.

El paso 2 usa un árbol nuevo, no el de `textA`/`textB`: las posiciones de esos documentos valen
para el texto original, y en las columnas se ve el texto **formateado**. Así que `recompare()`
parsea también las dos versiones formateadas y guarda sus raíces.

Si la diferencia es un **añadido**, no existe en A: se prueba en A y, si no está, en B, mirando
`rightNumber` en vez de `leftNumber`.

## Comportamiento
- Clic en una fila de la tabla: la vista alineada hace scroll a esa línea y la pinta con el color
  de selección **en las dos columnas**, por encima del rojo/verde de eliminado/añadido — si no,
  no se distinguiría de las otras nueve diferencias de la pantalla.
- ⌘G / ⇧⌘G: siguiente y anterior, dando la vuelta al llegar al final. Es **el mismo par de
  atajos** que en el editor: un solo elemento de menú que hace lo que toca según la pantalla, con
  el título cambiando entre "Coincidencia" y "Diferencia". Dos ⌘G distintos chocarían.
- El recuento "N de M" sale a la derecha de la barra de resumen.
- Estando en la vista de Entradas, elegir una diferencia cambia a Diferencias: si no, el
  resaltado ocurriría en una vista que no se está mirando.

## Dos cosas que había que comprobar, no suponer
- **`ScrollViewReader` sí funciona con `Table`.** No está documentado que lo haga; se probó y la
  tabla salta a la fila seleccionada. Sin eso, con ⌘G la selección se iba de la pantalla y la
  tabla se quedaba enseñando las primeras filas.
- **Al llegar desde Entradas, `onChange` no basta.** La vista alineada todavía no existe cuando
  se pide el scroll, así que hay que atender también en `onAppear` la petición que ya venía
  puesta (con un turno de run loop de por medio).

## Casos límite
- Si el documento cambia y la diferencia seleccionada deja de existir, se limpia la selección.
- Una ruta que no se encuentra en ninguno de los dos árboles no rompe nada: no hay resaltado.
- La petición de scroll lleva identidad, por lo mismo que `ScrollRequest` — ver
  `docs/specs/fase3-ir-a-linea-bucle.md`.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 130/130 el 2026-09-02.
2. Recorrer las diferencias del documento de ejemplo y comprobar que cada una cae en la línea
   correcta. **Verificado**: `estado` → fila 2, `cliente.canal` → 8, `envio.transportista` → 14,
   `envio.seguimiento` (añadido, solo en B) → 18, `totales.total` → 38.
3. Resaltado en las dos columnas y scroll a la fila. **Verificado** con capturas.
4. Llegar a una diferencia desde la vista de Entradas. **Verificado** con captura.
5. Manual, pendiente: hacer clic en las filas con el ratón y usar ⌘G / ⇧⌘G con el teclado.
