import SwiftUI
import UniformTypeIdentifiers
import JSONCore

struct CompareScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject var comparison: ComparisonModel

    init(model: AppModel) {
        self.model = model
        self.comparison = model.comparison
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PaneHeader(
                    label: "A", name: comparison.nameA,
                    valid: comparison.validA,
                    onImport: { comparison.openFile(into: .a) },
                    onPaste: { comparison.paste(into: .a) },
                    onFormat: { comparison.format(.a) })
                // No usar Divider() aquí: entre dos vistas custom cada una con su propio
                // .frame(height:), SwiftUI calcula mal la altura de este HStack (se midió
                // 200.5pt en vez de 26pt — el hueco en blanco que rodeaba esta fila en
                // Comparar). No basta con cambiar Divider() por otra forma: cualquier hijo
                // sin alto explícito (Divider y hasta un Rectangle sin `height:`) es
                // "greedy" y produce la misma altura inflada. Hay que fijar el alto a mano,
                // igual que PaneHeader.
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 26)
                PaneHeader(
                    label: "B", name: comparison.nameB,
                    valid: comparison.validB,
                    onImport: { comparison.openFile(into: .b) },
                    onPaste: { comparison.paste(into: .b) },
                    onFormat: { comparison.format(.b) })
            }
            Divider()

            // VSplitView y no un alto fijo: con 190 pt de tabla se veían cinco filas y no había
            // forma de agrandarla para leer una lista larga de diferencias. El reparto inicial
            // sale a medias — `idealHeight` lo ignora y `layoutPriority` se va al otro extremo
            // (deja la tabla en dos filas)—, y a medias es lo que mejor se ve de los tres.
            VSplitView {
                panes
                ChangeList(comparison: comparison, ignoredKeys: model.preferences.ignoredKeys)
                    .frame(minHeight: 120, idealHeight: 190, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var panes: some View {
        Group {
            if model.compareMode == .inputs || comparison.error != nil {
                HStack(spacing: 0) {
                    JSONTextView(text: $comparison.textA, errorLine: nil, onCaretChange: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrop(of: [.fileURL], isTargeted: nil) {
                            DropReceiver.handle($0) { comparison.load($0, into: .a) }
                        }
                    Divider()
                    JSONTextView(text: $comparison.textB, errorLine: nil, onCaretChange: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrop(of: [.fileURL], isTargeted: nil) {
                            DropReceiver.handle($0) { comparison.load($0, into: .b) }
                        }
                }
            } else {
                AlignedDiffView(
                    rows: comparison.alignedRows,
                    highlighted: comparison.highlightedAlignedRow,
                    scroll: comparison.alignedScroll)
            }
        }
        .frame(minHeight: 200, idealHeight: 520, maxHeight: .infinity)
    }
}

private struct PaneHeader: View {
    let label: String
    let name: String
    let valid: Bool
    let onImport: () -> Void
    let onPaste: () -> Void
    let onFormat: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold))
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            // Los mismos iconos que en el toolbar del editor. Eran enlaces de texto azules,
            // que es otro idioma distinto para las mismas dos acciones.
            Button(action: onImport) { Image(systemName: "square.and.arrow.down") }
                .help("Importar…")
            Button(action: onPaste) { Image(systemName: "clipboard") }
                .help("Pegar")
            Button(action: onFormat) { Image(systemName: "wand.and.stars") }
                .disabled(!valid)
                .help(valid ? "Formatear" : "No se puede formatear un documento inválido")
            Spacer(minLength: 6)
            Text(valid ? "válido" : "no válido")
                .font(.system(size: 11))
                .foregroundStyle(valid ? Color.green : Color.red)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4))
    }
}

/// Vista lado a lado. Un único ScrollView vertical contiene las dos columnas,
/// así el desplazamiento va sincronizado por construcción.
private struct AlignedDiffView: View {
    let rows: [AlignedRowItem]
    var highlighted: Int?
    var scroll: AlignedScrollRequest?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: scroll) { _, request in
                    guard let request else { return }
                    proxy.scrollTo(request.index, anchor: .center)
                }
                // Al hacer clic en una fila desde "Entradas" esta vista todavía no existe
                // cuando se pide el scroll, así que `onChange` no llega a dispararse: hay que
                // atender también la petición que ya venía puesta al aparecer.
                .onAppear {
                    guard let scroll else { return }
                    DispatchQueue.main.async { proxy.scrollTo(scroll.index, anchor: .center) }
                }
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { item in
                    HStack(spacing: 0) {
                        DiffCell(
                            number: item.row.leftNumber,
                            text: item.row.left,
                            highlighted: item.row.kind == .removed,
                            selected: item.id == highlighted,
                            tint: .red)
                        // Mismo caso que en PaneHeader: Divider() entre dos vistas custom
                        // con .frame(height:) propio infla la altura de la fila. Rectángulo
                        // con alto fijo en vez de Divider().
                        Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 18)
                        DiffCell(
                            number: item.row.rightNumber,
                            text: item.row.right,
                            highlighted: item.row.kind == .added,
                            selected: item.id == highlighted,
                            tint: .green)
                    }
                    .id(item.id)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DiffCell: View {
    let number: Int?
    let text: String?
    let highlighted: Bool
    let selected: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number.map(String.init) ?? "")
                .frame(width: 34, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(text ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text ?? "")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced).monospacedDigit())
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(background)
    }

    private var background: Color {
        // La fila elegida en la tabla manda sobre el color de añadido/eliminado: si no, no se
        // distinguiría de las otras nueve diferencias de la pantalla.
        if selected { return Color.accentColor.opacity(0.30) }
        if highlighted { return tint.opacity(0.15) }
        return text == nil ? Color.secondary.opacity(0.06) : .clear
    }
}

private struct ChangeList: View {
    @ObservedObject var comparison: ComparisonModel
    /// Se pasan en vez de leerlas del modelo: la lista solo las usa para decirlo en el resumen,
    /// y así no tiene que observar también las preferencias.
    let ignoredKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if !comparison.differenceSummary.isEmpty {
                    Text(comparison.differenceSummary)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 24)

            if let error = comparison.error {
                centered(error)
            } else if comparison.changes.isEmpty {
                centered("Los dos documentos son equivalentes.")
            } else {
                ScrollViewReader { proxy in
                    table
                        .onChange(of: comparison.selectedChangeID) { _, id in
                            guard let id else { return }
                            proxy.scrollTo(id, anchor: .center)
                        }
                }
            }
        }
        .background(.quaternary.opacity(0.25))
    }

    private var table: some View {
        Group {
            Table(comparison.changes, selection: $comparison.selectedChangeID) {
                TableColumn("Ruta", value: \.path)
                TableColumn("Cambio") { row in
                    Text(row.kindLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.color(for: row.change.kind).opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.color(for: row.change.kind))
                }
                .width(90)
                TableColumn("A", value: \.before)
                TableColumn("B", value: \.after)
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }

    private var summary: String {
        if comparison.error != nil { return "Sin comparación" }
        if comparison.changes.isEmpty {
            let ignoradas = ignoredKeys.count
            return ignoradas == 0
                ? "Sin diferencias estructurales"
                : "Sin diferencias estructurales · ignorando \(ignoradas) clave\(ignoradas == 1 ? "" : "s")"
        }
        func count(_ kind: JSONChange.Kind) -> Int {
            comparison.changes.filter { $0.change.kind == kind }.count
        }
        var partes = [JSONChange.Kind.added, .removed, .modified].map { $0.counted(count($0)) }
        let moved = count(.moved)
        if moved > 0 { partes.append(JSONChange.Kind.moved.counted(moved)) }
        let n = comparison.changes.count
        var linea = "\(n) diferencia\(n == 1 ? "" : "s") · " + partes.joined(separator: ", ")
        // Que se vea siempre: una comparación que esconde diferencias tiene que decirlo.
        let ignoradas = ignoredKeys.count
        if ignoradas > 0 {
            linea += " · ignorando \(ignoradas) clave\(ignoradas == 1 ? "" : "s")"
        }
        return linea
    }

    private func centered(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
