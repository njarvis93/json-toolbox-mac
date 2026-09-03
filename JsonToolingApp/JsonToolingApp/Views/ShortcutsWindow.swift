import SwiftUI

/// Los atajos de la app, en una ventana propia desde el menú Ayuda.
///
/// La lista se escribe a mano y no se deduce de los `.keyboardShortcut(...)`: SwiftUI no deja
/// enumerarlos. Si se añade un atajo, hay que añadirlo aquí — está en `CLAUDE.md`.
struct ShortcutsWindow: View {
    struct Item: Identifiable {
        let keys: String
        let what: String
        var id: String { keys + what }
    }

    struct Group: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(
            title: "Archivo",
            items: [
                Item(keys: "⌘S", what: "Guardar"),
                Item(keys: "⇧⌘S", what: "Guardar como…"),
            ]),
        Group(
            title: "Editor",
            items: [
                Item(keys: "⇧⌘F", what: "Formatear"),
                Item(keys: "⌘L", what: "Ir a línea…"),
                Item(keys: "⌘Z", what: "Deshacer, también tras formatear"),
            ]),
        Group(
            title: "Estructura",
            items: [
                Item(keys: "⌃⌘S", what: "Mostrar u ocultar el panel"),
                Item(keys: "⌘F", what: "Buscar clave, valor o ruta"),
                Item(keys: "⌘G", what: "Coincidencia siguiente"),
                Item(keys: "⇧⌘G", what: "Coincidencia anterior"),
            ]),
        Group(
            title: "Convertir",
            items: [
                Item(keys: "⌃⌘E", what: "Escapar como string"),
                Item(keys: "⌃⌘U", what: "Desescapar string"),
            ]),
        Group(
            title: "Comparar",
            items: [
                Item(keys: "⌘G", what: "Diferencia siguiente"),
                Item(keys: "⇧⌘G", what: "Diferencia anterior"),
            ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.keys)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 54, alignment: .trailing)
                                Text(item.what)
                                    .font(.system(size: 12))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                Text(
                    "⌘G y ⇧⌘G hacen lo que toca según la pantalla: coincidencias en el editor, diferencias en Comparar."
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 340, height: 460)
    }
}
