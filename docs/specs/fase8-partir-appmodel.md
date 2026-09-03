# Fase 8 — `AppModel` partido (2026-09-02)

`AppModel` eran 860 líneas con el documento, la comparación y la navegación dentro. Ahora son
cinco objetos y **163 líneas** de coordinación.

| Objeto | Líneas | Qué guarda |
|---|---|---|
| `Preferences` | 101 | Todo lo que sobrevive al relanzamiento: sangría, panel, claves ignoradas, recientes |
| `DocumentModel` | 325 | Texto, archivo, parseo, cursor, guardar, conversiones |
| `ComparisonModel` | 270 | A/B, diferencias, selección, exportar |
| `NavigationModel` | 233 | Despliegue del árbol, búsqueda, nodo señalado |
| `AppModel` | 163 | Pantalla, barra de estado y las costuras |

## `Preferences` no estaba en el plan

El plan decía tres objetos. Salen cuatro porque **la sangría la comparten documento y
comparación**: el editor formatea con ella y las dos columnas de Comparar se formatean con ella
antes de alinearse. Dejarla en uno de los dos obligaba al otro a llevar una copia sincronizada a
mano, que es exactamente lo que quitó el primer paso de la Fase 8. Compartir una referencia no
tiene ese problema.

La regla para saber qué va ahí es sencilla: **si se lee de `UserDefaults` al arrancar, vive en
`Preferences`**. Eso se llevó también la persistencia que estaba repartida por `AppModel`.

## Ningún modelo conoce a los otros

Las tres cosas que cruzan están todas en `AppModel`, y ninguna dentro de los modelos:

1. **El cursor** mueve la posición de la barra de estado *y* el nodo señalado en el árbol →
   `AppModel.reportCaret`, que es lo que llama la vista.
2. **Enseñar un nodo** lo decide el árbol y lo hace el texto → `navigation.onReveal`.
3. **La sangría y las claves ignoradas** cambian → reformatear el documento y rehacer la
   comparación → `preferences.onIndentChange` / `onIgnoredKeysChange`.

Son cierres y no referencias entre modelos a propósito: el documento no tiene por qué saber que
existe una vista de estructura.

## Dos cosas que costaron

**`@Published` publica en `willSet`.** El primer intento avisaba de los cambios de sangría con un
`sink` sobre `preferences.$indent`. Un suscriptor de Combine ahí lee la sangría **vieja**, justo
cuando va a reformatear con ella. Se cambió a un aviso desde el `didSet`, que corre con el valor
ya puesto. Lo cazaron dos tests que ya existían, no una lectura del código.

**SwiftUI no propaga los `ObservableObject` anidados.** Observar `AppModel` no entera a una vista
de que ha cambiado `document.text`. Estaba anticipado en el plan y es lo que da forma a las
vistas: cada una declara un `@ObservedObject` por objeto que lee y los saca del modelo en su
`init`, así que los sitios donde se construyen (`ContentView(model:)`, `TreePanel(model:)`) no
cambiaron. En los menús no valía eso —`.commands` solo observa el `@StateObject` de la `App`—, así
que cada grupo pasó a ser una vista pequeña con sus propios objetos observados
(`RecentDocumentsMenu`, `FileCommands`, `ConvertCommands`, `SidebarCommand`, `FindCommands`).
Ya se usaba ese patrón para `ShortcutsMenuItem`. Sin esto los elementos de menú se habrían quedado
habilitados o deshabilitados con el estado que tuvieran al arrancar — un fallo que no da la cara
al compilar.

## Verificación

33 tests en verde (los 30 anteriores, reescritos contra la forma nueva, más tres de las costuras),
168 de `JSONCore` intactos, cero avisos de compilación, y la app abierta y capturada: editor,
panel de estructura, resaltado y barra de estado correctos. La pantalla de Comparar no se pudo
accionar desde la sesión (no hay permiso para enviar eventos a System Events); la cubren los tests.
