import SwiftUI
import JSONCore

struct ContentView: View {
    // Uno por cada objeto que esta vista lee. SwiftUI **no** propaga los cambios de un
    // `ObservableObject` anidado dentro de otro, así que observar solo `model` dejaría el
    // toolbar sin enterarse de que ha cambiado la sangría o el documento.
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var document: DocumentModel
    @ObservedObject var comparison: ComparisonModel

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
        self.document = model.document
        self.comparison = model.comparison
    }

    /// Enlace que publica el cambio en el **siguiente turno** del run loop.
    ///
    /// Un `Picker` del toolbar escribe su selección mientras SwiftUI está actualizando la barra,
    /// y escribir ahí en un `@Published` es "Publishing changes from within view updates is not
    /// allowed". Medido: con solo el selector de modo en el toolbar, cambiar de pantalla ocho
    /// veces producía 40 avisos.
    private func diferido<T: Equatable>(_ valor: T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(
            get: { valor },
            set: { nuevo in
                guard nuevo != valor else { return }
                DispatchQueue.main.async { set(nuevo) }
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
            case .editor: EditorScreen(model: model)
            case .compare: CompareScreen(model: model)
            }
            Divider()
            StatusBar(model: model)
        }
        .frame(minWidth: 940, minHeight: 620)
        .toolbar { toolbar }
        // En Comparar el título se quita: el selector de modo, dos centímetros a la
        // izquierda, ya dice "Comparar", y verlo dos veces seguidas era lo que peor se veía.
        .navigationTitle(model.mode == .editor ? document.name : "")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // El interruptor del panel va el primero de todos, que es donde lo pone macOS en
        // Finder, Notas o Mail. `sidebar.leading` es el icono estándar de esa acción.
        ToolbarItem(placement: .navigation) {
            // Solo en el editor: en Comparar no hay panel que abrir, y dejarlo deshabilitado
            // era ocupar sitio para no hacer nada.
            if model.mode == .editor {
                Button {
                    preferences.showTree.toggle()
                } label: {
                    Label("Estructura", systemImage: "sidebar.leading")
                }
                .labelStyle(.iconOnly)
                .help(preferences.showTree ? "Ocultar la estructura (⌃⌘S)" : "Mostrar la estructura (⌃⌘S)")
            }
        }

        ToolbarItem(placement: .navigation) {
            Picker("Modo", selection: diferido(model.mode, { model.mode = $0 })) {
                Text("Editor").tag(AppModel.Mode.editor)
                Text("Comparar").tag(AppModel.Mode.compare)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        }

        ToolbarItemGroup {
            if model.mode == .editor {
                Picker("Sangría", selection: diferido(preferences.indent, { preferences.indent = $0 })) {
                    ForEach(IndentStyle.options) { style in
                        Text(style.label).tag(style)
                    }
                }
                .frame(width: 130)

                ControlGroup {
                    Button {
                        document.openFile()
                    } label: {
                        Label("Importar…", systemImage: "square.and.arrow.down")
                    }
                    .help("Importar…")
                    // `clipboard` y no `doc.on.clipboard`: aquel son dos documentos
                    // superpuestos, igual que el de Copiar, y estaban a pocos píxeles uno de
                    // otro. La silueta del portapapeles solo se distingue de un vistazo.
                    Button {
                        document.paste()
                    } label: {
                        Label("Pegar", systemImage: "clipboard")
                    }
                    .help("Pegar")
                }
                .labelStyle(.iconOnly)

                // Formatear va con las otras transformaciones del documento y no suelto: un
                // botón solo en el toolbar sale **circular**, y era la única forma redonda y el
                // único color saturado de la ventana. macOS no deja ponerle etiqueta.
                ControlGroup {
                    Button {
                        document.format()
                    } label: {
                        Label("Formatear", systemImage: "wand.and.stars")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(!document.isValid)
                    .help("Formatear (⇧⌘F)")
                    Button {
                        document.minify()
                    } label: {
                        Label("Minificar", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .disabled(!document.isValid)
                    .help("Minificar")
                    Button {
                        document.sortKeys()
                    } label: {
                        Label("Ordenar claves", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(!document.isValid)
                    .help("Ordenar claves")
                    Button {
                        document.copyToPasteboard()
                    } label: {
                        Label("Copiar", systemImage: "doc.on.doc")
                    }
                    .help("Copiar")
                }
                .labelStyle(.iconOnly)
            } else {
                // El selector de sangría también aquí: si no, Formatear en las cabeceras de A y
                // B usaría una preferencia que solo se puede cambiar desde el editor.
                Picker("Sangría", selection: diferido(preferences.indent, { preferences.indent = $0 })) {
                    ForEach(IndentStyle.options) { style in
                        Text(style.label).tag(style)
                    }
                }
                .frame(width: 130)

                Picker("Vista", selection: diferido(model.compareMode, { model.compareMode = $0 })) {
                    Text("Entradas").tag(AppModel.CompareMode.inputs)
                    Text("Diferencias").tag(AppModel.CompareMode.differences)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                Menu {
                    ForEach(JSONDiffExport.Format.allCases) { format in
                        Button(format.label) { comparison.copyDiff(as: format) }
                    }
                } label: {
                    Label("Exportar diferencias", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .disabled(comparison.error != nil)
                .help("Copiar las diferencias al portapapeles")

                IgnoredKeysButton(preferences: preferences)

                Button {
                    comparison.swapSides()
                } label: {
                    Label("Intercambiar", systemImage: "arrow.left.arrow.right")
                }
                .labelStyle(.iconOnly)
                .help("Intercambiar A y B")
            }
        }
    }
}
