# Spec: hueco en blanco en la pantalla Comparar

## Bug reportado
En modo Comparar (tanto "Entradas" como "Diferencias"), aparecía un hueco en blanco de
~80pt tanto antes como después de la fila de cabeceras "A ... / B ...", como si esa fila
estuviera centrada dentro de una franja invisible mucho más alta de lo que debería.

## Causa raíz
`CompareScreen.swift` envolvía las dos `PaneHeader` (cada una con su propio `.frame(height: 26)`)
en un `HStack` con un `Divider()` entre medias:

```swift
HStack(spacing: 0) {
    PaneHeader(...)   // vista custom, .frame(height: 26) por dentro
    Divider()
    PaneHeader(...)
}
```

Cuando los dos hermanos de un `Divider()` dentro de un `HStack` son **vistas custom** (structs
`View` propios, no modificadores inline) que fijan su propia altura, SwiftUI no logra resolver
correctamente la altura del `HStack` a partir de esas alturas fijas: el `Divider()` termina
pidiendo una altura "greedy" (se midió con `GeometryReader` en 200.5pt en vez de 26pt), y como la
altura del `HStack` es el máximo de sus hijos, toda la fila se infla a 200.5pt — con la cabecera
real (26pt) dibujada en algún punto intermedio de esa franja, dejando espacio en blanco arriba y
abajo.

**Reemplazar `Divider()` por otra forma sin fijar altura explícita NO alcanza**: un
`Rectangle().frame(width: 1)` (sin `height:`) es igual de "greedy" y produce la misma altura
inflada. Hay que darle una altura fija explícita, igual a la de las vistas custom vecinas.

El mismo patrón exacto existía en `AlignedDiffView` (`DiffCell` con `.frame(height: 18)` +
`Divider()` entre dos `DiffCell`), probablemente la causa de las filas en blanco extra que se
veían entre pares de líneas modificadas en la vista de diferencias.

## Diagnóstico
Se aisló usando capturas de ventana por id (`screencapture -l<id> -o`, sin sombra, exactamente 2x
los puntos de la ventana — permite mapear píxel↔punto con precisión) y, de forma decisiva, un
`GeometryReader` temporal en `.background()` del `HStack` sospechoso, con
`FileHandle.standardError.write` en `.onAppear` para loguear el frame real. Sin esto, quitar/cambiar
piezas a ciegas (contenido de `PaneHeader`, `ChangeList`, la tabla, el `Divider` de fuera del
`HStack`...) no reproducía ni explicaba el hueco — el `GeometryReader` fue lo que dio el número
exacto (200.5 → 26.0) que confirmó la causa real en segundos.

## Fix
`Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: <alto de los hermanos>)`
en vez de `Divider()`, tanto en la fila de cabeceras A/B como en cada fila de `AlignedDiffView`.

## Criterio de aceptación
1. `swift build` sin errores; 44/44 tests en verde (no afecta a JSONCore).
2. Verificado visualmente (capturas de ventana reales): la cabecera "A/B" queda pegada al toolbar
   en modo Comparar, sin hueco antes ni después, tanto en "Entradas" como en "Diferencias".

## Lección para el futuro
**Cuidado con `Divider()` (o cualquier vista sin tamaño fijo) entre dos vistas `View` custom
propias que fijan su altura con `.frame(height:)`.** Si aparece un hueco en blanco alrededor de
una fila que debería ser compacta, medir con un `GeometryReader` temporal antes de adivinar por
píxeles — es mucho más rápido y decisivo.
