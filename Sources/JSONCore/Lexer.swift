import Foundation

public struct Token: Equatable {
    public enum Kind: Equatable { case string, number, literal, punctuation }
    public let kind: Kind
    /// Rango en bytes UTF-8 sobre el documento original; el literal se conserva intacto.
    public let start: Int
    public let end: Int
    /// El mismo rango en unidades UTF-16, que es lo que usa NSAttributedString.
    public let utf16Start: Int
    public let utf16End: Int
    public let line: Int
    public let column: Int

    public func text(in bytes: [UInt8]) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }
}

/// Tokenizador sobre los bytes UTF-8 del documento.
/// Lleva línea, columna (en caracteres, no en bytes) y desplazamiento UTF-16.
public struct Lexer {
    public let bytes: [UInt8]
    private var i = 0
    private var line = 1
    private var column = 1
    private var utf16 = 0

    public init(_ text: String) { self.bytes = Array(text.utf8) }
    public init(bytes: [UInt8]) { self.bytes = bytes }

    private var current: UInt8? { i < bytes.count ? bytes[i] : nil }

    private mutating func advance(_ n: Int = 1) {
        for _ in 0..<n {
            guard i < bytes.count else { return }
            let b = bytes[i]
            if b & 0xC0 != 0x80 {  // no cuenta bytes de continuación
                if b == 0x0A { line += 1; column = 1 } else { column += 1 }
                utf16 += b >= 0xF0 ? 2 : 1  // fuera del BMP ocupa un par suplente
            }
            i += 1
        }
    }

    private func err(_ msg: String) -> JSONError {
        JSONError(msg, line: line, column: column, offset: i)
    }

    /// Tokeniza el documento completo. Lanza `JSONError` en el primer problema léxico.
    public mutating func tokenize() throws -> [Token] {
        var out: [Token] = []
        while let token = try next() { out.append(token) }
        return out
    }

    /// Tokeniza hasta donde pueda y devuelve lo obtenido junto al error, si lo hubo.
    /// El resaltado de sintaxis lo usa para colorear también documentos inválidos.
    public static func scan(_ text: String) -> (tokens: [Token], error: JSONError?) {
        var lexer = Lexer(text)
        var out: [Token] = []
        do {
            while let token = try lexer.next() { out.append(token) }
            return (out, nil)
        } catch let e as JSONError {
            return (out, e)
        } catch {
            return (out, JSONError("Error léxico desconocido", line: 1, column: 1, offset: 0))
        }
    }

    private mutating func next() throws -> Token? {
        skipWhitespace()
        guard let b = current else { return nil }
        let (l, c, s, u) = (line, column, i, utf16)
        switch b {
        case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["),
            UInt8(ascii: "]"), UInt8(ascii: ":"), UInt8(ascii: ","):
            advance()
            return token(.punctuation, s, u, l, c)
        case UInt8(ascii: "\""):
            try scanString()
            return token(.string, s, u, l, c)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            try scanNumber()
            return token(.number, s, u, l, c)
        case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"):
            try scanLiteral()
            return token(.literal, s, u, l, c)
        default:
            throw err("Carácter inesperado \(describe(b))")
        }
    }

    private func token(_ kind: Token.Kind, _ s: Int, _ u: Int, _ l: Int, _ c: Int) -> Token {
        Token(kind: kind, start: s, end: i, utf16Start: u, utf16End: utf16, line: l, column: c)
    }

    private func describe(_ b: UInt8) -> String {
        b >= 0x20 && b < 0x7F ? "'\(Character(UnicodeScalar(b)))'" : String(format: "0x%02X", b)
    }

    private mutating func skipWhitespace() {
        while let b = current, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { advance() }
    }

    private mutating func scanString() throws {
        advance()  // comilla de apertura
        while true {
            guard let b = current else { throw err("Cadena sin cerrar") }
            if b == UInt8(ascii: "\"") { advance(); return }
            if b == UInt8(ascii: "\\") {
                advance()
                guard let e = current else { throw err("Escape incompleto al final del documento") }
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                    UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                    advance()
                case UInt8(ascii: "u"):
                    advance()
                    for _ in 0..<4 {
                        guard let h = current, isHex(h) else {
                            throw err("Escape \\u con dígito hexadecimal inválido")
                        }
                        advance()
                    }
                default:
                    throw err("Escape desconocido \\\(describe(e))")
                }
                continue
            }
            if b < 0x20 { throw err("Carácter de control sin escapar dentro de la cadena") }
            advance()
        }
    }

    private func isHex(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || ((b | 0x20) >= UInt8(ascii: "a") && (b | 0x20) <= UInt8(ascii: "f"))
    }

    private func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

    private mutating func scanNumber() throws {
        if current == UInt8(ascii: "-") { advance() }
        guard let first = current, isDigit(first) else { throw err("Se esperaba un dígito") }
        if first == UInt8(ascii: "0") {
            advance()
            if let b = current, isDigit(b) { throw err("Un número no puede empezar por 0") }
        } else {
            while let b = current, isDigit(b) { advance() }
        }
        if current == UInt8(ascii: ".") {
            advance()
            guard let b = current, isDigit(b) else {
                throw err("Se esperaba un dígito tras el punto decimal")
            }
            while let b = current, isDigit(b) { advance() }
        }
        if let e = current, e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            advance()
            if let s = current, s == UInt8(ascii: "+") || s == UInt8(ascii: "-") { advance() }
            guard let b = current, isDigit(b) else { throw err("Exponente sin dígitos") }
            while let b = current, isDigit(b) { advance() }
        }
    }

    private mutating func scanLiteral() throws {
        for word in ["true", "false", "null"] {
            let w = Array(word.utf8)
            if i + w.count <= bytes.count && Array(bytes[i..<(i + w.count)]) == w {
                advance(w.count)
                return
            }
        }
        throw err("Se esperaba true, false o null")
    }
}
