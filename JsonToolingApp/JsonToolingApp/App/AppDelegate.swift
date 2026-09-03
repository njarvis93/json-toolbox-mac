import SwiftUI
import AppKit

/// Un ejecutable de SwiftPM no trae bundle de app: sin esto la ventana
/// aparece detrás de todo y sin icono en el Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Los archivos que llegan del Finder pueden hacerlo **antes** de que la ventana exista y
    /// enganche su modelo, así que se guardan y se abren en cuanto lo hay.
    weak var model: AppModel? { didSet { openPending() } }
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        openPending()
    }

    private func openPending() {
        guard let model, let url = pendingURLs.last else { return }
        pendingURLs.removeAll()
        Task { @MainActor in
            model.document.load(url)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.document.isDirty else { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿Guardar los cambios antes de salir?"
        alert.informativeText = "Los cambios en “\(model.document.name)” se perderán si no los guardas."
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "No guardar")
        alert.addButton(withTitle: "Cancelar")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.document.save()
            return model.document.isDirty ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
