import Foundation

public enum IndentStyle: Equatable, Hashable, Identifiable {
    case spaces(Int)
    case tab

    public var unit: String {
        switch self {
        case .spaces(let n): return String(repeating: " ", count: n)
        case .tab: return "\t"
        }
    }

    public var label: String {
        switch self {
        case .spaces(let n): return "\(n) espacios"
        case .tab: return "Tabulador"
        }
    }

    public var id: String { label }

    public static let options: [IndentStyle] = [.spaces(2), .spaces(4), .tab]
}

/// Formatea reemitiendo los tokens del documento original.
///
/// No pasa por `Double` ni por `JSONSerialization`, así que los literales
/// numéricos sobreviven exactos: `90071992547409931` no se degrada y `1.50`
/// no se normaliza a `1.5`. Un round-trip parse→stringify rompe ambos.
public enum JSONFormatter {

    public static func pretty(_ doc: JSONDocument, indent: IndentStyle = .spaces(2)) -> String {
        emit(doc, indentUnit: indent.unit)
    }

    public static func minified(_ doc: JSONDocument) -> String {
        emit(doc, indentUnit: nil)
    }

    public static func pretty(_ text: String, indent: IndentStyle = .spaces(2)) throws -> String {
        pretty(try JSONParser.parse(text), indent: indent)
    }

    public static func minified(_ text: String) throws -> String {
        minified(try JSONParser.parse(text))
    }

    private static func emit(_ doc: JSONDocument, indentUnit: String?) -> String {
        let tokens = doc.tokens
        let bytes = doc.bytes
        let pretty = indentUnit != nil
        var out = ""
        out.reserveCapacity(bytes.count + bytes.count / 3)
        var depth = 0

        func newline() -> String {
            guard let unit = indentUnit else { return "" }
            return "\n" + String(repeating: unit, count: depth)
        }

        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let s = t.text(in: bytes)

            if s == "{" || s == "[" {
                let close = s == "{" ? "}" : "]"
                if i + 1 < tokens.count && tokens[i + 1].text(in: bytes) == close {
                    out += s + close  // contenedor vacío en una sola línea
                    i += 2
                    continue
                }
                out += s
                depth += 1
                out += newline()
                i += 1
                continue
            }
            if s == "}" || s == "]" {
                depth -= 1
                out += newline() + s
                i += 1
                continue
            }
            if s == "," {
                out += "," + newline()
                i += 1
                continue
            }
            if s == ":" {
                out += pretty ? ": " : ":"
                i += 1
                continue
            }
            out += s
            i += 1
        }
        return out
    }

    /// Serializa un árbol (para "ordenar claves", donde el orden de tokens ya no sirve).
    public static func render(_ value: JSONValue, indent: IndentStyle? = .spaces(2), depth: Int = 0) -> String
    {
        let unit = indent?.unit
        let pad = { (d: Int) in unit.map { String(repeating: $0, count: d) } ?? "" }
        let nl = unit == nil ? "" : "\n"
        let sep = unit == nil ? ":" : ": "

        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let raw): return raw
        case .string(let s): return escape(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items.map { pad(depth + 1) + render($0, indent: indent, depth: depth + 1) }
                .joined(separator: "," + nl)
            return "[" + nl + body + nl + pad(depth) + "]"
        case .object(let obj):
            if obj.count == 0 { return "{}" }
            let body = obj.keys.map { k in
                pad(depth + 1) + escape(k) + sep + render(obj[k]!, indent: indent, depth: depth + 1)
            }.joined(separator: "," + nl)
            return "{" + nl + body + nl + pad(depth) + "}"
        }
    }

    static func escape(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
