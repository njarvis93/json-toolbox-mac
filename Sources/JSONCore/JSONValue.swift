import Foundation

/// Objeto JSON que conserva el orden de inserción de las claves.
public struct JSONObject {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else {
                storage[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    public var count: Int { keys.count }
    public func contains(_ key: String) -> Bool { storage[key] != nil }
    public var sortedByKey: JSONObject {
        var out = JSONObject()
        for k in keys.sorted() { out[k] = storage[k] }
        return out
    }
}

public indirect enum JSONValue {
    case object(JSONObject)
    case array([JSONValue])
    case string(String)
    /// El literal numérico tal cual aparece en el documento. No se convierte a
    /// Double en ningún momento: así `90071992547409931` y `1.50` sobreviven.
    case number(raw: String)
    case bool(Bool)
    case null

    public var typeName: String {
        switch self {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .null: return "null"
        }
    }

    /// Número de nodos del árbol, para la barra de estado.
    public var nodeCount: Int {
        switch self {
        case .object(let o): return 1 + o.keys.reduce(0) { $0 + (o[$1]?.nodeCount ?? 0) }
        case .array(let a): return 1 + a.reduce(0) { $0 + $1.nodeCount }
        default: return 1
        }
    }

    /// Ordena recursivamente las claves de todos los objetos.
    public var keysSorted: JSONValue {
        switch self {
        case .object(let o):
            var out = JSONObject()
            for k in o.keys.sorted() { out[k] = o[k]?.keysSorted }
            return .object(out)
        case .array(let a):
            return .array(a.map { $0.keysSorted })
        default:
            return self
        }
    }
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)):
            if a == b { return true }
            // "1.50" y "1.5" son el mismo número aunque no el mismo literal.
            guard let x = Double(a), let y = Double(b) else { return false }
            return x == y
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            for k in a.keys {
                guard let av = a[k], let bv = b[k], av == bv else { return false }
            }
            return true
        default: return false
        }
    }
}
