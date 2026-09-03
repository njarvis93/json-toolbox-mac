import SwiftUI
import Combine
import JSONCore

struct TreeRow: Identifiable {
    let node: JSONNode
    let depth: Int
    /// La fila es una coincidencia de la búsqueda, y no solo un ancestro que se enseña para
    /// no perder el contexto.
    let isMatch: Bool
    var id: String { node.path }
}

/// Moverse por la estructura: qué está desplegado, qué se está buscando y dónde está el cursor.
///
/// **No guarda el árbol.** El árbol es del documento; aquí se recibe como parámetro en cada
/// operación. Así no hay dos copias que puedan quedar desincronizadas, que es de lo que iba
/// entero el primer paso de la Fase 8.
@MainActor
final class NavigationModel: ObservableObject {
    /// Lo que el usuario ha desplegado o plegado **a mano**. Lo que no esté aquí sigue el valor
    /// por defecto, que lo decide `isExpanded`.
    ///
    /// Antes esto era un `Set` de rutas desplegadas que la búsqueda iba rellenando para abrir la
    /// rama de cada coincidencia. Mutar ahí estado publicado que la lista está leyendo hacía
    /// saltar "Application performed a reentrant operation in its NSTableView delegate" en cada
    /// tecla. Ahora el despliegue por búsqueda se **deriva** en vez de sincronizarse.
    @Published var expansionOverrides: [String: Bool] = [:]

    /// Ancestros del nodo donde está el cursor. Se guarda la cadena en vez de ir abriendo ramas
    /// a mano, por lo mismo: `sync` corre desde el aviso de cursor del editor, que puede caer
    /// dentro de una actualización de vista.
    @Published private(set) var caretChain: Set<String> = []
    @Published private(set) var selectedPath: String?

    @Published var searchQuery: String = "" { didSet { scheduleSearch() } }
    @Published var searchScope: JSONSearch.Scope = .all { didSet { scheduleSearch() } }
    @Published private(set) var search: JSONSearch.Result = .none
    /// Coincidencia actual, 1-based. 0 mientras no se ha saltado a ninguna.
    @Published private(set) var currentMatch: Int = 0
    /// Contador que pide el foco para el campo de búsqueda. Lleva identidad por lo mismo que
    /// `ScrollRequest`: la vista tiene que poder distinguir una petición nueva de una ya vista.
    @Published private(set) var focusSearchRequest: Int = 0

    /// Árbol sobre el que se busca. Lo pone `AppModel` en cada parseo del documento; no se
    /// publica porque nadie lo pinta desde aquí.
    private var root: JSONNode?

    /// Llevar el texto hasta un nodo es cosa del documento, no de la navegación.
    var onReveal: ((JSONNode) -> Void)?

    // MARK: - Filas

    /// Filas visibles del árbol, ya aplanadas según lo desplegado.
    ///
    /// Se aplana a mano en vez de usar `OutlineGroup` porque el despliegue tiene que poder
    /// abrirse **desde fuera**: al mover el cursor por el texto hay que desplegar la rama que
    /// lleva hasta ese nodo, y el estado interno de `OutlineGroup` no se deja tocar.
    func rows(of root: JSONNode?) -> [TreeRow] {
        guard let root else { return [] }
        var rows: [TreeRow] = []

        // Buscando, el árbol se filtra a las coincidencias y sus ancestros, y se despliega
        // solo: tener que abrir a mano la rama que lleva a lo que acabas de buscar no tiene
        // ningún sentido.
        if isSearching {
            func walk(_ node: JSONNode, depth: Int) {
                guard search.visiblePaths.contains(node.path) else { return }
                rows.append(
                    TreeRow(
                        node: node, depth: depth,
                        isMatch: search.matches.contains { $0.path == node.path }))
                // Se sigue respetando lo desplegado. Ignorarlo dejaba filas desplegadas con el
                // triángulo apuntando a "plegado", y plegar durante una búsqueda no hacía nada.
                guard node.isContainer, isExpanded(node.path) else { return }
                for child in node.children { walk(child, depth: depth + 1) }
            }
            walk(root, depth: 0)
            return rows
        }

        func walk(_ node: JSONNode, depth: Int) {
            rows.append(TreeRow(node: node, depth: depth, isMatch: false))
            guard node.isContainer, isExpanded(node.path) else { return }
            for child in node.children { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return rows
    }

    /// Si un contenedor se ve abierto. Sin decisión del usuario, la raíz está abierta y, durante
    /// una búsqueda, también la rama que lleva a cada coincidencia.
    func isExpanded(_ path: String) -> Bool {
        // Lo que el usuario haya decidido a mano manda sobre todo lo demás.
        if let explicit = expansionOverrides[path] { return explicit }
        if caretChain.contains(path) { return true }
        return isSearching ? search.visiblePaths.contains(path) : path == "$"
    }

    func toggleExpanded(_ node: JSONNode) {
        guard node.isContainer else { return }
        expansionOverrides[node.path] = !isExpanded(node.path)
    }

    func expandAll(of root: JSONNode?) {
        guard let root else { return }
        var all: [String: Bool] = [:]
        root.forEachNode { if $0.isContainer { all[$0.path] = true } }
        expansionOverrides = all
    }

    func collapseAll(of root: JSONNode?) {
        guard let root else { return }
        var all: [String: Bool] = [:]
        root.forEachNode { if $0.isContainer { all[$0.path] = false } }
        all["$"] = true
        expansionOverrides = all
    }

    // MARK: - Sincronización con el texto

    /// Del árbol al texto: selecciona el valor y pide traerlo a la vista.
    func reveal(_ node: JSONNode) {
        selectedPath = node.path
        onReveal?(node)
    }

    /// Del texto al árbol: marca el nodo donde está el cursor y despliega lo que haga falta
    /// para que se vea.
    func sync(toUTF16 offset: Int, line: Int, in root: JSONNode?) {
        guard let root else { return }
        let chain = root.chain(atUTF16: offset, line: line)
        guard let deepest = chain.last else { return }
        // Los contenedores intermedios se ven abiertos; el propio nodo no, para no abrir de
        // golpe un array enorme solo por pasar el cursor por encima.
        let ancestors = Set(chain.dropLast().map(\.path))
        if caretChain != ancestors { caretChain = ancestors }
        if selectedPath != deepest.path { selectedPath = deepest.path }
    }

    /// El documento se ha vuelto a parsear: se rehace la búsqueda sobre el árbol nuevo y se
    /// suelta la selección si esa ruta ya no existe.
    func documentDidParse(root newRoot: JSONNode?) {
        root = newRoot
        if let selectedPath, newRoot?.node(withPath: selectedPath) == nil {
            self.selectedPath = nil
        }
        refreshSearch()
    }

    // MARK: - Búsqueda

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Texto del recuento, que es lo que pedía el plan ("con recuento de coincidencias").
    var searchSummary: String {
        guard isSearching else { return "" }
        // El detalle completo va al cuerpo del panel (`searchErrorDetail`): aquí no cabe, y
        // truncado a "Comparación no re…" no le sirve a nadie.
        if search.error != nil { return "Consulta no válida" }
        if search.isEmpty { return "Sin coincidencias" }
        let total = "\(search.count) coincidencia\(search.count == 1 ? "" : "s")"
        return currentMatch > 0 ? "\(currentMatch) de \(search.count)" : total
    }

    /// La consulta está mal escrita (solo puede pasar con el ámbito de ruta).
    var hasSearchError: Bool { search.error != nil }

    /// Mensaje completo del error, con su columna dentro de la consulta.
    var searchErrorDetail: String? { search.error }

    /// Se ha escrito lo que parece una consulta de ruta con un ámbito que busca texto.
    ///
    /// Pasa constantemente: escribes `$..precio`, el ámbito está en "Todo" —que es el de
    /// salida—, se busca como texto literal, no aparece por ningún lado y la app se limita a
    /// decir "Sin coincidencias". No se cambia el ámbito solo: buscar un `$` de verdad (en
    /// precios, por ejemplo) es legítimo. Se avisa y se ofrece el cambio en un clic.
    var looksLikePathQuery: Bool {
        searchScope != .path && isSearching && search.isEmpty
            && searchQuery.trimmingCharacters(in: .whitespaces).hasPrefix("$")
    }

    func searchAsPath() {
        searchScope = .path
    }

    func focusSearch() {
        focusSearchRequest += 1
    }

    func clearSearch() {
        searchQuery = ""
    }

    func nextMatch() { step(by: 1) }

    func previousMatch() { step(by: -1) }

    private func step(by delta: Int) {
        guard !search.isEmpty else { return }
        // Al saltar por primera vez se empieza por la primera coincidencia, no por la segunda.
        let next =
            currentMatch == 0
            ? (delta > 0 ? 1 : search.count)
            : (currentMatch - 1 + delta + search.count) % search.count + 1
        currentMatch = next
        reveal(search.matches[next - 1])
    }

    private var pendingSearch: DispatchWorkItem?

    /// Recalcula la búsqueda en el **siguiente turno** del run loop, no en el mismo.
    ///
    /// Escribiendo en el campo, la primera tecla cambia el árbol entero de golpe —de la vista
    /// normal a la filtrada— en la misma pasada en que el campo escribe en su binding, y AppKit
    /// avisaba: "Application performed a reentrant operation in its NSTableView delegate", que
    /// además promete convertirse en un assert. Separarlo en dos turnos lo quita, y de paso
    /// agrupa las teclas rápidas en un solo recálculo.
    private func scheduleSearch() {
        pendingSearch?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshSearch() }
        pendingSearch = work
        DispatchQueue.main.async(execute: work)
    }

    private func refreshSearch() {
        guard let root, isSearching else {
            search = .none
            currentMatch = 0
            return
        }
        search = JSONSearch.find(searchQuery, in: root, scope: searchScope)
        currentMatch = 0
    }
}
