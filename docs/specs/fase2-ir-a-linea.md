# Spec: Ir a línea (⌘L) + clic en error de la barra de estado

## Comportamiento esperado
- ⌘L en modo editor abre un diálogo pidiendo un número de línea; al confirmar, el editor hace
  scroll a esa línea y selecciona/posiciona el cursor ahí.
- En la barra de estado, si hay un error de validación (modo editor), el mensaje de error es
  clicable y hace lo mismo: salta a `editorError.line`.
- Fuera de modo editor, ambas acciones no hacen nada (⌘L deshabilitado; la barra de estado en modo
  comparar no tiene mensaje de error de línea).

## Casos límite
- Línea pedida mayor que el número de líneas del documento: salta a la última línea disponible en
  vez de fallar o no hacer nada.
- Texto no numérico en el diálogo de "Ir a línea": no hace nada (se ignora, sin crash).

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual: ⌘L, escribir una línea válida → el editor hace scroll y selecciona esa línea.
3. Manual: con un JSON inválido, clic en el mensaje de error de la barra de estado → salta a la
   línea del error.

**Verificado a mano por el usuario el 2026-09-02.**
