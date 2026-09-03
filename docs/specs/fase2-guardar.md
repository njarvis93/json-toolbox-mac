# Spec: ⌘S sobre archivo abierto + aviso al cerrar

## Comportamiento esperado
- ⌘S en modo editor: si el documento tiene `fileURL`, escribe ahí directamente sin diálogo. Si no
  lo tiene (documento nuevo, pegado, o cargado desde el portapapeles), se comporta como "Guardar
  como…" (abre `NSSavePanel`).
- ⇧⌘S siempre abre "Guardar como…", tenga o no `fileURL`, y tras guardar el nuevo destino pasa a
  ser el `fileURL` activo.
- Ambos deshabilitados fuera de modo editor (modo comparar no tiene concepto de guardado en esta
  fase).
- Al cerrar la última ventana o salir de la app (⌘Q) con `isDirty == true`, aparece un aviso con
  Guardar / No guardar / Cancelar antes de terminar.

## Casos límite
- Guardar con error de escritura (permiso denegado, disco lleno) muestra el aviso existente vía
  `flash(...)` y no marca el documento como limpio.
- Elegir "Guardar" en el aviso de cierre y que el guardado falle (p.ej. cancelar el panel de
  Guardar como) no debe cerrar la app igualmente — se cancela el cierre.

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual: abrir un `.json`, editar, ⌘S → se guarda sin diálogo, el título/documentName no cambia
   inesperadamente.
3. Manual: documento nuevo (sin archivo), ⌘S → abre "Guardar como…".
4. Manual: editar y cerrar la ventana → aparece el aviso; "No guardar" cierra igualmente.

**Verificado a mano por el usuario el 2026-09-02.**
