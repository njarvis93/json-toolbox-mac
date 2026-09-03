import SwiftUI
import JSONCore

/// Panel lateral con la estructura del documento.
///
/// Las filas se aplanan en `AppModel.treeRows` en vez de usar `OutlineGroup`: el despliegue
/// tiene que poder abrirse desde fuera cuando el cursor se mueve por el texto, y el estado
/// interno de `OutlineGroup` no se deja tocar.
struct TreePanel: View {
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var document: DocumentModel
    @FocusState private var searchFocused: Bool

    init(model: AppModel) {
        self.navigation = model.navigation
        self.document = model.document
    }

    /// El árbol es del documento; la navegación solo decide qué se ve de él.
    private var visibleRows: [TreeRow] { navigation.rows(of: document.rootNode) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            searchBar
            if navigation.isSearching { matchBar }
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            if document.rootNode == nil {
                placeholder("Sin estructura que mostrar")
            } else if visibleRows.isEmpty {
                // Un panel del todo vacío parece roto; el recuento de la barra no basta.
                if let detail = navigation.searchErrorDetail {
                    placeholder(detail)
                } else if navigation.looksLikePathQuery {
                    pathHint
                } else {
                    placeholder("Nada que coincida con \u{201C}\(navigation.searchQuery)\u{201D}")
                }
            } else {
                rows
            }
        }
        .background(VisualEffectBackground())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Estructura")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if document.isTreeStale {
                Text("desfasado")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("El documento no es válido ahora mismo: el árbol es del último parseo correcto")
            }
            Spacer(minLength: 4)
            // `rectangle.compress/expand.vertical` y no las flechas diagonales: aquellas son
            // el icono de "Minificar" del toolbar, y el mismo dibujo no puede significar dos
            // cosas distintas en la misma ventana. Además, a este tamaño las dos diagonales
            // opuestas no se distinguían.
            Button {
                navigation.collapseAll(of: document.rootNode)
            } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .help("Plegar todo")
            Button {
                navigation.expandAll(of: document.rootNode)
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .help("Desplegar todo")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField(navigation.searchScope.placeholder, text: $navigation.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($searchFocused)
                .onSubmit { navigation.nextMatch() }
            if navigation.isSearching {
                Button {
                    navigation.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Borrar la búsqueda")
            }
        }
        // Con `.textFieldStyle(.plain)` y sin fondo, el campo parecía una etiqueta con una
        // lupa al lado. La cápsula es lo que lo hace reconocible como sitio donde escribir.
        .padding(.horizontal, 7)
        .frame(height: 22)
        // El `TextField` con estilo `.plain` solo acepta el clic sobre su propio marco: la
        // lupa, el relleno y los milímetros de arriba y abajo de la cápsula no daban el foco,
        // y al teclear el texto no iba al campo. La cápsula entera lo enfoca.
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .onChange(of: navigation.focusSearchRequest) { searchFocused = true }
    }

    private var matchBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $navigation.searchScope) {
                ForEach(JSONSearch.Scope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .labelsHidden()
            .frame(width: 92)

            Text(navigation.searchSummary)
                .font(.system(size: 10))
                .foregroundStyle(summaryColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(navigation.searchErrorDetail ?? "")

            Spacer(minLength: 0)

            Button {
                navigation.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Coincidencia anterior (⇧⌘G)")
            Button {
                navigation.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Coincidencia siguiente (⌘G)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 10))
        .disabled(navigation.search.isEmpty)
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    /// Lo escrito parece una ruta pero el ámbito busca texto: decirlo, y ofrecer el cambio.
    private var pathHint: some View {
        VStack(spacing: 9) {
            Spacer()
            Text(
                "Esto parece una consulta de ruta, y el ámbito \u{201C}\(navigation.searchScope.label)\u{201D} busca texto."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            Button("Buscar como ruta") { navigation.searchAsPath() }
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryColor: Color {
        if navigation.hasSearchError { return .orange }
        return navigation.search.isEmpty ? .secondary : .primary
    }

    private func placeholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            List(visibleRows) { row in
                TreeRowView(
                    row: row,
                    isSelected: navigation.selectedPath == row.node.path,
                    isExpanded: navigation.isExpanded(row.node.path),
                    onToggle: { navigation.toggleExpanded(row.node) },
                    onSelect: { navigation.reveal(row.node) }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .id(row.node.path)
            }
            .listStyle(.plain)
            // Sin esto el List pinta su propio fondo opaco y tapa el material del panel.
            .scrollContentBackground(.hidden)
            .onChange(of: navigation.selectedPath) { _, path in
                guard let path else { return }
                withAnimation(.none) { proxy.scrollTo(path, anchor: .center) }
            }
        }
    }
}

private struct TreeRowView: View {
    let row: TreeRow
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if row.node.isContainer {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onToggle)
                } else {
                    Color.clear
                }
            }
            .frame(width: 10, height: 10)

            // Los dos puntos separan clave de valor; sin ellos la fila se leía apelotonada
            // (`pedidoId "4471-AC"`). Los elementos de array no llevan: su etiqueta es el
            // índice, y `0: { … }` no aporta nada.
            Text(row.node.key == nil ? row.node.label : row.node.label + ":")
                .foregroundStyle(Theme.keyColor)
                .fontWeight(row.isMatch ? .bold : .regular)
            Text(row.node.summary)
                .foregroundStyle(Theme.color(for: row.node.kind))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.leading, CGFloat(row.depth) * 12 + 10)
        .padding(.trailing, 10)
        .frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // La selección va con margen y esquinas redondeadas, como en las barras laterales de
        // macOS, en vez de llegar a sangre hasta los dos bordes del panel.
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(background)
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// La fila seleccionada manda sobre la coincidencia: si no, saltar de una coincidencia a
    /// otra no se vería, porque todas estarían pintadas igual.
    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        return row.isMatch ? Color.yellow.opacity(0.12) : Color.clear
    }
}
