# Spec: recordar sangría y tamaño de ventana entre lanzamientos

## Comportamiento esperado
- La sangría elegida (`IndentStyle`) persiste en `UserDefaults` y se restaura al iniciar la app.
- El tamaño y posición de la ventana principal persisten (autosave nativo de AppKit) y se
  restauran al reabrir.

## Casos límite
- Primer lanzamiento (sin valor guardado): sangría por defecto `2 espacios`, ventana con el frame
  por defecto de SwiftUI (`minWidth`/`minHeight` de `ContentView`).
- Valor guardado corrupto/desconocido para la sangría: cae al valor por defecto sin crashear.

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual: cambiar sangría a "4 espacios", cerrar y reabrir la app → sigue en "4 espacios".
3. Manual: redimensionar/mover la ventana, cerrar y reabrir → mismo tamaño y posición.

**Verificado a mano por el usuario el 2026-09-02.**
