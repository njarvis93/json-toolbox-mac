import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import JSONCore

/// El documento del editor: su texto, de qué archivo viene, cómo se parsea y en qué se convierte.
///
/// No sabe nada del árbol ni de la comparación. Lo único que sale de aquí hacia fuera es el
/// resultado del parseo, y lo reparte `AppModel` (ver `onParse`).
@MainActor
final class DocumentModel: ObservableObject {
    /// Alcance declarado de la v1. Por encima se rechaza en vez de congelar la ventana.
    static let sizeLimit = 10 * 1024 * 1024

    @Published var text: String = Samples.a { didSet { revalidate() } }
    @Published var name: String = "pedido-4471.json"

    @Published private(set) var fileURL: URL?
    private var lastSavedText: String = Samples.a

    var isDirty: Bool { text != lastSavedText }

    /// Resultado de parsear el editor: árbol, recuento y error, **juntos**.
    ///
    /// Antes eran tres propiedades publicadas que había que acordarse de escribir a la vez y en
    /// el mismo orden. Son un solo valor: una notificación en vez de tres, y ninguna combinación
    /// imposible (árbol nuevo con recuento viejo, por ejemplo).
    struct Parse {
        /// Último árbol **válido**. No se pierde al teclear algo que rompe el JSON: el panel se
        /// queda con la última foto buena y se marca como desfasado, que es menos molesto que
        /// verlo desaparecer con cada carácter a medio escribir.
        var root: JSONNode?
        var nodeCount: Int = 0
        var error: JSONError?
    }

    @Published private(set) var parse = Parse()

    var rootNode: JSONNode? { parse.root }
    var nodeCount: Int { parse.nodeCount }
    var error: JSONError? { parse.error }
    var isValid: Bool { parse.error == nil }
    /// El árbol no corresponde al texto que hay ahora mismo en el editor.
    var isTreeStale: Bool { parse.error != nil }

    @Published var caretLine: Int = 1
    @Published var caretColumn: Int = 1
    /// Última petición de "ir a línea". La consume `JSONTextView` una sola vez, por su id;
    /// no se limpia desde la vista (ver `docs/specs/fase3-ir-a-linea-bucle.md`).
    @Published private(set) var scrollRequest: ScrollRequest?
    private var scrollRequestCount = 0

    /// Mensaje efímero para cosas que no son estado del documento (import fallido, copiado).
    @Published var notice: String?

    /// Se avisa a `AppModel` de cada parseo para que la navegación reaccione: la búsqueda y el
    /// nodo seleccionado viven en el árbol, y el árbol acaba de cambiar. Es un cierre y no una
    /// referencia al otro modelo a propósito — el documento no tiene por qué saber que existe
    /// una vista de estructura.
    var onParse: ((Parse) -> Void)?

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        revalidate()
    }

    // MARK: - Acciones

    func format() {
        guard let doc = try? JSONParser.parse(text) else { revalidate(); return }
        text = JSONFormatter.pretty(doc, indent: preferences.indent)
    }

    func minify() {
        guard let doc = try? JSONParser.parse(text) else { revalidate(); return }
        text = JSONFormatter.minified(doc)
    }

    func sortKeys() {
        guard let doc = try? JSONParser.parse(text) else { revalidate(); return }
        text = JSONFormatter.render(doc.value.keysSorted, indent: preferences.indent)
    }

    /// Cambiar la sangría tiene que verse en el documento.
    ///
    /// Antes solo guardaba la preferencia y afectaba al *siguiente* Formatear, así que elegir
    /// "4 espacios" no hacía nada visible y el selector parecía roto. Se aplica al momento; es
    /// una acción explícita del usuario y ⌘Z la deshace como cualquier otro formateo.
    func reindent() {
        guard let doc = try? JSONParser.parse(text) else { return }
        text = JSONFormatter.pretty(doc, indent: preferences.indent)
    }

    // MARK: - Convertir

    /// El resultado sigue siendo JSON válido (una cadena en la raíz), así que se puede
    /// quedar en el editor sin que la barra de estado se ponga en rojo.
    func escapeAsString() {
        text = JSONEscaping.escape(text)
    }

    func unescapeFromString() {
        do {
            text = try JSONEscaping.unescape(text)
        } catch let error as JSONError {
            flash("No se pudo desescapar: \(error.description)")
        } catch {
            flash("No se pudo desescapar")
        }
    }

    /// El XML va al portapapeles en vez de al editor: el editor es de JSON — dejarle
    /// dentro un documento XML lo pondría en rojo y rompería el resaltado.
    func copyAsXML() {
        guard let doc = try? JSONParser.parse(text) else {
            flash("Solo se puede convertir a XML un documento válido")
            return
        }
        let base = (name as NSString).deletingPathExtension
        let root = JSONXML.isValidName(base) ? base : JSONXML.defaultRootName
        copyToPasteboard(JSONXML.toXML(doc.value, root: root, indent: preferences.indent))
        flash("XML copiado al portapapeles")
    }

    func pasteFromXML() {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else {
            flash("El portapapeles no contiene texto")
            return
        }
        guard string.utf8.count <= Self.sizeLimit else {
            flash("El contenido del portapapeles supera los 10 MB")
            return
        }
        do {
            let value = try JSONXML.toJSON(string)
            assign(JSONFormatter.render(value, indent: preferences.indent), name: "desde XML")
            fileURL = nil
        } catch let error as JSONError {
            flash("No se pudo convertir el XML: \(error.message)")
        } catch {
            flash("No se pudo convertir el XML")
        }
    }

    func copyToPasteboard() {
        copyToPasteboard(text)
        flash("Copiado al portapapeles")
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Cursor y saltos

    func reportCaret(line: Int, column: Int) {
        caretLine = line
        caretColumn = column
    }

    func promptGoToLine() {
        // Se difiere al siguiente turno del run loop: mostrar el NSAlert (modal) y mutar
        // la petición de salto en el mismo stack de la acción del menú (⌘L viene de un Button
        // dentro de .commands) producía "Publishing changes from within view updates is not
        // allowed" y, con ello, un cuelgue con desconexión de ViewBridge. Diferirlo evita ambos.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Ir a línea"
            alert.addButton(withTitle: "Ir")
            alert.addButton(withTitle: "Cancelar")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            field.stringValue = "\(self.caretLine)"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn,
                let line = Int(field.stringValue.trimmingCharacters(in: .whitespaces))
            else { return }
            self.goTo(line: line)
        }
    }

    func goTo(line: Int) {
        request(.line(max(1, line)))
    }

    /// Trae a la vista el rango de un nodo. Lo pide la navegación, a través de `AppModel`.
    func reveal(utf16Start: Int, end: Int) {
        request(.utf16Range(start: utf16Start, end: end))
    }

    private func request(_ target: ScrollRequest.Target) {
        scrollRequestCount += 1
        scrollRequest = ScrollRequest(target: target, id: scrollRequestCount)
    }

    // MARK: - Entrada y salida

    func openFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        guard let contents = FileImport.read(url, flash: { [weak self] in self?.flash($0) }) else { return }
        assign(contents, name: url.lastPathComponent)
        fileURL = url
        lastSavedText = contents
        preferences.remember(url)
    }

    func paste() {
        guard let string = FileImport.pasteboard(flash: { [weak self] in self?.flash($0) }) else { return }
        assign(string, name: "portapapeles")
        fileURL = nil
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        writeToDisk(fileURL)
    }

    func saveAs() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeToDisk(url)
    }

    private func writeToDisk(_ rawURL: URL) {
        // NSSavePanel no siempre añade la extensión si el nombre no trae una (p. ej. al
        // guardar contenido pegado, sin nombre de archivo previo). Si no tiene ninguna, se
        // asume JSON; si el usuario puso una distinta a propósito, se respeta.
        let url = rawURL.pathExtension.isEmpty ? rawURL.appendingPathExtension("json") : rawURL
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            name = url.lastPathComponent
            lastSavedText = text
            preferences.remember(url)
            flash("Guardado en \(url.lastPathComponent)")
        } catch {
            flash("No se pudo guardar: \(error.localizedDescription)")
        }
    }

    private func assign(_ contents: String, name newName: String) {
        text = contents
        name = newName
        notice = nil
    }

    // MARK: - Cálculo

    private func revalidate() {
        notice = nil
        do {
            let doc = try JSONParser.parse(text)
            parse = Parse(root: doc.root, nodeCount: doc.nodeCount, error: nil)
        } catch {
            let detalle =
                error as? JSONError
                ?? JSONError("Error desconocido", line: 1, column: 1, offset: 0)
            // Se conserva el último árbol bueno; solo se marca el error.
            parse = Parse(root: parse.root, nodeCount: 0, error: detalle)
        }
        onParse?(parse)
    }

    private func flash(_ message: String) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.notice == message { self?.notice = nil }
        }
    }
}
