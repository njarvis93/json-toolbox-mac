import Foundation

/// Vuelca una lista de diferencias a texto pegable.
///
/// Existe porque el final del camino de una comparación no es mirarla: es contársela a alguien
/// en un ticket o en un mensaje. Hasta ahora eso era una captura de pantalla o copiar celda a
/// celda de la tabla.
public enum JSONDiffExport {

    public enum Format: String, CaseIterable, Identifiable {
        case plain, markdown

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .plain: return "Texto plano"
            case .markdown: return "Markdown"
            }
        }
    }

    public static func render(
        _ changes: [JSONChange], format: Format,
        nameA: String, nameB: String,
        ignoredKeys: Set<String> = []
    ) -> String {
        switch format {
        case .plain: return plain(changes, nameA: nameA, nameB: nameB, ignoredKeys: ignoredKeys)
        case .markdown: return markdown(changes, nameA: nameA, nameB: nameB, ignoredKeys: ignoredKeys)
        }
    }

    /// Resumen que encabeza los dos formatos.
    static func summary(_ changes: [JSONChange], ignoredKeys: Set<String>) -> String {
        guard !changes.isEmpty else {
            return ignoredKeys.isEmpty
                ? "Sin diferencias estructurales."
                : "Sin diferencias estructurales (ignorando \(list(ignoredKeys)))."
        }
        func count(_ kind: JSONChange.Kind) -> Int { changes.filter { $0.kind == kind }.count }
        var parts: [String] = []
        for kind in [JSONChange.Kind.added, .removed, .modified, .moved] where count(kind) > 0 {
            parts.append(kind.counted(count(kind)))
        }
        var line =
            "\(changes.count) diferencia\(changes.count == 1 ? "" : "s") · "
            + parts.joined(separator: ", ")
        // Lo que se ha dejado fuera va en el volcado: quien lo lea en un ticket tiene que poder
        // saber que la comparación no lo miraba todo.
        if !ignoredKeys.isEmpty { line += " · ignorando \(list(ignoredKeys))" }
        return line
    }

    private static func list(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: ", ")
    }

    /// Valor de una celda. Los contenedores se minifican para que quepan en una línea.
    static func cell(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        return JSONFormatter.render(value, indent: nil)
    }

    // MARK: - Texto plano

    private static func plain(
        _ changes: [JSONChange], nameA: String, nameB: String,
        ignoredKeys: Set<String>
    ) -> String {
        var out = "\(nameA)  vs  \(nameB)\n"
        out += summary(changes, ignoredKeys: ignoredKeys) + "\n"
        guard !changes.isEmpty else { return out }
        out += "\n"

        let rows = changes.map {
            (
                label: $0.kind.label, path: $0.path,
                before: cell($0.before), after: cell($0.after)
            )
        }
        // Columnas alineadas a mano: en texto plano no hay tabla, y sin alinear no se lee.
        let labelWidth = rows.map(\.label.count).max() ?? 0
        let pathWidth = rows.map(\.path.count).max() ?? 0
        let beforeWidth = rows.map(\.before.count).max() ?? 0

        for row in rows {
            out += row.label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            out += "  " + row.path.padding(toLength: pathWidth, withPad: " ", startingAt: 0)
            out += "  " + row.before.padding(toLength: beforeWidth, withPad: " ", startingAt: 0)
            out += "  →  " + row.after + "\n"
        }
        return out
    }

    // MARK: - Markdown

    private static func markdown(
        _ changes: [JSONChange], nameA: String, nameB: String,
        ignoredKeys: Set<String>
    ) -> String {
        var out = "**\(escape(nameA))** vs **\(escape(nameB))**\n\n"
        out += summary(changes, ignoredKeys: ignoredKeys) + "\n"
        guard !changes.isEmpty else { return out }

        out += "\n| Cambio | Ruta | A | B |\n|---|---|---|---|\n"
        for change in changes {
            out += "| \(change.kind.label) | `\(escapeCode(change.path))` "
            out += "| \(code(cell(change.before))) | \(code(cell(change.after))) |\n"
        }
        return out
    }

    /// Un valor vacío o con barra vertical rompería la tabla.
    private static func code(_ text: String) -> String {
        text == "—" ? "—" : "`\(escapeCode(text))`"
    }

    private static func escapeCode(_ text: String) -> String {
        // Dentro de comillas invertidas solo estorba la barra vertical, que corta la celda.
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
