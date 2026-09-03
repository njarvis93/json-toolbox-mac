import Foundation

public struct JSONDocument {
    public let value: JSONValue
    /// Mismo árbol, con la posición de cada valor en el texto. Ver `JSONNode`.
    public let root: JSONNode
    public let tokens: [Token]
    public let bytes: [UInt8]
    public var nodeCount: Int { value.nodeCount }
}

public enum JSONParser {
    public static let maxDepth = 512

    public static func parse(_ text: String) throws -> JSONDocument {
        var lexer = Lexer(text)
        let tokens = try lexer.tokenize()
        let bytes = lexer.bytes
        guard !tokens.isEmpty else {
            throw JSONError("Documento vacío", line: 1, column: 1, offset: 0)
        }
        var p = Cursor(tokens: tokens, bytes: bytes)
        let (value, root) = try p.value(depth: 0, at: "$")
        if let extra = p.peek() {
            throw p.error("Contenido sobrante tras el valor raíz", at: extra)
        }
        return JSONDocument(value: value, root: root, tokens: tokens, bytes: bytes)
    }

    /// Valida sin construir el árbol. Devuelve nil si el documento es válido.
    public static func validate(_ text: String) -> JSONError? {
        do { _ = try parse(text); return nil } catch let e as JSONError { return e } catch {
            return JSONError("Error desconocido", line: 1, column: 1, offset: 0)
        }
    }
}

private struct Cursor {
    let tokens: [Token]
    let bytes: [UInt8]
    var i = 0

    func peek() -> Token? { i < tokens.count ? tokens[i] : nil }
    func text(_ t: Token) -> String { t.text(in: bytes) }

    func error(_ msg: String, at token: Token?) -> JSONError {
        if let token {
            return JSONError(msg, line: token.line, column: token.column, offset: token.start)
        }
        let last = tokens.last
        return JSONError(msg, line: last?.line ?? 1, column: (last?.column ?? 0) + 1, offset: bytes.count)
    }

    /// Ruta de un hijo, con el mismo formato que usa `JSONDiff`.
    func childPath(_ parent: String, key: String) -> String {
        parent == "$" ? key : "\(parent).\(key)"
    }

    func childPath(_ parent: String, index: Int) -> String {
        "\(parent)[\(index)]"
    }

    /// Devuelve el valor y, en paralelo, su nodo posicionado. Van juntos porque los dos
    /// salen del mismo recorrido: separarlos obligaría a parsear dos veces.
    mutating func value(
        depth: Int, at path: String, key: String? = nil,
        keyStart: Int? = nil
    ) throws -> (JSONValue, JSONNode) {
        guard depth <= JSONParser.maxDepth else {
            throw error("Anidamiento demasiado profundo (más de \(JSONParser.maxDepth) niveles)", at: peek())
        }
        guard let t = peek() else { throw error("Fin de documento inesperado", at: nil) }

        func leaf(_ value: JSONValue, _ kind: JSONNode.Kind, _ scalarText: String?) -> (JSONValue, JSONNode) {
            (
                value,
                JSONNode(
                    kind: kind, key: key, path: path,
                    start: t.utf16Start, end: t.utf16End,
                    startWithKey: keyStart ?? t.utf16Start, line: t.line,
                    scalarText: scalarText, children: [])
            )
        }

        switch t.kind {
        case .punctuation:
            let s = text(t)
            if s == "{" { return try object(depth: depth, at: path, key: key, keyStart: keyStart) }
            if s == "[" { return try array(depth: depth, at: path, key: key, keyStart: keyStart) }
            throw error("Se esperaba un valor, se encontró \"\(s)\"", at: t)
        case .string:
            i += 1
            let unescaped = try JSONString.unescape(t, in: bytes)
            return leaf(.string(unescaped), .string, unescaped)
        case .number:
            i += 1
            return leaf(.number(raw: text(t)), .number, text(t))
        case .literal:
            i += 1
            let s = text(t)
            return leaf(s == "null" ? .null : .bool(s == "true"), s == "null" ? .null : .bool, s)
        }
    }

    mutating func object(
        depth: Int, at path: String, key: String?,
        keyStart: Int?
    ) throws -> (JSONValue, JSONNode) {
        let open = tokens[i]
        i += 1  // {
        var obj = JSONObject()
        var children: [JSONNode] = []

        func node(closedAt close: Token) -> JSONNode {
            JSONNode(
                kind: .object, key: key, path: path,
                start: open.utf16Start, end: close.utf16End,
                startWithKey: keyStart ?? open.utf16Start, line: open.line,
                scalarText: nil, children: children)
        }

        if let t = peek(), text(t) == "}" { i += 1; return (.object(obj), node(closedAt: t)) }
        while true {
            guard let k = peek(), k.kind == .string else {
                throw error("Se esperaba una clave entre comillas", at: peek())
            }
            i += 1
            guard let colon = peek(), text(colon) == ":" else {
                throw error("Falta \":\" después de la clave", at: peek())
            }
            i += 1
            let childKey = try JSONString.unescape(k, in: bytes)
            if obj.contains(childKey) {
                throw error("Clave duplicada \"\(childKey)\"", at: k)
            }
            let (childValue, childNode) = try value(
                depth: depth + 1,
                at: childPath(path, key: childKey),
                key: childKey, keyStart: k.utf16Start)
            obj[childKey] = childValue
            children.append(childNode)

            guard let next = peek() else { throw error("Falta \"}\"", at: nil) }
            let s = text(next)
            if s == "," {
                i += 1
                if let after = peek(), text(after) == "}" {
                    throw error("Coma sobrante antes de \"}\"", at: after)
                }
                continue
            }
            if s == "}" { i += 1; return (.object(obj), node(closedAt: next)) }
            throw error("Se esperaba \",\" o \"}\"", at: next)
        }
    }

    mutating func array(
        depth: Int, at path: String, key: String?,
        keyStart: Int?
    ) throws -> (JSONValue, JSONNode) {
        let open = tokens[i]
        i += 1  // [
        var items: [JSONValue] = []
        var children: [JSONNode] = []

        func node(closedAt close: Token) -> JSONNode {
            JSONNode(
                kind: .array, key: key, path: path,
                start: open.utf16Start, end: close.utf16End,
                startWithKey: keyStart ?? open.utf16Start, line: open.line,
                scalarText: nil, children: children)
        }

        if let t = peek(), text(t) == "]" { i += 1; return (.array(items), node(closedAt: t)) }
        while true {
            let (itemValue, itemNode) = try value(
                depth: depth + 1,
                at: childPath(path, index: items.count))
            items.append(itemValue)
            children.append(itemNode)

            guard let next = peek() else { throw error("Falta \"]\"", at: nil) }
            let s = text(next)
            if s == "," {
                i += 1
                if let after = peek(), text(after) == "]" {
                    throw error("Coma sobrante antes de \"]\"", at: after)
                }
                continue
            }
            if s == "]" { i += 1; return (.array(items), node(closedAt: next)) }
            throw error("Se esperaba \",\" o \"]\"", at: next)
        }
    }
}

enum JSONString {
    /// Convierte el literal de cadena (con comillas) en su valor.
    static func unescape(_ token: Token, in bytes: [UInt8]) throws -> String {
        let raw = Array(bytes[(token.start + 1)..<(token.end - 1)])
        if !raw.contains(UInt8(ascii: "\\")) {
            return String(decoding: raw, as: UTF8.self)
        }
        var out = String.UnicodeScalarView()
        var j = 0
        var pendingHighSurrogate: UInt32? = nil

        func flushPending() {
            if let hs = pendingHighSurrogate {
                out.append(UnicodeScalar(0xFFFD)!)
                _ = hs
                pendingHighSurrogate = nil
            }
        }

        while j < raw.count {
            let b = raw[j]
            if b != UInt8(ascii: "\\") {
                flushPending()
                // Copia la secuencia UTF-8 completa tal cual.
                var k = j + 1
                while k < raw.count && raw[k] & 0xC0 == 0x80 { k += 1 }
                out.append(contentsOf: String(decoding: raw[j..<k], as: UTF8.self).unicodeScalars)
                j = k
                continue
            }
            j += 1
            let e = raw[j]
            j += 1
            switch e {
            case UInt8(ascii: "u"):
                let hex = String(decoding: raw[j..<(j + 4)], as: UTF8.self)
                j += 4
                let code = UInt32(hex, radix: 16) ?? 0xFFFD
                if code >= 0xD800 && code <= 0xDBFF {
                    flushPending()
                    pendingHighSurrogate = code
                } else if code >= 0xDC00 && code <= 0xDFFF, let hs = pendingHighSurrogate {
                    let combined = 0x10000 + ((hs - 0xD800) << 10) + (code - 0xDC00)
                    pendingHighSurrogate = nil
                    out.append(UnicodeScalar(combined) ?? UnicodeScalar(0xFFFD)!)
                } else {
                    flushPending()
                    out.append(UnicodeScalar(code) ?? UnicodeScalar(0xFFFD)!)
                }
            default:
                flushPending()
                let map: [UInt8: UnicodeScalar] = [
                    UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\", UInt8(ascii: "/"): "/",
                    UInt8(ascii: "b"): UnicodeScalar(UInt8(8)), UInt8(ascii: "f"): UnicodeScalar(UInt8(12)),
                    UInt8(ascii: "n"): "\n", UInt8(ascii: "r"): "\r", UInt8(ascii: "t"): "\t",
                ]
                out.append(map[e] ?? UnicodeScalar(0xFFFD)!)
            }
        }
        flushPending()
        return String(out)
    }
}
