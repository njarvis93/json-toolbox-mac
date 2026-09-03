import Foundation

/// Conversión entre un documento y su literal de string escapado.
///
/// Va *encima* del texto ya formateado: no toca el parser ni el árbol. Escapar un
/// JSON válido produce otro JSON válido (un string en la raíz), así que el documento
/// escapado se sigue pudiendo validar, formatear y desescapar sin salir del editor.
public enum JSONEscaping {

    /// Texto → literal de string JSON, con comillas incluidas.
    public static func escape(_ text: String) -> String {
        JSONFormatter.escape(text)
    }

    /// Literal escapado → texto.
    ///
    /// Acepta el literal completo (`"{\"a\":1}"`) y también el cuerpo suelto
    /// (`{\"a\":1}`), que es lo que queda al copiar de un log o de código fuente.
    public static func unescape(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JSONError("No hay nada que desescapar", line: 1, column: 1, offset: 0)
        }
        var scalars = Array(trimmed.unicodeScalars)
        // Se quitan las comillas exteriores solo si delimitan de verdad todo el literal.
        // `"a": "b"` empieza y acaba por comilla sin ser uno, y ahí hay que dejarlo estar.
        if scalars.count >= 2, scalars.first == "\"", scalars.last == "\"",
            !hasUnescapedQuote(scalars[1..<(scalars.count - 1)])
        {
            scalars = Array(scalars[1..<(scalars.count - 1)])
        }
        return try unescapeBody(scalars)
    }

    private static func hasUnescapedQuote(_ body: ArraySlice<UnicodeScalar>) -> Bool {
        var escaped = false
        for s in body {
            if escaped { escaped = false; continue }
            if s == "\\" { escaped = true; continue }
            if s == "\"" { return true }
        }
        return false
    }

    /// Desescapa el cuerpo de un literal, sin comillas.
    ///
    /// Duplica en parte a `JSONString.unescape`, que trabaja sobre bytes de un token ya
    /// validado por el léxico. Aquí la entrada es texto arbitrario pegado por el usuario:
    /// hace falta detectar los escapes inválidos y decir en qué línea y columna están.
    private static func unescapeBody(_ scalars: [UnicodeScalar]) throws -> String {
        var out = String.UnicodeScalarView()
        var i = 0
        var line = 1, column = 1, offset = 0
        var pendingHighSurrogate: UInt32?

        func err(_ message: String) -> JSONError {
            JSONError(message, line: line, column: column, offset: offset)
        }

        func advance(_ n: Int = 1) {
            for _ in 0..<n {
                guard i < scalars.count else { return }
                let s = scalars[i]
                if s == "\n" { line += 1; column = 1 } else { column += 1 }
                offset += UTF8.width(of: s)
                i += 1
            }
        }

        func flushPending() {
            if pendingHighSurrogate != nil {
                out.append(UnicodeScalar(0xFFFD)!)
                pendingHighSurrogate = nil
            }
        }

        while i < scalars.count {
            let s = scalars[i]
            guard s == "\\" else {
                flushPending()
                out.append(s)
                advance()
                continue
            }
            let (startLine, startColumn, startOffset) = (line, column, offset)
            advance()  // la barra
            guard i < scalars.count else {
                throw JSONError(
                    "Escape incompleto al final del texto",
                    line: startLine, column: startColumn, offset: startOffset)
            }
            let e = scalars[i]
            advance()

            if e == "u" {
                guard i + 4 <= scalars.count else {
                    throw JSONError(
                        "Escape \\u incompleto: faltan dígitos hexadecimales",
                        line: startLine, column: startColumn, offset: startOffset)
                }
                var hex = ""
                for k in 0..<4 {
                    let d = scalars[i + k]
                    guard d.properties.isASCIIHexDigit else {
                        throw JSONError(
                            "Escape \\u con dígito hexadecimal inválido \"\(d)\"",
                            line: startLine, column: startColumn, offset: startOffset)
                    }
                    hex.unicodeScalars.append(d)
                }
                advance(4)
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
                continue
            }

            flushPending()
            let map: [UnicodeScalar: UnicodeScalar] = [
                "\"": "\"", "\\": "\\", "/": "/",
                "b": UnicodeScalar(UInt8(8)), "f": UnicodeScalar(UInt8(12)),
                "n": "\n", "r": "\r", "t": "\t",
            ]
            guard let replacement = map[e] else {
                throw JSONError(
                    "Escape desconocido \\\(e)",
                    line: startLine, column: startColumn, offset: startOffset)
            }
            out.append(replacement)
        }
        flushPending()
        return String(out)
    }
}

private extension UTF8 {
    static func width(of scalar: UnicodeScalar) -> Int {
        switch scalar.value {
        case 0..<0x80: return 1
        case 0x80..<0x800: return 2
        case 0x800..<0x10000: return 3
        default: return 4
        }
    }
}
