import SwiftUI
import JSONCore

// Cada grupo de menú es una **vista** con sus propios `@ObservedObject`, y no botones sueltos
// dentro de `.commands`. Es obligado desde que el modelo son cinco objetos: `.commands` solo
// observa el `@StateObject` de `JsonToolingApp`, y SwiftUI no propaga los cambios de un
// `ObservableObject` anidado — los elementos se quedarían habilitados o deshabilitados con el
// estado que tuvieran al arrancar, y eso no da la cara al compilar.

/// Submenú "Abrir reciente".
struct RecentDocumentsMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        Menu("Abrir reciente") {
            ForEach(preferences.recentDocuments, id: \.self) { url in
                Button(url.lastPathComponent) { model.document.load(url) }
            }
            if !preferences.recentDocuments.isEmpty {
                Divider()
                Button("Vaciar menú") { preferences.clearRecentDocuments() }
            }
        }
    }
}

/// Guardar y exportar, en el menú Archivo.
struct FileCommands: View {
    @ObservedObject var model: AppModel
    @ObservedObject var comparison: ComparisonModel

    init(model: AppModel) {
        self.model = model
        self.comparison = model.comparison
    }

    var body: some View {
        Button("Guardar") { model.document.save() }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(model.mode != .editor)
        Button("Guardar como…") { model.document.saveAs() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model.mode != .editor)
        Divider()
        // Dentro de este grupo y no en un `CommandGroup(after: .saveItem)` aparte: ese
        // se anclaba a un grupo que se reemplaza, y el menú desaparecía sin decir nada.
        // El botón del toolbar sí funcionaba, así que no se notaba.
        Menu("Exportar diferencias") {
            ForEach(JSONDiffExport.Format.allCases) { format in
                Button(format.label) { comparison.copyDiff(as: format) }
            }
        }
        .disabled(model.mode != .compare || comparison.error != nil)
    }
}

/// El menú Convertir.
struct ConvertCommands: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button("Escapar como string") { model.document.escapeAsString() }
            .keyboardShortcut("e", modifiers: [.command, .control])
            .disabled(model.mode != .editor)
        Button("Desescapar string") { model.document.unescapeFromString() }
            .keyboardShortcut("u", modifiers: [.command, .control])
            .disabled(model.mode != .editor)
        Divider()
        // El XML no se queda en el editor: ver `DocumentModel.copyAsXML`.
        Button("Copiar como XML") { model.document.copyAsXML() }
            .disabled(model.mode != .editor)
        Button("Pegar desde XML") { model.document.pasteFromXML() }
            .disabled(model.mode != .editor)
    }
}

/// Mostrar u ocultar el panel de estructura.
struct SidebarCommand: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        Button(preferences.showTree ? "Ocultar estructura" : "Mostrar estructura") {
            preferences.showTree.toggle()
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(model.mode != .editor)
    }
}

/// Buscar, saltar de coincidencia o de diferencia, e ir a línea.
struct FindCommands: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var comparison: ComparisonModel

    init(model: AppModel) {
        self.model = model
        self.navigation = model.navigation
        self.comparison = model.comparison
    }

    var body: some View {
        Button("Buscar en la estructura…") { model.focusSearch() }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(model.mode != .editor)
        // Un solo par de atajos que hace lo que toca según la pantalla: dos ⌘G
        // distintos chocarían entre sí.
        Button(model.mode == .editor ? "Coincidencia siguiente" : "Diferencia siguiente") {
            model.stepNext()
        }
        .keyboardShortcut("g", modifiers: [.command])
        .disabled(!model.canStep)
        Button(model.mode == .editor ? "Coincidencia anterior" : "Diferencia anterior") {
            model.stepPrevious()
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(!model.canStep)
        Divider()
        Button("Ir a línea…") { model.document.promptGoToLine() }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(model.mode != .editor)
    }
}

/// El elemento del menú Ayuda. Es una vista porque `openWindow` solo llega por el entorno, y
/// dentro de `.commands` no hay otra forma de alcanzarlo.
struct ShortcutsMenuItem: View {
    static let windowID = "atajos"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Atajos de teclado") { openWindow(id: Self.windowID) }
            .keyboardShortcut("/", modifiers: [.command])
    }
}
