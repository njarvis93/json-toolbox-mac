# Spec: emparejar arrays por clave de identidad

El defecto conocido del diff, arreglado. Hasta ahora `JSONDiff` comparaba `a[0]` con `b[0]`:
insertar un elemento al principio desplazaba todo y marcaba el array entero.

## Lo que se gana, medido

El caso que motivaba el cambio —un pedido al que se le mete una línea nueva al principio y se le
cambia la cantidad de otra— pasa de **8 diferencias a 2**, y las 2 son las reales. Hay un test que
fija las dos cifras, para que se vea la diferencia y no se pierda si alguien toca esto.

## Cuándo se empareja por clave

Solo cuando es seguro. Se recorre la lista de nombres candidatos (`id`, `uuid`, `guid`, `_id`,
`key`, `clave`, `sku`, `code`, `codigo`, `ref`, `slug`) y se coge **la primera que de verdad
identifica**, lo que exige las tres cosas a la vez, en los dos arrays:

1. estar presente en **todos** los elementos,
2. tener valor **escalar** (`null`, objetos y arrays no identifican),
3. **no repetirse** dentro de su array.

Si ninguna cumple, se compara por posición, que es lo que se hacía antes y sigue siendo lo
correcto para arrays de escalares o de objetos sin identificador. La lista es configurable
(`DiffOptions.identityKeys`), que es por donde entrará la lista editable de la interfaz.

Los identificadores numéricos se comparan **por su literal**, no como `Double`: un id de más de
2^53 no puede pasar por `Double` sin arriesgarse a confundir dos elementos distintos. Es la misma
razón por la que el formateador no toca los literales.

## Reordenar sí es una diferencia, pero desplazarse no

Un array de JSON está ordenado, así que un cambio de orden es una diferencia de verdad y se
informa: tipo **`movido`**, con el índice de origen y el de destino en las columnas A y B (en un
movido el valor es el mismo a los dos lados; lo que interesa ver es de dónde a dónde).

La parte delicada es no confundir *moverse* con *desplazarse*. Insertar un elemento al principio
cambia el índice de todos los demás, y marcarlos a todos como movidos sería exactamente el ruido
que se venía a quitar. Así que se mira el **orden relativo**: se calcula la subsecuencia común más
larga entre el orden en que aparecen los emparejados en A y el orden en que aparecen en B; los que
están en ella se consideran quietos y solo los demás son movidos. Por eso una inserción o una
eliminación no generan ningún `movido`.

La detección es cuadrática, así que por encima de `DiffOptions.maxMoveDetection` (500 elementos
emparejados) no se buscan reordenaciones. Las diferencias de contenido se siguen dando.

## La ruta de una diferencia

`JSONChange` tiene una sola ruta y un elemento movido tiene dos. Se usa **la de A** (y la de B
cuando el elemento solo existe en B, que es el caso de los añadidos). Es lo que necesita la
navegación de `fase5-navegar-diferencias.md` para localizarlo en la columna izquierda.

Las diferencias salen en orden de A, y los añadidos al final. No es orden de documento estricto;
si algún día molesta al navegar con ⌘G, hay que ordenarlas al terminar.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 150/150 el 2026-09-02, 20 de ellos de
   emparejado. Los 130 anteriores pasan sin tocarlos.
2. Insertar al principio no marca el array entero; quitar del medio tampoco. **Verificado** en
   los tests y en la app: dos ficheros de pedido reales dan `added lineas[0]` y
   `modified lineas[1].cantidad`, nada más.
3. Una reordenación de verdad sale como `movido` con sus índices, y el resumen las cuenta aparte.
   **Verificado** con captura de la ventana real.
4. Sin clave de identidad, con ids repetidos, con la clave ausente en algún elemento, con `null`
   o un objeto como id, y en arrays de escalares: se compara por posición. **Cubierto por tests.**
5. Manual, pendiente: comparar dos respuestas de API de verdad, que es el criterio de cierre de
   la fase.
