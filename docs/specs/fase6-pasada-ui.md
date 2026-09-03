# Pasada de UI (2026-09-02)

Adelanto de la Fase 6 (era la 7 hasta que se renumeraron el 2026-09-02). El usuario dijo que la app "se ve desprolija" tras añadir el panel de
estructura; esto es lo que salió de revisarla con capturas de la ventana real, en claro y en
oscuro, y contra `docs/prototipo-ux.html`.

## 1. El panel no parecía un panel

Lo que más ensuciaba, y era medible: el fondo del panel y el del editor eran **prácticamente el
mismo color**. Muestreando píxeles de la ventana real:

| | panel | editor |
|---|---|---|
| Oscuro | `#222324` | `#1E1F1E` |
| Claro | `#FFFFFF` | `#FFFFFF` |

En claro, idénticos. Lo único que los separaba era una línea de 1 px, así que el árbol se leía
como una columna de texto flotando sobre la misma superficie del editor.

Arreglo: `VisualEffectBackground`, un `NSVisualEffectView` con material `.sidebar` — que es lo que
usan las barras laterales de macOS y no se puede pedir con un `Color` en SwiftUI. Queda
`#CBCBCC` contra `#FFFFFF` en claro y `#262627` contra `#1E1F1E` en oscuro.

**Detalle que costó encontrar**: no bastaba con poner el material de fondo. El `List` de dentro
pinta su propio fondo opaco y lo tapaba entero — hace falta `.scrollContentBackground(.hidden)`.
Los primeros intentos medían exactamente los mismos colores de antes.

**Cómo medirlo**: `screencapture -l<id>` compone la ventana **sin el escritorio detrás**, así que
un material `.behindWindow` sale como un relleno plano y no se puede evaluar. Hay que capturar la
región de pantalla (`screencapture -R x,y,w,h`) con la ventana delante.

## 2. Iconos que significaban dos cosas

- `arrow.down.right.and.arrow.up.left` era **a la vez** "Minificar" en el toolbar y "Plegar todo"
  en el panel. El panel pasa a `rectangle.compress.vertical` / `rectangle.expand.vertical`, que
  además a 10 pt se distinguen entre sí (las dos flechas diagonales opuestas, no).
- "Pegar" (`doc.on.clipboard`) y "Copiar" (`doc.on.doc`) eran los dos dos documentos
  superpuestos, a pocos píxeles uno de otro. Pegar pasa a `clipboard`, que tiene otra silueta.

## 3. Panel: campo de búsqueda y filas

- El campo de búsqueda era `.plain` sin fondo: parecía una etiqueta con una lupa al lado. Ahora
  lleva cápsula redondeada con borde, como un campo de verdad.
- Las filas no separaban clave de valor (`pedidoId "4471-AC"`). Se añaden los dos puntos. Los
  elementos de array no llevan: su etiqueta es el índice y `0: { … }` no aporta.
- La selección llegaba a sangre hasta los dos bordes del panel; ahora va con margen y esquinas
  redondeadas, como en las barras laterales de macOS.
- **Se mantiene la fuente monoespaciada** en el árbol: decisión explícita del usuario, le gusta
  que parezca código.
- Salió de paso un defecto real: durante una búsqueda las filas se veían desplegadas pero el
  triángulo apuntaba a "plegado", y plegar no hacía nada. El árbol filtrado ignoraba
  `expandedPaths`. Ahora `refreshSearch` abre de antemano la rama de cada coincidencia y el
  filtrado respeta lo desplegado, así que el triángulo dice la verdad y plegar funciona.

## 4. Comparar

- El título se veía **dos veces**: el selector de modo dice "Comparar" y el `navigationTitle`
  lo repetía al lado. Se quita el título en ese modo.
- El botón del panel lateral seguía en el toolbar, deshabilitado, ocupando sitio para nada. Ahora
  solo existe en el editor.
- "Importar" y "Pegar" eran enlaces de texto azules, otro idioma distinto para las mismas dos
  acciones que en el editor son iconos. Pasan a los mismos iconos.
- Fuera "Comparación semántica por ruta, no por texto": texto de folleto heredado del prototipo,
  permanente en la barra.

## Segunda pasada (2026-09-02, tarde)

**El botón de Formatear deja de ser un círculo azul.** Un botón suelto en el toolbar de macOS sale
**redondo**, así que era la única forma circular y el único color saturado de la ventana. Se probó
`.buttonStyle(.glassProminent)` —el prominente de macOS 26— y sigue siendo un círculo azul; y
macOS no deja ponerle etiqueta de texto en el toolbar (`.labelStyle(.titleAndIcon)` se ignora).

Solución: meterlo en el mismo `ControlGroup` que Minificar, Ordenar claves y Copiar, que es donde
pertenece —las cuatro son transformaciones del documento— y va el primero. Pierde énfasis visual;
mantiene ⇧⌘F y el tooltip.

**La tabla de diferencias se puede agrandar.** Tenía 190 pt fijos: cinco filas y sin forma de ver
más en una lista larga. Ahora va en un `VSplitView` con divisor arrastrable. El reparto inicial
sale a medias: `idealHeight` lo ignora y `layoutPriority` se va al otro extremo (deja la tabla en
dos filas), así que a medias es lo mejor de los tres.

**Sobre Liquid Glass**: la app ya lo tiene. Compilando contra el SDK de macOS 26, los controles
estándar del toolbar adoptan el material solos, y así se ve en las capturas. `glassEffect`,
`GlassEffectContainer` y `.buttonStyle(.glass)` están disponibles y se comprobó que compilan, pero
no se han usado: la guía de Apple es que el cristal va en controles que flotan sobre el contenido,
no apilado sobre superficies que ya son material —y el panel lateral ya usa el suyo, el de barra
lateral del sistema.

## Lo que se dejó sin tocar
- Las tres barras apiladas del panel siguen con alturas distintas (28 / 32 / 26). Se ve bien en las
  capturas; si algún día molesta, unificarlas.
- El reparto inicial del `VSplitView` de Comparar no se puede fijar sin bajar a `NSSplitView`.

## Verificación

Capturas de la ventana real en claro y en oscuro, en editor y en Comparar, con y sin búsqueda
activa; y muestreo de píxeles para los fondos. 105/105 tests en verde (no toca lógica, pero el
cambio del árbol filtrado sí es comportamiento).

Manual, pendiente: pasar el ratón por los controles nuevos y comprobar el material del panel con
la ventana sobre distintos fondos de escritorio.
