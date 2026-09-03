import Foundation

/// Conversión entre JSON y XML.
///
/// El XML no tiene tipos ni distingue "un elemento" de "una lista de un elemento", así que
/// hace falta una convención explícita para que el viaje de ida y vuelta no pierda nada:
///
/// - Cada clave de un objeto es un elemento con ese nombre.
/// - Un array es un elemento con `type="array"` y un hijo `<item>` por elemento.
/// - Los valores que no son cadenas llevan `type` (`number`, `bool`, `null`, `object`,
///   `array`); las cadenas no llevan nada, que es el caso común.
/// - Los números viajan como su literal original, igual que en el formateador: `7.50` no
///   se convierte en `7.5` ni `90071992547409931` pierde precisión.
/// - Una clave que no sea un nombre XML válido (espacios, acentos raros, empezar por
///   dígito) se emite como `<entry key="la clave">`.
///
/// Al leer XML escrito a mano, sin `type`, se infiere: un elemento con hijos es un objeto
/// (o un array si todos sus hijos son `<item>`), y uno sin hijos es una cadena.
public enum JSONXML {

    public static let defaultRootName = "root"

    // MARK: - JSON → XML

    public static func toXML(
        _ value: JSONValue,
        root: String = defaultRootName,
        indent: IndentStyle? = .spaces(2)
    ) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        emit(
            value, name: isValidName(root) ? root : defaultRootName,
            keyAttribute: nil, depth: 0, indent: indent, into: &out)
        return out
    }

    private static func emit(
        _ value: JSONValue, name: String, keyAttribute: String?,
        depth: Int, indent: IndentStyle?, into out: inout String
    ) {
        let unit = indent?.unit
        let pad = unit.map { String(repeating: $0, count: depth) } ?? ""
        let nl = unit == nil ? "" : "\n"
        var attrs = ""
        if let keyAttribute { attrs += " key=\"\(escapeAttribute(keyAttribute))\"" }

        func open(_ type: String?) -> String {
            "\(pad)<\(name)\(attrs)\(type.map { " type=\"\($0)\"" } ?? "")>"
        }

        switch value {
        case .null:
            out += "\(pad)<\(name)\(attrs) type=\"null\"/>\(nl)"
        case .bool(let b):
            out += open("bool") + (b ? "true" : "false") + "</\(name)>\(nl)"
        case .number(let raw):
            out += open("number") + raw + "</\(name)>\(nl)"
        case .string(let s):
            out += open(nil) + escapeText(s) + "</\(name)>\(nl)"
        case .array(let items):
            if items.isEmpty {
                out += "\(pad)<\(name)\(attrs) type=\"array\"/>\(nl)"
                return
            }
            out += open("array") + nl
            for item in items {
                emit(item, name: "item", keyAttribute: nil, depth: depth + 1, indent: indent, into: &out)
            }
            out += "\(pad)</\(name)>\(nl)"
        case .object(let obj):
            if obj.count == 0 {
                out += "\(pad)<\(name)\(attrs) type=\"object\"/>\(nl)"
                return
            }
            out += open("object") + nl
            for key in obj.keys {
                let valid = isValidName(key)
                emit(
                    obj[key]!, name: valid ? key : "entry", keyAttribute: valid ? nil : key,
                    depth: depth + 1, indent: indent, into: &out)
            }
            out += "\(pad)</\(name)>\(nl)"
        }
    }

    static func escapeText(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    static func escapeAttribute(_ s: String) -> String {
        var out = escapeText(s)
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out.replacingOccurrences(of: "\n", with: "&#10;")
    }

    /// Subconjunto práctico de `Name` de XML 1.0: suficiente para decidir si una clave
    /// puede ser el nombre del elemento o hay que meterla en `<entry key="…">`.
    public static func isValidName(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return false }
        guard first == "_" || CharacterSet.letters.contains(first) else { return false }
        if s.lowercased().hasPrefix("xml") { return false }
        for c in s.unicodeScalars.dropFirst() {
            let ok =
                c == "_" || c == "-" || c == "."
                || CharacterSet.letters.contains(c) || CharacterSet.decimalDigits.contains(c)
            if !ok { return false }
        }
        return true
    }

    // MARK: - XML → JSON

    public static func toJSON(_ xml: String) throws -> JSONValue {
        let builder = Builder()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = builder
        guard parser.parse() else {
            if let failure = builder.failure { throw failure }
            let e = parser.parserError as NSError?
            throw JSONError(
                "XML no válido: \(e?.localizedDescription ?? "error de sintaxis")",
                line: parser.lineNumber, column: parser.columnNumber, offset: 0)
        }
        if let failure = builder.failure { throw failure }
        guard let root = builder.root else {
            throw JSONError("El XML no tiene ningún elemento", line: 1, column: 1, offset: 0)
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        struct Frame {
            let name: String
            let key: String?
            let type: String?
            var text = ""
            var children: [(key: String, value: JSONValue)] = []
        }

        private var stack: [Frame] = []
        private(set) var root: JSONValue?
        private(set) var failure: JSONError?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String]
        ) {
            stack.append(Frame(name: elementName, key: attributes["key"], type: attributes["type"]))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName: String?
        ) {
            guard let frame = stack.popLast() else { return }
            let value: JSONValue
            do {
                value = try build(frame, parser: parser)
            } catch let e as JSONError {
                if failure == nil { failure = e }
                parser.abortParsing()
                return
            } catch {
                return
            }
            if stack.isEmpty {
                root = value
            } else {
                stack[stack.count - 1].children.append((key: frame.key ?? frame.name, value: value))
            }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            guard failure == nil else { return }
            failure = JSONError(
                "XML no válido: \((parseError as NSError).localizedDescription)",
                line: parser.lineNumber, column: parser.columnNumber, offset: 0)
        }

        private func build(_ frame: Frame, parser: XMLParser) throws -> JSONValue {
            func err(_ message: String) -> JSONError {
                JSONError(message, line: parser.lineNumber, column: parser.columnNumber, offset: 0)
            }
            let text = frame.text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch frame.type {
            case "null":
                return .null
            case "bool":
                guard text == "true" || text == "false" else {
                    throw err("<\(frame.name) type=\"bool\"> con valor \"\(text)\"")
                }
                return .bool(text == "true")
            case "number":
                guard isNumberLiteral(text) else {
                    throw err("<\(frame.name) type=\"number\"> con valor \"\(text)\"")
                }
                return .number(raw: text)
            case "string":
                return .string(frame.text)
            case "array":
                return .array(frame.children.map(\.value))
            case "object":
                return .object(object(from: frame.children))
            case .some(let other):
                throw err("Tipo desconocido type=\"\(other)\" en <\(frame.name)>")
            case nil:
                // XML escrito a mano, sin anotar: se infiere por la forma.
                if frame.children.isEmpty { return .string(frame.text) }
                if frame.children.allSatisfy({ $0.key == "item" }) {
                    return .array(frame.children.map(\.value))
                }
                return .object(object(from: frame.children))
            }
        }

        /// Claves repetidas en el XML se agrupan en un array: es la forma habitual de
        /// escribir listas a mano (`<tag>a</tag><tag>b</tag>`) y perder una sería peor.
        private func object(from children: [(key: String, value: JSONValue)]) -> JSONObject {
            var out = JSONObject()
            var repeatedKeys: Set<String> = []
            for child in children {
                guard let existing = out[child.key] else {
                    out[child.key] = child.value
                    continue
                }
                if repeatedKeys.contains(child.key), case .array(var items) = existing {
                    items.append(child.value)
                    out[child.key] = .array(items)
                } else {
                    repeatedKeys.insert(child.key)
                    out[child.key] = .array([existing, child.value])
                }
            }
            return out
        }
    }

    private static func isNumberLiteral(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var lexer = Lexer(s)
        guard let tokens = try? lexer.tokenize() else { return false }
        return tokens.count == 1 && tokens[0].kind == .number
    }
}
