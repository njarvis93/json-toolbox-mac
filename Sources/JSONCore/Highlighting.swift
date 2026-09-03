import Foundation

public enum SyntaxRole: Equatable {
    case key, string, number, literal, punctuation
}

public struct SyntaxSpan: Equatable {
    /// Rango en unidades UTF-16, listo para NSAttributedString.
    public let location: Int
    public let length: Int
    public let role: SyntaxRole
}

public enum SyntaxScanner {
    /// Resalta también documentos inválidos: colorea lo que se pudo tokenizar
    /// y deja el resto sin atributos, en vez de quedarse en blanco.
    public static func spans(_ text: String) -> [SyntaxSpan] {
        let (tokens, _) = Lexer.scan(text)
        let bytes = Array(text.utf8)
        return tokens.enumerated().map { index, t in
            let role: SyntaxRole
            switch t.kind {
            case .string:
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                role = (next?.text(in: bytes) == ":") ? .key : .string
            case .number: role = .number
            case .literal: role = .literal
            case .punctuation: role = .punctuation
            }
            return SyntaxSpan(location: t.utf16Start, length: t.utf16End - t.utf16Start, role: role)
        }
    }
}
