import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import JSONCore

struct ChangeRow: Identifiable {
    let id: Int
    let change: JSONChange
    var path: String { change.path }
    var kindLabel: String { change.kind.label }
    var before: String { ChangeRow.preview(change.before) }
    var after: String { ChangeRow.preview(change.after) }

    static func preview(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        let rendered = JSONFormatter.render(value, indent: nil)
        return rendered.count > 90 ? String(rendered.prefix(87)) + "…" : rendered
    }
}

struct AlignedRowItem: Identifiable {
    let id: Int
    let row: AlignedRow
}

struct AlignedScrollRequest: Equatable {
    let index: Int
    let id: Int
}

/// Los dos documentos de Comparar y todo lo que se hace con sus diferencias.
///
/// No sabe nada del editor: son otros dos textos, con otro parseo y otro formateo.
@MainActor
final class ComparisonModel: ObservableObject {
    enum Side: Hashable { case a, b }

    @Published var textA: String = Samples.a { didSet { recompare() } }
    @Published var textB: String = Samples.b { didSet { recompare() } }

    @Published var nameA: String = "pedido-4471.json"
    @Published var nameB: String = "pedido-4471.remoto.json"

    /// Resultado de comparar A con B, en un solo valor: antes eran siete propiedades publicadas
    /// que solo tienen sentido a la vez.
    struct Result {
        var changes: [ChangeRow] = []
        var rows: [AlignedRowItem] = []
        var error: String?
        var validA = true
        var validB = true
        /// Árboles de los documentos **ya formateados**, que son los que se ven en las dos
        /// columnas. Las posiciones de A y B valen para el texto original, no para el formateado.
        var prettyA: JSONNode?
        var prettyB: JSONNode?
    }

    @Published private(set) var result = Result()

    var changes: [ChangeRow] { result.changes }
    var alignedRows: [AlignedRowItem] { result.rows }
    var error: String? { result.error }
    var validA: Bool { result.validA }
    var validB: Bool { result.validB }

    /// Diferencia seleccionada en la tabla. Es el enganche entre la tabla y las dos columnas.
    @Published var selectedChangeID: Int? {
        didSet {
            guard selectedChangeID != oldValue else { return }
            // Diferido por lo mismo que el cursor: esto se escribe desde el binding de selección de
            // la tabla, que corre dentro de la actualización de la vista, y `revealSelectedChange`
            // toca otras propiedades publicadas.
            DispatchQueue.main.async { [weak self] in self?.revealSelectedChange() }
        }
    }

    /// Petición de scroll de la vista alineada; lleva identidad por lo mismo que
    /// `ScrollRequest` (ver `docs/specs/fase3-ir-a-linea-bucle.md`).
    @Published private(set) var alignedScroll: AlignedScrollRequest?
    private var alignedScrollCount = 0

    @Published var notice: String?

    /// Al seleccionar una diferencia hay que traer la vista de Diferencias al frente: si no, el
    /// usuario hace clic en una fila y el resaltado ocurre en una pantalla que no está viendo.
    /// La pantalla la manda `AppModel`, así que se le avisa por aquí.
    var onRevealChange: (() -> Void)?

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        recompare()
    }

    // MARK: - Acciones sobre un lado

    func text(in side: Side) -> String {
        side == .a ? textA : textB
    }

    func isValid(_ side: Side) -> Bool {
        side == .a ? validA : validB
    }

    func name(in side: Side) -> String {
        side == .a ? nameA : nameB
    }

    /// Formatear cada entrada desde su cabecera: pegar una respuesta minificada y no poder
    /// abrirla dejaba esta pantalla inservible para lo que más se usa, mirar arrays grandes.
    func format(_ side: Side) {
        guard let doc = try? JSONParser.parse(text(in: side)) else { return }
        assign(JSONFormatter.pretty(doc, indent: preferences.indent), name: name(in: side), to: side)
    }

    func openFile(into side: Side) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url, into: side)
    }

    func load(_ url: URL, into side: Side) {
        guard let contents = FileImport.read(url, flash: { [weak self] in self?.flash($0) }) else { return }
        assign(contents, name: url.lastPathComponent, to: side)
    }

    func paste(into side: Side) {
        guard let string = FileImport.pasteboard(flash: { [weak self] in self?.flash($0) }) else { return }
        assign(string, name: "portapapeles", to: side)
    }

    private func assign(_ contents: String, name: String, to side: Side) {
        switch side {
        case .a: textA = contents; nameA = name
        case .b: textB = contents; nameB = name
        }
        notice = nil
    }

    func swapSides() {
        let text = textA, name = nameA
        textA = textB; nameA = nameB
        textB = text; nameB = name
    }

    /// Vuelca las diferencias al portapapeles. El destino de esto es un ticket o un mensaje.
    func copyDiff(as format: JSONDiffExport.Format) {
        guard error == nil else {
            flash("No se puede exportar: alguno de los dos documentos no es válido")
            return
        }
        let text = JSONDiffExport.render(
            changes.map(\.change), format: format,
            nameA: nameA, nameB: nameB,
            ignoredKeys: preferences.ignoredKeys)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        flash("Diferencias copiadas como \(format.label.lowercased())")
    }

    // MARK: - Navegar las diferencias

    /// Fila de la vista alineada donde vive esa ruta.
    ///
    /// Se busca en el árbol del documento **formateado**, que es lo que se ve en las columnas, y
    /// de ahí sale la línea; luego la fila alineada que lleva ese número. Funciona porque las
    /// rutas de `JSONChange` y las de `JSONNode` son el mismo formato — se hizo así a propósito
    /// en la Fase 4. Si la diferencia es un añadido no existe en A, así que se prueba con B.
    func alignedRowIndex(forPath path: String) -> Int? {
        if let line = result.prettyA?.node(withPath: path)?.line,
            let index = alignedRows.firstIndex(where: { $0.row.leftNumber == line })
        {
            return index
        }
        if let line = result.prettyB?.node(withPath: path)?.line,
            let index = alignedRows.firstIndex(where: { $0.row.rightNumber == line })
        {
            return index
        }
        return nil
    }

    /// Fila de la vista alineada que toca resaltar. Se **deriva** de la diferencia seleccionada
    /// en vez de mantenerse en paralelo: era otra propiedad que había que acordarse de limpiar.
    var highlightedAlignedRow: Int? {
        guard let id = selectedChangeID,
            let row = changes.first(where: { $0.id == id })
        else { return nil }
        return alignedRowIndex(forPath: row.path)
    }

    private func revealSelectedChange() {
        guard selectedChangeID != nil else { return }
        onRevealChange?()
        if let index = highlightedAlignedRow {
            alignedScrollCount += 1
            alignedScroll = AlignedScrollRequest(index: index, id: alignedScrollCount)
        }
    }

    func nextDifference() { stepDifference(by: 1) }

    func previousDifference() { stepDifference(by: -1) }

    private func stepDifference(by delta: Int) {
        guard !changes.isEmpty else { return }
        guard let id = selectedChangeID,
            let current = changes.firstIndex(where: { $0.id == id })
        else {
            selectedChangeID = changes[delta > 0 ? 0 : changes.count - 1].id
            return
        }
        let next = (current + delta + changes.count) % changes.count
        selectedChangeID = changes[next].id
    }

    var differenceSummary: String {
        guard !changes.isEmpty else { return "" }
        guard let id = selectedChangeID,
            let index = changes.firstIndex(where: { $0.id == id })
        else { return "" }
        return "\(index + 1) de \(changes.count)"
    }

    // MARK: - Cálculo

    /// Rehace la comparación. La llama `AppModel` cuando cambia la sangría o la lista de claves
    /// ignoradas, que son suyas y no de aquí.
    func recompare() {
        notice = nil
        result = compare()
        // La diferencia que estuviera seleccionada puede haber dejado de existir.
        if let id = selectedChangeID, !result.changes.contains(where: { $0.id == id }) {
            selectedChangeID = nil
        }
    }

    /// Calcula la comparación entera. Devuelve el valor en vez de ir escribiendo propiedades:
    /// así no hay estados a medias mientras se construye.
    private func compare() -> Result {
        let a = try? JSONParser.parse(textA)
        let b = try? JSONParser.parse(textB)
        let validA = a != nil, validB = b != nil

        guard let a, let b else {
            let broken = validA ? "B" : "A"
            let detail = JSONParser.validate(validA ? textB : textA)?.description ?? "documento no válido"
            return Result(error: "\(broken): \(detail)", validA: validA, validB: validB)
        }

        let changes = JSONDiff.compare(a.value, b.value, options: preferences.diffOptions)
            .enumerated().map { ChangeRow(id: $0.offset, change: $0.element) }
        let leftText = JSONFormatter.pretty(a, indent: preferences.indent)
        let rightText = JSONFormatter.pretty(b, indent: preferences.indent)
        let rows = LineAlignment.align(
            leftText.components(separatedBy: "\n"),
            rightText.components(separatedBy: "\n")
        )
        .enumerated().map { AlignedRowItem(id: $0.offset, row: $0.element) }
        return Result(
            changes: changes, rows: rows, error: nil,
            validA: true, validB: true,
            prettyA: try? JSONParser.parse(leftText).root,
            prettyB: try? JSONParser.parse(rightText).root)
    }

    private func flash(_ message: String) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.notice == message { self?.notice = nil }
        }
    }
}
