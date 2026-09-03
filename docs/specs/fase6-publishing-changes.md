# "Publishing changes from within view updates": eran los Pickers del toolbar

El aviso que el usuario veía al cambiar entre Editor y Comparar, y entre Entradas y Diferencias.
Costó tres intentos fallidos antes de medirlo bien.

## Por qué no se reproducía

Dos condiciones **a la vez**, y me faltaban las dos:

1. **Va al log unificado, no a `stderr`.** Yo capturaba `2>&1` y ahí no aparece nunca.
2. **Solo se emite con un depurador enganchado.** Ejecutando el binario suelto no existe; hay que
   lanzarlo bajo `lldb` (o desde Xcode, que es donde lo veía el usuario).

Y además hay que accionar el control **de verdad**: cambiar `model.mode` por código no lo produce,
porque el problema es quién escribe y cuándo, no el valor.

La receta que sí reproduce:

```
JT_SEG=1 lldb -b -o run -- .../JsonTooling
```

con un gancho que busca el `NSSegmentedControl` del toolbar, le cambia el segmento y envía su
acción. Ocho cambios → **40 avisos**.

## Cómo se localizó

Bisecando, con la cuenta de avisos como medida:

| Qué se quitó | Avisos |
|---|---|
| Nada (base) | 44 |
| `CompareScreen` → `Text` | 36 |
| Las **dos** pantallas → `Text` | 28 |
| Todo el toolbar menos el selector de modo | 40 (con las pantallas de verdad) |
| Escritura del `Picker` diferida un turno | **0** |

Antes de eso, instrumentando cada mutación del modelo (`revalidate`, `recompare`,
`refreshSearch`, `revealSelectedChange`, `syncTree`, el aviso de cursor) se vio que **ninguna se
ejecuta durante el cambio de pantalla** y aun así salían los avisos. Eso descartó el modelo y
mandó a mirar la capa de vista.

## La causa y el arreglo

Un `Picker` del toolbar escribe su selección **mientras SwiftUI está actualizando la barra**, y
esa escritura cae sobre un `@Published`. El arreglo es un enlace que publica el cambio en el
siguiente turno del run loop (`ContentView.diferido`), aplicado a los tres selectores del toolbar:
modo, vista de comparación y sangría.

Los selectores siguen funcionando —ocho cambios seguidos dejan el modo correcto y la sangría
aplicada—, con un turno de retraso que no se percibe.

## Lo que se probó y no era

- Que el editor escribiera en el modelo desde `updateNSView` (`didChangeText` → `parent.text` y el
  aviso de cursor). **Es real y se arregló igualmente** —el editor no debe escribir en el modelo
  desde dentro de una actualización— pero no era esto: medido, quitar el aplazamiento del cursor
  deja los avisos en 0 igual.
- `makeNSView` poniendo el texto inicial. No dispara nada: cuando eso ocurre,
  `coordinator.textView` todavía es `nil` y el delegado sale por la guarda.

## Lección

Tres arreglos se dieron por buenos sin reproducción, y dos no eran. Lo que lo resolvió fue montar
la medida (lldb + acción real + contar avisos) **antes** de tocar nada más.
