import SwiftUI
import AppKit

/// Fondo con material de macOS (`NSVisualEffectView`), que en SwiftUI no se puede pedir con
/// un `Color`.
///
/// Hace falta para el panel lateral: `controlBackgroundColor` deja el panel y el editor
/// prácticamente del mismo color — medido, #222324 contra #1E1F1E en oscuro y **#FFFFFF los
/// dos en claro** — así que el árbol se leía como una columna flotando sobre la misma
/// superficie del editor en vez de como una barra lateral.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        // Sin esto el material se apaga cuando la ventana pierde el foco, que es justo lo que
        // hace macOS con las barras laterales de verdad.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
