# Spec: undo deshacible en reemplazos externos de texto

## Comportamiento esperado
Cuando `AppModel.text` cambia desde fuera del `NSTextView` (Formatear, Minificar, Ordenar claves,
Importar, Pegar, cargar por drag&drop), el cambio debe quedar registrado en la pila de undo del
`NSTextView` como un único paso, deshacible con ⌘Z.

## Caso límite
- Escribir a mano normalmente no debe cambiar de comportamiento: sigue siendo undo carácter/palabra
  a palabra, como ahora.
- La posición del cursor tras el reemplazo se mantiene acotada a la nueva longitud del texto (igual
  que hoy).

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual: escribir JSON válido, pulsar "Formatear", pulsar ⌘Z → el texto vuelve exactamente al
   estado previo al formateo (no a un estado intermedio ni sin efecto).
3. Manual: repetir con "Minificar" y "Ordenar claves".

## Bug relacionado encontrado y corregido (2026-09-01)
Reportado por el usuario: el editor no mostraba nada de texto, solo los números de línea del
ruler. Causa: `tv.string = text` no dispara el redimensionado automático que activa
`isHorizontallyResizable`/`isVerticallyResizable` (eso solo ocurre vía `didChangeText()`), así
que el `NSTextView` se quedaba con frame `.zero` y no dibujaba nada, aunque el
`NSLayoutManager` tuviera el layout correcto (por eso el ruler, que lee directo del layout
manager, sí mostraba los números). Fix: `tv.sizeToFit()` después de fijar el contenido inicial en
`makeNSView` y tras cada reemplazo externo en `updateNSView`. Compila; **no verificado
visualmente** por falta de permisos de Screen Recording/Accessibility en este entorno — pendiente
de que el usuario confirme que ahora sí se ve el texto.

## Seguimiento (2026-09-01): seguía en blanco tras el fix de sizeToFit
El usuario confirmó (con capturas) que el editor seguía sin mostrar texto, y además reportó dos
cosas más: la vista de comparar en modo "Diferencias" tenía huecos en blanco feos alrededor de la
cabecera A/B, y el botón "Importar" parecía no responder.

Revisando `UserDefaults` de la app en la misma máquina (`defaults read JsonTooling`) aparecieron
claves de tamaño de ventana bajo **dos nombres de módulo distintos**:
`JsonToolingApp.ContentView-1-AppWindow-1` (940×672, el build por `swift build`/CLI) y
`JsonTooling.ContentView...`/`SwiftUI.ModifiedContent<JsonTooling.ContentView,...>` (1261×970,
consistente con un build hecho desde Xcode con el scheme del producto). Esto confirma que el
build de Xcode del usuario y el build de CLI con el que yo verifico son binarios distintos — así
que no puedo asumir que un fix compilado por mí ya esté en lo que el usuario está probando.
**Recomendación al usuario: Product → Clean Build Folder y volver a correr en Xcode** antes de
reportar si un fix funciona o no.

Además, SwiftUI ya persiste y restaura el frame de `WindowGroup` por su cuenta (de ahí esas claves
`SwiftUI.ModifiedContent<...>`). El código añadido en Fase 2 para "recordar tamaño de ventana"
(`NSApp.windows.first?.setFrameAutosaveName("main")` en `AppDelegate`) era redundante con eso, no
generaba ninguna clave `NSWindow Frame main` (`NSApp.windows.first` probablemente devolvía la
ventana antes de tiempo o SwiftUI competía por el mismo frame) y aplicaba un resize por fuera del
ciclo de actualización de SwiftUI — explicación plausible de los huecos en blanco vistos en el
comparador (contenido dispuesto para un tamaño, ventana redimensionada después sin que SwiftUI
volviera a hacer layout). **Se quitó esa línea** — SwiftUI ya lo cubre nativamente.

Segundo fix aplicado: `sizeToFit()` a solas no bastaba (o el build de Xcode no lo tenía). Se
sustituyó por `JSONTextView.fitToContent(_:)`, que fuerza el layout con
`layoutManager.ensureLayout(for:)` y calcula el frame explícitamente desde `usedRect(for:)` en vez
de confiar en el redimensionado implícito de AppKit. Se llama en `makeNSView` (ya con
`scroll.documentView = tv` asignado antes, no después) y en cada reemplazo de texto.

Tercer fix, para "el botón Importar no responde": si Xcode se queda como app activa tras lanzar
el proceso hijo, un `NSOpenPanel`/`NSSavePanel`/`NSAlert` modal puede abrirse detrás de Xcode sin
que se note. Se añadió `NSApp.activate(ignoringOtherApps: true)` justo antes de cada
`panel.runModal()`/`alert.runModal()` (`openFile`, `saveAs`, `promptGoToLine`, el aviso de cierre
con cambios sin guardar).

Los tres fixes compilan y pasan `swift test` (44/44), pero **siguen sin verificarse a mano** por
la misma limitación de permisos. Pendiente de que el usuario haga *Clean Build Folder* + Run en
Xcode y confirme.
