import Foundation

/// Consultas JSONPath sobre el árbol posicionado.
///
/// Subconjunto escrito a mano, como decía el plan: JSONPath completo (expresiones de script,
/// uniones, rebanadas con paso) es mucho más de lo que hace falta para inspeccionar un documento,
/// y no merece una dependencia. Lo que se admite:
///
/// | | |
/// |---|---|
/// | `$` | la raíz |
/// | `.clave` / `['clave']` | un hijo; la forma con corchetes vale para claves con puntos o espacios |
/// | `[2]` / `[-1]` | un elemento del array; los negativos cuentan desde el final |
/// | `.*` / `[*]` | todos los hijos |
/// | `..clave` | esa clave a cualquier profundidad |
/// | `..*` | todos los descendientes |
/// | `[?(@.clave)]` | los hijos que tengan esa clave |
/// | `[?(@.clave > 10)]` | ídem, comparando: `==`, `!=`, `<`, `<=`, `>`, `>=` |
///
/// Va sobre `JSONNode` y no sobre `JSONValue` porque el resultado tiene que poder señalarse en
/// el editor: una consulta que devuelve valores sueltos, sin posición, no sirve para navegar.
public enum JSONPath {

    public static func evaluate(_ expression: String, in root: JSONNode) throws -> [JSONNode] {
        var parser = Parser(Array(expression.trimmingCharacters(in: .whitespaces)))
        let steps = try parser.parse()
        var current = [root]
        for step in steps { current = apply(step, to: current) }
        return current
    }

    // MARK: - Gramática

    enum Step: Equatable {
        case child(String)
        case index(Int)
        case allChildren
        case descendant(String)
        case allDescendants
        case filter(Filter)
    }

    struct Filter: Equatable {
        let key: String
        /// Sin comparación, el filtro es "que exista esa clave".
        let comparison: Comparison?
    }

    struct Comparison: Equatable {
        let op: Op
        let literal: Literal
    }

    enum Op: String, Equatable {
        case eq = "==", ne = "!=", lt = "<", le = "<=", gt = ">", ge = ">="
    }

    enum Literal: Equatable {
        case number(String)
        case string(String)
        case bool(Bool)
        case null
    }

    // MARK: - Evaluación

    private static func apply(_ step: Step, to nodes: [JSONNode]) -> [JSONNode] {
        var out: [JSONNode] = []
        for node in nodes {
            switch step {
            case .child(let name):
                out += node.children.filter { $0.key == name }
            case .index(let index):
                guard node.kind == .array else { continue }
                let real = index < 0 ? node.children.count + index : index
                if real >= 0, real < node.children.count { out.append(node.children[real]) }
            case .allChildren:
                out += node.children
            // Se mira cada nodo, no los hijos de cada nodo: así el resultado sale en orden de
            // documento. Recogiendo los hijos de cada visita, `$..x` sobre
            // `{"a":{"x":1},"x":2}` devolvía la `x` de arriba antes que la de dentro de `a`.
            case .descendant(let name):
                node.forEachNode { if $0.path != node.path, $0.key == name { out.append($0) } }
            case .allDescendants:
                node.forEachNode { if $0.path != node.path { out.append($0) } }
            case .filter(let filter):
                out += node.children.filter { matches(filter, $0) }
            }
        }
        return deduplicated(out)
    }

    /// `..` puede llegar al mismo nodo por dos caminos; el orden de documento se conserva.
    private static func deduplicated(_ nodes: [JSONNode]) -> [JSONNode] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.path).inserted }
    }

    private static func matches(_ filter: Filter, _ node: JSONNode) -> Bool {
        guard let field = node.children.first(where: { $0.key == filter.key }) else { return false }
        guard let comparison = filter.comparison else { return true }
        return compare(field, comparison)
    }

    private static func compare(_ node: JSONNode, _ comparison: Comparison) -> Bool {
        let equal: Bool
        switch comparison.literal {
        case .null:
            equal = node.kind == .null
        case .bool(let b):
            equal = node.kind == .bool && node.scalarText == (b ? "true" : "false")
        case .number(let raw):
            equal = node.kind == .number && Double(node.scalarText ?? "") == Double(raw)
        case .string(let s):
            equal = node.kind == .string && node.scalarText == s
        }

        switch comparison.op {
        case .eq: return equal
        case .ne: return !equal
        case .lt, .le, .gt, .ge:
            return ordered(node, comparison)
        }
    }

    private static func ordered(_ node: JSONNode, _ comparison: Comparison) -> Bool {
        // Los números se comparan como números (`9` < `10`) y las cadenas alfabéticamente.
        // Comparar tipos distintos no es un error: sencillamente no cumple.
        if case .number(let raw) = comparison.literal,
            node.kind == .number,
            let a = Double(node.scalarText ?? ""), let b = Double(raw)
        {
            return satisfies(comparison.op, a < b, a > b, a == b)
        }
        if case .string(let s) = comparison.literal, node.kind == .string, let a = node.scalarText {
            return satisfies(comparison.op, a < s, a > s, a == s)
        }
        return false
    }

    private static func satisfies(_ op: Op, _ less: Bool, _ greater: Bool, _ equal: Bool) -> Bool {
        switch op {
        case .lt: return less
        case .le: return less || equal
        case .gt: return greater
        case .ge: return greater || equal
        case .eq, .ne: return false
        }
    }

    // MARK: - Análisis sintáctico

    private struct Parser {
        let chars: [Character]
        var i = 0

        init(_ chars: [Character]) { self.chars = chars }

        private func err(_ message: String) -> JSONError {
            JSONError(message, line: 1, column: i + 1, offset: i)
        }

        private var current: Character? { i < chars.count ? chars[i] : nil }

        mutating func parse() throws -> [Step] {
            guard !chars.isEmpty else { throw err("Consulta vacía") }
            guard current == "$" else { throw err("La consulta tiene que empezar por \"$\"") }
            i += 1

            var steps: [Step] = []
            while let c = current {
                if c == "." {
                    steps.append(try dotStep())
                } else if c == "[" {
                    steps.append(try bracketStep())
                } else {
                    throw err("Se esperaba \".\" o \"[\", se encontró \"\(c)\"")
                }
            }
            return steps
        }

        private mutating func dotStep() throws -> Step {
            i += 1
            if current == "." {  // ..clave
                i += 1
                if current == "*" { i += 1; return .allDescendants }
                return .descendant(try name())
            }
            if current == "*" { i += 1; return .allChildren }
            return .child(try name())
        }

        private mutating func bracketStep() throws -> Step {
            i += 1
            skipSpaces()
            let step: Step
            switch current {
            case "*":
                i += 1
                step = .allChildren
            case "?":
                step = .filter(try filter())
            case "'", "\"":
                step = .child(try quoted())
            default:
                step = .index(try integer())
            }
            skipSpaces()
            guard current == "]" else { throw err("Falta \"]\"") }
            i += 1
            return step
        }

        private mutating func filter() throws -> Filter {
            i += 1  // ?
            guard current == "(" else { throw err("Se esperaba \"(\" tras \"?\"") }
            i += 1
            skipSpaces()
            guard current == "@" else { throw err("Un filtro tiene que empezar por \"@\"") }
            i += 1
            guard current == "." else { throw err("Se esperaba \".\" tras \"@\"") }
            i += 1
            let key = try fieldName()
            skipSpaces()

            if current == ")" {
                i += 1
                return Filter(key: key, comparison: nil)
            }
            let op = try comparisonOperator()
            skipSpaces()
            let value = try literal()
            skipSpaces()
            guard current == ")" else { throw err("Falta \")\" al cerrar el filtro") }
            i += 1
            return Filter(key: key, comparison: Comparison(op: op, literal: value))
        }

        private mutating func comparisonOperator() throws -> Op {
            for raw in ["==", "!=", "<=", ">=", "<", ">"] {
                let symbol = Array(raw)
                if i + symbol.count <= chars.count, Array(chars[i..<(i + symbol.count)]) == symbol {
                    i += symbol.count
                    return Op(rawValue: raw)!
                }
            }
            throw err("Comparación no reconocida; se admiten ==, !=, <, <=, > y >=")
        }

        private mutating func literal() throws -> Literal {
            if current == "'" || current == "\"" { return .string(try quoted()) }
            for (word, value) in [("true", Literal.bool(true)), ("false", .bool(false)), ("null", .null)] {
                let letters = Array(word)
                if i + letters.count <= chars.count, Array(chars[i..<(i + letters.count)]) == letters {
                    i += letters.count
                    return value
                }
            }
            let start = i
            if current == "-" { i += 1 }
            while let c = current, c.isNumber || c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                i += 1
            }
            let raw = String(chars[start..<i])
            guard !raw.isEmpty, Double(raw) != nil else {
                throw err("Valor no reconocido en el filtro")
            }
            return .number(raw)
        }

        private mutating func quoted() throws -> String {
            let quote = chars[i]
            i += 1
            var out = ""
            while let c = current, c != quote {
                out.append(c)
                i += 1
            }
            guard current == quote else { throw err("Falta la comilla de cierre") }
            i += 1
            return out
        }

        private mutating func integer() throws -> Int {
            let start = i
            if current == "-" { i += 1 }
            while let c = current, c.isNumber { i += 1 }
            guard let value = Int(String(chars[start..<i])) else {
                throw err("Se esperaba un índice, \"*\", una clave entre comillas o un filtro")
            }
            return value
        }

        /// Nombre de campo dentro de un filtro. Termina donde empieza el operador o el
        /// espacio: con las reglas de `name()`, `@.precio > 10` se leía como una clave
        /// llamada "precio > 10".
        private mutating func fieldName() throws -> String {
            let start = i
            while let c = current, !" )].[=!<>".contains(c) { i += 1 }
            let raw = String(chars[start..<i])
            guard !raw.isEmpty else { throw err("Se esperaba un nombre de clave tras \"@.\"") }
            return raw
        }

        /// Nombre sin comillas: lo que hay hasta el siguiente `.`, `[` o final.
        private mutating func name() throws -> String {
            let start = i
            while let c = current, c != ".", c != "[", c != "]" { i += 1 }
            let raw = String(chars[start..<i])
            guard !raw.isEmpty else { throw err("Se esperaba un nombre de clave") }
            return raw
        }

        private mutating func skipSpaces() {
            while current == " " { i += 1 }
        }
    }
}
