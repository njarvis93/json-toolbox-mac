# Spec: árbol posicionado y navegación estructural

Primer trozo de la Fase 4: el cambio en JSONCore que el plan marcaba como bloqueante, más el
panel lateral y la sincronización árbol ↔ texto. Quedan fuera de este trozo la búsqueda por
clave/valor y las consultas JSONPath.

## La decisión que el plan dejaba abierta

> "`JSONValue` con rango asociado, **o** un árbol paralelo de nodos posicionados."

**Árbol paralelo** (`JSONNode`), no rango dentro de `JSONValue`. El motivo es el diff: `JSONDiff`
compara `JSONValue` por valor, y dos documentos equivalentes escritos con distinto espaciado
tienen que seguir siendo iguales. Con el rango dentro del valor, o contamina la igualdad o hay
que acordarse de excluirlo en cada sitio que compare. Separados, la frontera es la que ya existía:
`JSONValue` dice **qué** pone el documento y `JSONNode` dice **dónde** lo pone.

El parser construye los dos a la vez, en el mismo recorrido (`Cursor.value` devuelve la pareja):
parsear dos veces para tener las posiciones sería tirar el trabajo hecho.

Los desplazamientos son **UTF-16**, como los de `Token`, porque es lo que consume `NSTextView`.
Con bytes UTF-8 la selección se descuadra en cuanto hay un emoji — hay un test que lo fija.

Las rutas usan **el mismo formato que `JSONChange.path`** (`lineas[0].cantidad`, raíz `$`). No es
cosmético: la Fase 5 quiere saltar de una fila de diferencias al nodo correspondiente, y con dos
formatos distintos habría que traducir. Hay un test que compara las rutas que produce el diff con
las que produce el árbol sobre el mismo documento.

## Qué nodo señala el cursor

La mitad delicada de la sincronización. Regla, en orden:

1. El nodo más profundo cuyo rango contiene el desplazamiento (contando la clave, para que poner
   el cursor sobre `"nombre"` señale su valor).
2. Si eso cae en un contenedor —típicamente la sangría al principio de una línea, que pertenece
   al contenedor y no a lo escrito en ella— y hay un hijo que empieza en esa **misma línea** más
   adelante, se baja **un solo nivel** hasta él.
3. **Un solo** nivel: en `"cliente": { "id": 1, … }`, todo en una línea, bajar sin freno acabaría
   señalando `cliente.id` en vez de `cliente`.
4. No se baja si el desplazamiento es justo el principio del contenedor. Ahí el cursor lo está
   señalando a propósito: es lo que hace "revelar" desde el árbol, y bajar sería deshacer lo que
   el usuario acaba de pedir.

## El panel

- Filas **aplanadas a mano** (`AppModel.treeRows`), no `OutlineGroup`. El despliegue tiene que
  poder abrirse desde fuera —al mover el cursor por el texto se despliega la rama que lleva hasta
  ese nodo— y el estado interno de `OutlineGroup` no se deja tocar.
- Mismos colores que el resaltado del editor, resueltos con `NSColor(name:dynamicProvider:)` para
  que sigan la apariencia clara/oscura.
- Separadores con ancho fijo en vez de `Divider()`, por lo de siempre (`fase2-comparar-hueco.md`).
- El árbol es del **último parseo válido**: al teclear algo que rompe el JSON no desaparece, se
  marca "desfasado" en la cabecera. Verlo parpadear con cada carácter a medio escribir sería peor.
- Se muestra/oculta con ⌃⌘S y con el botón del toolbar; la preferencia se recuerda.

Al revelar un nodo se selecciona **solo el valor**, no la clave: es lo que se quiere copiar o
reemplazar. Los rangos vienen del último parseo, así que al aplicarlos se recortan contra la
longitud actual del texto — si no, un texto editado desde entonces reventaría la selección.

## Casos límite
- Documento inválido: el panel mantiene la última foto buena, marcada como desfasada.
- El nodo seleccionado desaparece al reeditar: `selectedPath` se pone a nil en el siguiente
  parseo válido.
- Raíz escalar (`42`): un único nodo, etiqueta `$`, sin hijos.
- Contenedores vacíos: `{}` / `[]`, sin triángulo de desplegar.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 95/95 el 2026-09-02, 22 de ellos del árbol.
   Los 73 anteriores siguen pasando sin tocar nada, que es lo que se quería del cambio del parser.
2. El panel se ve y el editor **sigue componiéndose** (la trampa histórica de este proyecto).
   **Verificado** con captura de la ventana real.
3. Texto → árbol: cursor en la línea 9 del documento de ejemplo → el árbol despliega `lineas` y
   resalta `lineas[1]`. **Verificado** con captura, CPU al 0 %.
4. Árbol → texto: revelar `lineas[0].descripcion` → el editor selecciona exactamente
   `"Router dual-band"` y el árbol despliega la rama. **Verificado** con captura, CPU al 0 %.
5. Manual, pendiente (sin permiso de Accessibility aquí para automatizar ratón ni teclado):
   clic en una fila, clic en el triángulo de desplegar, plegar/desplegar todo, ⌃⌘S, y mover el
   cursor tecleando por un documento grande.
