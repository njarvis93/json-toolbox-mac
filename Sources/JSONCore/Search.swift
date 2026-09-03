import Foundation

/// Búsqueda por clave y por valor sobre el árbol posicionado.
///
/// Va sobre `JSONNode` y no sobre el texto a propósito: buscar `precio` tiene que encontrar la
/// clave `precio` esté escrita como esté —minificada, en otra línea, con la sangría que sea— y
/// no encontrar la palabra "precio" dentro de una cadena si lo que se pide son claves. Eso es
/// exactamente lo que un buscador de texto no sabe distinguir.
public enum JSONSearch {

    public enum Scope: String, CaseIterable, Identifiable, Equatable {
        case all, keys, values, path

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .all: return "Todo"
            case .keys: return "Claves"
            case .values: return "Valores"
            case .path: return "Ruta"
            }
        }

        /// Texto de ejemplo del campo: escribir una ruta no se parece en nada a buscar texto.
        public var placeholder: String {
            self == .path ? "$.lineas[?(@.precio > 10)]" : "Buscar clave o valor"
        }
    }

    public struct Result: Equatable {
        /// Coincidencias en preorden, que es el orden en que se ven en el árbol.
        public let matches: [JSONNode]
        /// Rutas de las coincidencias **y de sus ancestros**: es lo que hay que dejar visible
        /// para que una coincidencia hundida en el árbol se vea sin perder el contexto.
        public let visiblePaths: Set<String>
        /// Consulta mal escrita. Solo aparece con el ámbito `.path`: buscar texto no puede
        /// fallar, pero una ruta sí.
        public let error: String?

        public init(matches: [JSONNode], visiblePaths: Set<String>, error: String? = nil) {
            self.matches = matches
            self.visiblePaths = visiblePaths
            self.error = error
        }

        public var count: Int { matches.count }
        public var isEmpty: Bool { matches.isEmpty }

        public static let none = Result(matches: [], visiblePaths: [])
    }

    public static func find(_ query: String, in root: JSONNode, scope: Scope = .all) -> Result {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .none }

        // Con ámbito de ruta, quién coincide lo decide `JSONPath`; el recorrido de después es
        // el mismo, así que los ancestros, el orden de documento y el filtrado del árbol salen
        // igual para los dos casos.
        var selected: Set<String>?
        if scope == .path {
            do {
                selected = Set(try JSONPath.evaluate(needle, in: root).map(\.path))
            } catch let e as JSONError {
                // Sin el "línea 1" de `description`: una consulta siempre tiene una sola línea.
                return Result(matches: [], visiblePaths: [], error: "\(e.message) — columna \(e.column)")
            } catch {
                return Result(matches: [], visiblePaths: [], error: "Consulta no válida")
            }
        }

        var matches: [JSONNode] = []
        var visible: Set<String> = []

        func walk(_ node: JSONNode, ancestors: [String]) {
            if selected.map({ $0.contains(node.path) }) ?? isMatch(node, needle, scope) {
                matches.append(node)
                visible.insert(node.path)
                visible.formUnion(ancestors)
            }
            let chain = ancestors + [node.path]
            for child in node.children { walk(child, ancestors: chain) }
        }
        walk(root, ancestors: [])
        return Result(matches: matches, visiblePaths: visible)
    }

    private static func isMatch(_ node: JSONNode, _ needle: String, _ scope: Scope) -> Bool {
        switch scope {
        case .keys:
            return node.key.map { contains($0, needle) } ?? false
        case .values:
            return node.scalarText.map { contains($0, needle) } ?? false
        case .all:
            return isMatch(node, needle, .keys) || isMatch(node, needle, .values)
        case .path:
            return false  // lo resuelve JSONPath antes del recorrido
        }
    }

    /// Sin distinguir mayúsculas ni tildes: buscar `articulo` tiene que encontrar `Artículo`.
    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
