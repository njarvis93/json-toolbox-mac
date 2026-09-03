import SwiftUI
import JSONCore

/// La barra de abajo. Es lo único que mira al documento y a la comparación a la vez, por eso
/// lee del `AppModel` lo derivado y de los otros dos lo concreto.
struct StatusBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var document: DocumentModel
    @ObservedObject var comparison: ComparisonModel

    init(model: AppModel) {
        self.model = model
        self.document = model.document
        self.comparison = model.comparison
    }

    private var dotColor: Color {
        switch model.statusLevel {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(model.statusText)
                .foregroundStyle(model.statusLevel == .error ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .onTapGesture {
                    guard model.mode == .editor, let line = document.error?.line else { return }
                    document.goTo(line: line)
                }
                .contentShape(Rectangle())
                .help(model.mode == .editor && document.error != nil ? "Clic para ir a la línea" : "")

            Spacer(minLength: 12)

            if model.mode == .editor {
                Text("Ln \(document.caretLine), Col \(document.caretColumn)")
            } else {
                Text("A vs B")
            }
            Text(AppModel.humanSize(model.byteCount))
            if model.mode == .editor && document.isValid {
                Text("\(document.nodeCount) nodos")
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }
}
