import SwiftUI
import JSONCore
import AppKit

@main
struct JsonToolingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("JsonTooling") {
            ContentView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .help) { ShortcutsMenuItem() }
        }
        // Cada grupo es una **vista** con sus propios `@ObservedObject`, y no botones sueltos.
        // Es obligado desde que el modelo son cuatro objetos: `.commands` solo observa el
        // `@StateObject` de aquí arriba, y SwiftUI no propaga los cambios de un
        // `ObservableObject` anidado — los elementos se quedarían habilitados o deshabilitados
        // con el estado que tuvieran al arrancar. Ya se usaba así para `ShortcutsMenuItem`.
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) { RecentDocumentsMenu(model: model) }
            CommandGroup(replacing: .saveItem) { FileCommands(model: model) }
            CommandMenu("Convertir") { ConvertCommands(model: model) }
            CommandGroup(after: .sidebar) { SidebarCommand(model: model) }
            CommandGroup(after: .textEditing) { FindCommands(model: model) }
        }

        Window("Atajos de teclado", id: ShortcutsMenuItem.windowID) {
            ShortcutsWindow()
        }
        .windowResizability(.contentSize)
    }
}
