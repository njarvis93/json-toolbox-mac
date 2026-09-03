# Spec: buscar por clave y por valor

Segundo trozo de la Fase 4, encima del árbol posicionado (`fase4-arbol.md`).

## Por qué sobre el árbol y no sobre el texto

`JSONSearch` recorre `JSONNode`, no el texto. Es lo que permite distinguir **la clave `precio`**
de **la palabra "precio" escrita dentro de una cadena** — y esa distinción es justo lo que un
buscador de texto no sabe hacer. También hace que encontrar una clave no dependa de cómo esté
escrito el documento: minificado, con la sangría que sea o con la clave en otra línea, da igual.

## Comportamiento esperado
- Campo de búsqueda en el panel de estructura. ⌘F lo enfoca (y abre el panel si estaba cerrado).
- Ámbito **Todo / Claves / Valores**. Los números, `true`, `false` y `null` se buscan por su
  literal: buscar `42.90` o `null` en Valores funciona.
- Sin distinguir mayúsculas ni tildes: `articulo` encuentra `Artículo`.
- Recuento en el panel: "N coincidencias", y "N de M" en cuanto se salta a una.
- ⌘G / ⇧⌘G y las flechas del panel saltan a la coincidencia siguiente/anterior, dando la vuelta
  al llegar al final. El primer salto va a la **primera** coincidencia, no a la segunda.
- Saltar a una coincidencia la selecciona en el editor, igual que revelar desde el árbol.

## El árbol mientras se busca
- Se filtra a las coincidencias **y sus ancestros**, y se despliega solo. Tener que abrir a mano
  la rama que lleva a lo que acabas de buscar no tiene ningún sentido.
- Las coincidencias van en negrita con fondo amarillo; los ancestros se enseñan en gris normal,
  solo para no perder el contexto.
- La fila seleccionada manda sobre el amarillo de coincidencia: si no, saltar de una a otra no se
  vería, porque todas estarían pintadas igual.
- Sin resultados, el cuerpo del panel dice "Nada que coincida con …". Un panel del todo vacío
  parece roto, y el recuento de la barra no basta.

## Casos límite
- Consulta vacía o solo espacios: no es una búsqueda, el árbol vuelve al modo normal.
- La búsqueda se recalcula en cada parseo válido, así que editar el documento actualiza el
  recuento sin tener que volver a escribir la consulta.
- Documento inválido: la búsqueda sigue mostrando lo del último árbol bueno, como el panel.
- ⌘G con cero coincidencias no hace nada (el menú y los botones salen deshabilitados).

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 105/105 el 2026-09-02, 10 de ellos de
   búsqueda.
2. Buscar `precio` en el documento de ejemplo y saltar dos veces: 2 coincidencias, "2 de 2", el
   árbol filtrado y desplegado hasta las dos, y el editor con `7.50` seleccionado.
   **Verificado** con captura de la ventana real, CPU al 0 %.
3. Búsqueda sin resultados: "Sin coincidencias", flechas deshabilitadas, mensaje en el cuerpo y
   ningún hueco raro en el panel. **Verificado** con captura.
4. Manual, pendiente (sin permiso de Accessibility aquí para automatizar teclado):
   ⌘F, ⌘G, ⇧⌘G, y cambiar el ámbito con el selector.
