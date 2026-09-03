import AppKit
import Foundation

/// Leer de disco y del portapapeles con el mismo límite y los mismos mensajes en los dos sitios
/// que importan contenido (el editor y cada lado de Comparar).
enum FileImport {
    @MainActor
    static func read(_ url: URL, flash: (String) -> Void) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= DocumentModel.sizeLimit else {
            flash("\"\(url.lastPathComponent)\" pesa \(humanSize(size)) — el límite es 10 MB")
            return nil
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            flash("No se pudo leer \"\(url.lastPathComponent)\" como UTF-8")
            return nil
        }
        return contents
    }

    @MainActor
    static func pasteboard(flash: (String) -> Void) -> String? {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else {
            flash("El portapapeles no contiene texto")
            return nil
        }
        guard string.utf8.count <= DocumentModel.sizeLimit else {
            flash("El contenido del portapapeles supera los 10 MB")
            return nil
        }
        return string
    }

    static func humanSize(_ bytes: Int) -> String {
        bytes < 1024
            ? "\(bytes) B"
            : bytes < 1024 * 1024
                ? String(format: "%.1f KB", Double(bytes) / 1024)
                : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
