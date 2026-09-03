import SwiftUI
import UniformTypeIdentifiers
import JSONCore

struct EditorScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var document: DocumentModel

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
        self.document = model.document
    }

    var body: some View {
        HStack(spacing: 0) {
            if preferences.showTree {
                TreePanel(model: model)
                    .frame(width: 260)
                // Separador con ancho fijo en vez de `Divider()`, por la misma razón que en
                // Comparar: ver docs/specs/fase2-comparar-hueco.md.
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            editor
        }
    }

    private var editor: some View {
        JSONTextView(
            text: $document.text,
            errorLine: document.error?.line,
            // El cursor mueve dos cosas a la vez (barra de estado y árbol), así que lo reparte
            // `AppModel`: es una de las tres costuras que quedaron ahí al partir la clase.
            onCaretChange: { caret in
                model.reportCaret(
                    line: caret.line, column: caret.column,
                    utf16Offset: caret.utf16Offset)
            },
            scrollRequest: document.scrollRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropReceiver.handle(providers) { document.load($0) }
        }
    }
}

enum DropReceiver {
    /// Quién recibe el archivo lo decide quien llama: el editor y cada lado de Comparar cargan
    /// en modelos distintos.
    @MainActor
    static func handle(
        _ providers: [NSItemProvider],
        into load: @escaping @MainActor (URL) -> Void
    ) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in load(url) }
        }
        return true
    }
}
