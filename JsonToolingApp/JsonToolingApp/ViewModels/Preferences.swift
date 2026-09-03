import SwiftUI
import Combine
import JSONCore

/// Todo lo que sobrevive al relanzamiento, en un solo sitio.
///
/// Existe por la sangría: la usan **documento y comparación** a la vez (formatear el editor, y
/// formatear las dos columnas antes de alinearlas). Dejarla en cualquiera de los dos obligaría al
/// otro a llevar una copia sincronizada a mano, que es justo lo que quitó el primer paso de la
/// Fase 8. Compartir una referencia no tiene ese problema.
///
/// La regla para saber qué va aquí es simple: si se lee de `UserDefaults` al arrancar, vive aquí.
@MainActor
final class Preferences: ObservableObject {
    @Published var indent: IndentStyle = .spaces(2) {
        didSet {
            guard !isLoading, indent != oldValue else { return }
            defaults.set(indent.id, forKey: Self.indentKey)
            onIndentChange?()
        }
    }

    @Published var showTree: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(showTree, forKey: Self.showTreeKey)
        }
    }

    /// Claves que no se informan al comparar, tal y como las escribe el usuario.
    @Published var ignoredKeysText: String = "" {
        didSet {
            guard !isLoading else { return }
            defaults.set(ignoredKeysText, forKey: Self.ignoredKeysKey)
            onIgnoredKeysChange?()
        }
    }

    var ignoredKeys: Set<String> { DiffOptions.parseIgnoredKeys(ignoredKeysText) }

    /// Quién reacciona a que estas dos cambien es `AppModel`: reformatear el documento y rehacer
    /// la comparación son cosas de otros modelos.
    ///
    /// Es un aviso desde el `didSet` y **no** un `sink` sobre el `@Published`: `@Published`
    /// publica en `willSet`, así que un suscriptor de Combine leería la sangría **vieja** justo
    /// cuando va a reformatear con ella. Aquí el valor ya está puesto.
    var onIndentChange: (() -> Void)?
    var onIgnoredKeysChange: (() -> Void)?

    var diffOptions: DiffOptions { DiffOptions(ignoredKeys: ignoredKeys) }

    @Published private(set) var recentDocuments: [URL] = []

    /// Dónde se lee y se escribe. Se inyecta para que los tests usen un suite propio: si no,
    /// ejecutarlos pisaría la sangría, las claves ignoradas y los recientes del usuario real.
    private let defaults: UserDefaults

    /// Se está cargando lo persistido dentro de `init`. Los `didSet` **sí** corren ahí —las
    /// propiedades ya están todas inicializadas cuando el cuerpo del init les asigna—, así que
    /// sin esto leer una preferencia la volvería a escribir, y cargar una sangría guardada
    /// dispararía un reformateo del documento antes de que el usuario hiciera nada.
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        indent = Self.loadIndent(defaults)
        showTree = defaults.object(forKey: Self.showTreeKey) as? Bool ?? true
        ignoredKeysText = defaults.string(forKey: Self.ignoredKeysKey) ?? ""
        recentDocuments = (defaults.stringArray(forKey: Self.recentDocumentsKey) ?? [])
            .map(URL.init(fileURLWithPath:))
        isLoading = false
    }

    // MARK: - Documentos recientes

    private static let recentDocumentsLimit = 8

    func remember(_ url: URL) {
        recentDocuments.removeAll { $0.path == url.path }
        recentDocuments.insert(url, at: 0)
        if recentDocuments.count > Self.recentDocumentsLimit {
            recentDocuments.removeLast(recentDocuments.count - Self.recentDocumentsLimit)
        }
        persistRecentDocuments()
    }

    func clearRecentDocuments() {
        recentDocuments = []
        persistRecentDocuments()
    }

    private func persistRecentDocuments() {
        defaults.set(recentDocuments.map(\.path), forKey: Self.recentDocumentsKey)
    }

    // MARK: - Claves

    private static let indentKey = "indentStyle"
    private static let showTreeKey = "showTree"
    private static let ignoredKeysKey = "ignoredKeys"
    private static let recentDocumentsKey = "recentDocuments"

    private static func loadIndent(_ defaults: UserDefaults) -> IndentStyle {
        guard let id = defaults.string(forKey: indentKey) else { return .spaces(2) }
        return IndentStyle.options.first { $0.id == id } ?? .spaces(2)
    }
}
