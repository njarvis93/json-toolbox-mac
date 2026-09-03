# Bug: "Ir a línea" colgaba la app en un bucle de render

Reportado por el usuario el 2026-09-02. La función quedó implementada en la Fase 2 pero nunca se
había probado a mano (el propio plan lo decía). No funcionaba.

## Síntoma

Pedir cualquier línea deja la app **al 100 % de CPU indefinidamente**, la ventana congelada
arriba del documento y el cursor en un sitio que no es el pedido. Reproducido con un documento de
603 líneas, saltando a la 300: `updateNSView` se ejecutó **6.376 veces en 5 segundos** y seguía.

## Causa

`AppModel.scrollTarget` era un `Int?` que la vista consumía y limpiaba:

```swift
if let target = scrollTarget.wrappedValue {
    tv.scrollRangeToVisible(range)
    tv.setSelectedRange(range)
    DispatchQueue.main.async { binding.wrappedValue = nil }   // ← limpieza diferida
}
```

Dos cosas se juntan y se realimentan:

1. `setSelectedRange` llama a `textViewDidChangeSelection` **de forma síncrona**, y ese delegado
   acaba en `reportCaret`, que escribe `caretLine`/`caretColumn` en el modelo. Es decir: publicar
   cambios *dentro* de una actualización de vista, que es justo lo que SwiftUI prohíbe. SwiftUI
   vuelve a renderizar en el acto.
2. En ese nuevo render, `scrollTarget` **sigue valiendo 300**: la limpieza estaba diferida a un
   `DispatchQueue.main.async` que no llega a ejecutarse nunca, porque el hilo principal no vuelve
   al run loop. Se reaplica el salto → nueva selección → nuevo render → …

El rango calculado era correcto (`lineRange(300)` = `{5689, 21}`, comprobado; ese offset es de
verdad la línea 300). El fallo no estaba en el cálculo sino en el ciclo de vida de la petición.

## Arreglo

Dos cambios, cada uno mata una de las dos patas:

1. **La petición tiene identidad.** `ScrollRequest { line, id }` con un contador que sube en cada
   `AppModel.goTo(line:)`. El coordinador se queda con el `id` del último salto atendido y no
   repite. La vista **ya no escribe en el modelo**: no hay limpieza que diferir, y `scrollTarget`
   deja de ser un `Int?` ambiguo entre "hay salto pendiente" y "este ya lo hice".
2. **La selección programática no informa del cursor en el mismo turno.**
   `setSelectionWithoutReporting` pone una bandera mientras llama a `setSelectedRange`, para que
   `textViewDidChangeSelection` no dispare, y difiere un único `reportCaret` al siguiente turno
   del run loop, ya fuera de la actualización de vista.

El segundo también cubre la sustitución de texto de `updateNSView` (Formatear, Minificar, Ordenar
claves, Convertir): allí se hacía la misma llamada a `setSelectedRange` desde dentro del update.
Ese camino no llegaba a colgarse porque converge — a la segunda pasada `tv.string == text` — pero
era la misma clase de error.

## Verificación

Con permiso de Screen Recording, capturando la ventana real por su window id, y un gancho de
depuración temporal (quitado después) para disparar los saltos sin teclado, ya que no hay permiso
de Accessibility en este entorno:

- Salto a la línea 300 de 603: la línea queda visible y seleccionada, barra de estado
  "Ln 300, Col 1", **CPU al 0 %**.
- Secuencia de cuatro saltos seguidos (300 → 5 → 9999 → 120): acaba en la 120, seleccionada, sin
  quedarse pegado en ninguno. El 9999, fuera de rango, no rompe nada (va a la última línea, que
  es lo que decía la spec original).

**El usuario lo probó a mano y funciona** (2026-09-02): ⌘L, diálogo, número, Intro. Queda sin
confirmar el clic en el mensaje de error de la barra de estado, que entra por el mismo
`goTo(line:)`.

## Regla que se lleva a CLAUDE.md

No tocar el `NSTextView` desde `updateNSView` de forma que dispare delegados que escriben en el
modelo. Y una petición que la vista deba atender una sola vez necesita identidad propia: limpiarla
con un `async` desde la vista parece funcionar y se rompe en cuanto algo más re-renderiza.
