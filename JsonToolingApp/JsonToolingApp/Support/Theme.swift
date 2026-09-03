import SwiftUI
import AppKit
import JSONCore

enum Theme {
    static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // Colores de sintaxis en el espíritu de Xcode, resueltos por apariencia.
    static func color(for role: SyntaxRole, dark: Bool) -> NSColor {
        switch role {
        case .key: return dark ? NSColor(hex: 0x7FB6F5) : NSColor(hex: 0x0B6BB5)
        case .string: return dark ? NSColor(hex: 0xFC6A5D) : NSColor(hex: 0xC8341F)
        case .number: return dark ? NSColor(hex: 0xD0BF69) : NSColor(hex: 0x2A2AD0)
        case .literal: return dark ? NSColor(hex: 0xFC5FA3) : NSColor(hex: 0x9A1F8F)
        case .punctuation: return NSColor.tertiaryLabelColor
        }
    }

    /// Mismo color que tendría el valor en el texto, para que el árbol y el editor se lean
    /// como la misma cosa. `NSColor(name:dynamicProvider:)` resuelve claro/oscuro solo, que es
    /// lo que aquí no se puede preguntar como en `JSONTextView`.
    static func color(for kind: JSONNode.Kind) -> Color {
        switch kind {
        case .string: return dynamic(light: 0xC8341F, dark: 0xFC6A5D)
        case .number: return dynamic(light: 0x2A2AD0, dark: 0xD0BF69)
        case .bool, .null: return dynamic(light: 0x9A1F8F, dark: 0xFC5FA3)
        case .object, .array: return Color.secondary
        }
    }

    static let keyColor = dynamic(light: 0x0B6BB5, dark: 0x7FB6F5)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(hex: dark) : NSColor(hex: light)
            })
    }

    static func swiftUIColor(for kind: AlignedRow.Kind) -> Color {
        switch kind {
        case .equal: return .clear
        case .added: return Color.green.opacity(0.16)
        case .removed: return Color.red.opacity(0.14)
        }
    }

    static func color(for kind: JSONChange.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        case .moved: return .blue
        }
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
