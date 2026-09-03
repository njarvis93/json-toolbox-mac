# Spec: fileURL, isDirty y documentos recientes (solo slot .editor)

## Comportamiento esperado
- `AppModel` sabe, para el documento del editor, si viene de un archivo en disco (`fileURL`) y si
  el texto actual difiere del último contenido guardado/cargado (`isDirty`).
- Cargar un archivo (`load(_:into: .editor)`) fija `fileURL` y el snapshot "guardado"; pegar
  (`paste(into: .editor)`) limpia `fileURL` (el contenido no tiene archivo de origen) pero no se
  considera "guardado".
- Cada archivo abierto o guardado con éxito en `.editor` se añade al principio de una lista de
  recientes persistida entre lanzamientos, sin duplicados, tope 8 entradas.

## Casos límite
- Abrir el mismo archivo dos veces no duplica la entrada en recientes (se mueve al principio).
- `isDirty` es `false` justo tras cargar o guardar, y `true` en cuanto el texto cambia respecto a
  ese snapshot.
- Los slots `.a`/`.b` (modo comparar) no se ven afectados — sin `fileURL` ni recientes ahí.

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual (se verifica junto con la pieza 3, que es la que expone esto en la UI).
