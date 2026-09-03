import SwiftUI
// `@Published` y `ObservableObject` son de Combine. SwiftPM lo daba por importado de
// rebote vía SwiftUI; el modo Swift 6 de Xcode exige el import explícito.
import Combine
import AppKit
import JSONCore

/// Lo que queda cuando el documento, la comparación y la navegación viven cada uno en su clase:
/// **qué pantalla se ve, qué dice la barra de estado y las tres cosas que cruzan de un lado a
/// otro**. Era una sola clase de 860 líneas (Fase 8).
///
/// Coordina en vez de guardar: aquí no hay estado que también esté en otro sitio. Las tres cosas
/// que cruzan son el cursor (mueve el texto **y** el árbol), enseñar un nodo (lo decide el árbol,
/// lo hace el texto) y la sangría (la usan documento y comparación).
///
/// **SwiftUI no propaga los cambios de un `ObservableObject` anidado dentro de otro**: observar
/// `AppModel` no entera a una vista de que ha cambiado `document.text`. Por eso cada vista se
/// queda con los objetos que lee (ver el `init` de `ContentView`), y los elementos de menú son
/// vistas pequeñas con su propio `@ObservedObject`.
@MainActor
final class AppModel: ObservableObject {
    enum Mode: Hashable { case editor, compare }
    enum CompareMode: Hashable { case inputs, differences }

    @Published var mode: Mode = .editor
    @Published var compareMode: CompareMode = .differences

    let preferences: Preferences
    let document: DocumentModel
    let comparison: ComparisonModel
    let navigation: NavigationModel

    init(defaults: UserDefaults = .standard) {
        let preferences = Preferences(defaults: defaults)
        self.preferences = preferences
        document = DocumentModel(preferences: preferences)
        comparison = ComparisonModel(preferences: preferences)
        navigation = NavigationModel()

        // Las tres costuras, todas aquí y ninguna dentro de los modelos: cada uno sigue sin
        // saber que los otros existen.
        document.onParse = { [weak self] parse in
            self?.navigation.documentDidParse(root: parse.root)
        }
        navigation.onReveal = { [weak self] node in
            self?.document.reveal(utf16Start: node.start, end: node.end)
        }
        comparison.onRevealChange = { [weak self] in
            self?.compareMode = .differences
        }

        // La sangría y las claves ignoradas viven en `Preferences` porque las comparten dos
        // modelos; quien reacciona a que cambien es esto. Los avisos salen del `didSet` y no de
        // un `sink`: ver el porqué en `Preferences.onIndentChange`.
        preferences.onIndentChange = { [weak self] in
            guard let self else { return }
            if mode == .editor { document.reindent() }
            comparison.recompare()
        }
        preferences.onIgnoredKeysChange = { [weak self] in
            self?.comparison.recompare()
        }

        // El documento ya se parseó al construirse, antes de que existiera la navegación.
        navigation.documentDidParse(root: document.rootNode)
    }

    // MARK: - Lo que cruza

    /// El cursor mueve dos cosas: la posición que enseña la barra de estado y el nodo señalado
    /// en el árbol.
    func reportCaret(line: Int, column: Int, utf16Offset: Int) {
        document.reportCaret(line: line, column: column)
        navigation.sync(toUTF16: utf16Offset, line: line, in: document.rootNode)
    }

    func focusSearch() {
        preferences.showTree = true
        navigation.focusSearch()
    }

    /// Un solo par de atajos (⌘G / ⇧⌘G) que hace lo que toca según la pantalla: dos ⌘G distintos
    /// chocarían entre sí.
    func stepNext() {
        mode == .editor ? navigation.nextMatch() : comparison.nextDifference()
    }

    func stepPrevious() {
        mode == .editor ? navigation.previousMatch() : comparison.previousDifference()
    }

    var canStep: Bool {
        mode == .editor ? !navigation.search.isEmpty : !comparison.changes.isEmpty
    }

    // MARK: - Barra de estado

    /// Es lo único que mira a la vez al documento y a la comparación, y por eso se queda aquí.
    var statusText: String {
        switch mode {
        case .editor:
            if let notice = document.notice { return notice }
            if let error = document.error { return error.description }
            return "JSON válido"
        case .compare:
            if let notice = comparison.notice { return notice }
            if let error = comparison.error { return error }
            let n = comparison.changes.count
            return n == 0 ? "Documentos equivalentes" : "\(n) diferencia\(n == 1 ? "" : "s")"
        }
    }

    enum StatusLevel { case ok, warning, error }

    var statusLevel: StatusLevel {
        switch mode {
        case .editor: return document.error == nil ? .ok : .error
        case .compare:
            if comparison.error != nil { return .error }
            return comparison.changes.isEmpty ? .ok : .warning
        }
    }

    var byteCount: Int {
        mode == .editor
            ? document.text.utf8.count
            : comparison.textA.utf8.count + comparison.textB.utf8.count
    }

    static func humanSize(_ bytes: Int) -> String { FileImport.humanSize(bytes) }
}

enum Samples {
    static let a = """
        {
          "pedidoId": "4471-AC",
          "estado": "EN_PREPARACION",
          "creadoEn": "2026-08-31T14:02:11Z",
          "cliente": { "id": 90071992547409931, "nombre": "Marta Ferreira", "canal": "web" },
          "envio": { "metodo": "estandar", "prometido": "2026-09-04", "transportista": null },
          "lineas": [
            { "sku": "TL-0091", "descripcion": "Router dual-band", "cantidad": 1, "precio": 42.90 },
            { "sku": "TL-4420", "descripcion": "Cable Cat6 3m", "cantidad": 2, "precio": 7.50 }
          ],
          "totales": { "subtotal": 57.90, "impuestos": 12.16, "total": 70.06 }
        }
        """

    static let b = """
        {
          "pedidoId": "4471-AC",
          "estado": "ENVIADO",
          "creadoEn": "2026-08-31T14:02:11Z",
          "cliente": { "id": 90071992547409931, "nombre": "Marta Ferreira", "canal": "app" },
          "envio": { "metodo": "express", "prometido": "2026-09-02", "transportista": "SEUR", "seguimiento": "SE9928471X" },
          "lineas": [
            { "sku": "TL-0091", "descripcion": "Router dual-band", "cantidad": 1, "precio": 42.90 },
            { "sku": "TL-4420", "descripcion": "Cable Cat6 3m", "cantidad": 3, "precio": 7.50 }
          ],
          "totales": { "subtotal": 65.40, "impuestos": 13.73, "total": 79.13 }
        }
        """
}
