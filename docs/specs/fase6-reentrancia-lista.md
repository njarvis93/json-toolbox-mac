# Aviso de reentrancia en la lista del panel, y estado derivado

El usuario preguntó si había visto "Publishing changes from within view updates is not allowed,
this will cause undefined behavior". Buscándolo apareció **otro de la misma familia**, este sí
reproducible:

```
WARNING: Application performed a reentrant operation in its NSTableView delegate.
This warning will become an assert in the future.
```

## Cómo se aisló

Ejercitando la app con ganchos temporales y leyendo `stderr`:

- Disparando acciones **desde el modelo** (sangría, búsqueda, ámbito, comparar, exportar): ningún
  aviso.
- Disparando los **comandos de menú** de verdad (`performActionForItem`): ningún aviso.
- **Tecleando de verdad** en el campo de búsqueda —eventos de teclado dentro del proceso—: el
  aviso salta, y salta en la **primera tecla**.

Esa es la pista: en la primera tecla el árbol pasa de golpe de la vista normal a la filtrada, un
cambio estructural de toda la lista, **en la misma pasada** en la que el campo de texto escribe en
su binding.

Por el camino me engañé una vez: quité `expandedPaths.formUnion(...)` de `refreshSearch()`, el
aviso desapareció y lo di por resuelto. Era un falso positivo — sin esa línea el árbol filtrado se
quedaba casi vacío, así que no había cambio estructural que provocara nada. Se vio al mirar el
recuento de filas, no solo el aviso.

## El arreglo

**Recalcular la búsqueda en el siguiente turno del run loop** (`scheduleSearch`), no en el mismo.
Separa la escritura del binding del cambio de la lista, y de paso agrupa las teclas rápidas en un
único recálculo. Cero avisos, y la búsqueda se comporta igual: `precio` sigue dando 2
coincidencias con el árbol filtrado y desplegado.

## Lo que se cambió de fondo: sincronizar → derivar

Dos sitios mutaban estado publicado para mantener sincronizado algo que en realidad **se puede
calcular**:

- `refreshSearch()` rellenaba `expandedPaths` para abrir la rama de cada coincidencia.
- `syncTree(toUTF16:line:)` hacía lo mismo con los ancestros del cursor — y ese sí corre desde el
  aviso de cursor del editor, que puede caer dentro de una actualización de vista.

Ahora `expandedPaths` es `expansionOverrides: [String: Bool]` —**solo lo que el usuario ha tocado
a mano**— y `isExpanded(_:)` decide el resto: manda lo explícito, luego la cadena del cursor,
luego la búsqueda, y por defecto solo la raíz. Menos estado que mantener a mano y una mutación
menos en cada tecla.

## El "Publishing changes": el editor escribía en el modelo desde dentro del update

El usuario dio la lista de cuándo lo veía: cambiar entre Editor y Comparar, minificar, ordenar
claves, pegar, formatear, ⌃⌘E, y cambiar entre Entradas y Diferencias. **Todas cambian el texto o
recrean el editor**, y eso apuntaba a un solo sitio.

`JSONTextView.updateNSView`, al meter el texto nuevo, llamaba a `didChangeText()` — necesario para
que ⌘Z siga deshaciendo. Pero `didChangeText()` avisa al delegado de forma **síncrona**, y el
delegado hacía `parent.text = tv.string` y `reportCaret()`, que escribe otras tres propiedades
publicadas. Es decir: **cuatro escrituras en el modelo desde dentro de una actualización de
vista**, en cada una de las acciones de esa lista.

Arreglo: una bandera (`isApplyingModelText`) que hace que el delegado se calle cuando el texto lo
está poniendo el propio modelo — no hay nada que devolverle, porque ya coincide. Se conservan
`shouldChangeText`/`didChangeText`, así que el deshacer sigue registrándose.

**El primer intento no bastó** y el usuario lo confirmó: el aviso seguía en todos los casos. La
guarda solo cubría `textDidChange`, y falta la otra mitad — `replaceCharacters` **mueve la
selección por su cuenta**, eso dispara `textViewDidChangeSelection`, y ese delegado también llama
a `reportCaret()`, que escribe cinco propiedades publicadas (línea, columna, cadena del cursor,
nodo seleccionado). Ahora las dos guardas miran la misma bandera.

Comprobado que el camino sigue sosteniendo lo suyo: minificar deja 1 línea, formatear 34, ordenar
claves 34, escapar 1, desescapar 34, todos válidos; el cursor se sigue informando (queda en Ln19
con su nodo seleccionado) y deshacer restaura.

**Sin reproducción propia.** No se ha conseguido disparar el aviso desde aquí por ninguna vía:
acciones del modelo, tecleo real, comandos de menú, acciones de los `NSToolbarItem` y clics de
ratón sintéticos dentro del proceso. Los dos arreglos salen de leer el camino, no de verlo fallar,
y eso hay que decirlo: el primero ya se dio por bueno una vez y no lo era.

## Criterio de aceptación
1. Tecleando `precio` en el buscador: **cero** avisos de reentrancia y cero de publishing, contra
   uno antes. **Verificado** leyendo `stderr` del binario.
2. La búsqueda sigue igual: 2 coincidencias, 6 filas, árbol filtrado con los triángulos correctos.
   **Verificado** con captura.
3. `swift test` 168/168 y el proyecto compila.
