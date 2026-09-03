import Foundation

/// Error de parseo con posición utilizable por la UI.
/// `JSONSerialization` no da línea/columna; esta es la razón de tener parser propio.
public struct JSONError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let line: Int
    public let column: Int
    /// Desplazamiento en bytes UTF-8 desde el inicio del documento.
    public let offset: Int

    public init(_ message: String, line: Int, column: Int, offset: Int) {
        self.message = message
        self.line = line
        self.column = column
        self.offset = offset
    }

    public var description: String { "\(message) — línea \(line), columna \(column)" }
}
