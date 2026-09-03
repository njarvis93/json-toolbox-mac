import SwiftUI

/// Lista editable de claves que se ignoran al comparar.
///
/// El botón se pinta relleno cuando hay alguna: filtrar diferencias en silencio, sin que se vea
/// en ninguna parte, es la clase de cosa que hace que te fíes de una comparación que te está
/// escondiendo algo.
struct IgnoredKeysButton: View {
    @ObservedObject var preferences: Preferences
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("Ignorar claves", systemImage: preferences.ignoredKeys.isEmpty ? "eye" : "eye.slash.fill")
        }
        .labelStyle(.iconOnly)
        .help(
            preferences.ignoredKeys.isEmpty
                ? "Ignorar claves al comparar"
                : "Ignorando \(preferences.ignoredKeys.count) clave\(preferences.ignoredKeys.count == 1 ? "" : "s")"
        )
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ignorar estas claves")
                    .font(.system(size: 12, weight: .semibold))
                Text(
                    "Separadas por comas. Se ignoran por nombre, estén donde estén: sirve para los campos que cambian en cada respuesta."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $preferences.ignoredKeysText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                HStack {
                    Text(
                        preferences.ignoredKeys.isEmpty
                            ? "Ninguna"
                            : "\(preferences.ignoredKeys.count) clave\(preferences.ignoredKeys.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Vaciar") { preferences.ignoredKeysText = "" }
                        .controlSize(.small)
                        .disabled(preferences.ignoredKeys.isEmpty)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }
}
