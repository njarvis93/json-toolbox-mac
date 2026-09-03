import SwiftUI
import AppKit
import JSONCore

/// Petición de salto a una línea.
///
/// Lleva identidad propia a propósito: `updateNSView` se ejecuta ante *cualquier* cambio del
/// modelo, así que con un simple `Int?` no hay forma de distinguir "hay un salto pendiente" de
/// "este salto ya lo atendí", y el salto se reaplicaba en cada render. Ver
/// `docs/specs/fase3-ir-a-linea-bucle.md`.
struct ScrollRequest: Equatable {
    enum Target: Equatable {
        case line(Int)
        /// Rango en unidades UTF-16, que es como vienen los rangos de `JSONNode`.
        case utf16Range(start: Int, end: Int)
    }

    let target: Target
    let id: Int
}

/// Posición del cursor tal y como la necesita la app: la línea y la columna para la barra de
/// estado, y el desplazamiento UTF-16 para localizar el nodo del árbol.
struct CaretPosition: Equatable {
    let line: Int
    let column: Int
    let utf16Offset: Int
}

/// Editor de texto con numeración de líneas y resaltado de sintaxis.
/// Envuelve NSTextView porque SwiftUI TextEditor no da ni regla lateral ni atributos.
struct JSONTextView: NSViewRepresentable {
    @Binding var text: String
    var errorLine: Int?
    var onCaretChange: ((CaretPosition) -> Void)?
    var scrollRequest: ScrollRequest?

    /// Por encima de este tamaño se deja el texto sin colorear: retokenizar en
    /// cada pulsación deja de ser gratis mucho antes del límite de 10 MB.
    static let highlightLimit = 512 * 1024

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        // Pila TextKit 1 explícita: la regla de líneas necesita NSLayoutManager.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.addTextContainer(container)

        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.allowsUndo = true
        tv.font = Theme.mono
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = []
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.contentView.postsBoundsChangedNotifications = true

        tv.string = text
        // .string no dispara el redimensionado automático que activa
        // isHorizontallyResizable/isVerticallyResizable (eso solo ocurre vía
        // didChangeText()): sin esto el frame se queda pequeño. Se calcula a mano
        // en vez de confiar solo en sizeToFit(), ya con el scroll view asignado.
        Self.fitToContent(tv)

        // La numeración de líneas NO se implementa con NSScrollView.verticalRulerView:
        // un NSRulerView asignado ahí, en este árbol de vistas hospedado por SwiftUI,
        // hace que el NSTextView vecino deje de componerse en pantalla en cuanto el ruler
        // dibuja algo — incluso un simple relleno de color sin tocar layout ni texto. El
        // contenido sigue existiendo (el layout manager lo tiene y cacheDisplay(in:to:) lo
        // pinta bien offscreen) pero la ventana real nunca lo muestra mientras el ruler esté
        // activo. Ver docs/specs/fase2-undo.md para el detalle de cómo se aisló. En vez de
        // pelear con eso, el gutter es una NSView normal, hermana del scroll, fuera de su
        // mecanismo de ruler.
        let gutter = LineNumberGutter(textView: tv)

        let root = NSView()
        gutter.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(gutter)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: root.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 46),
            scroll.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        context.coordinator.textView = tv
        context.coordinator.gutter = gutter
        context.coordinator.observeScrolling(scroll)
        context.coordinator.applyHighlighting()
        return root
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            context.coordinator.applyTextFromModel(text, to: tv)
        }
        if context.coordinator.gutter?.errorLine != errorLine {
            context.coordinator.gutter?.errorLine = errorLine
            context.coordinator.gutter?.needsDisplay = true
        }
        // Cada petición se atiende una sola vez, por su id, y sin escribir de vuelta en el
        // modelo: mutar estado publicado desde aquí es mutarlo dentro de una actualización de
        // vista, y era justo lo que colgaba la app al ir a una línea.
        if let request = scrollRequest, request.id != context.coordinator.lastScrollRequestID {
            context.coordinator.lastScrollRequestID = request.id
            context.coordinator.apply(request.target)
        }
    }

    /// Recalcula el frame del text view a partir del rectángulo realmente usado por el
    /// layout manager, sin depender de que `sizeToFit()` acierte por sí solo. Nunca lo deja
    /// más pequeño que el área visible del scroll, para que siga rellenando el fondo.
    static func fitToContent(_ tv: NSTextView) {
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let inset = tv.textContainerInset
        var size = NSSize(width: used.width + inset.width * 2, height: used.height + inset.height * 2)
        if let visible = tv.enclosingScrollView?.contentView.bounds.size {
            size.width = max(size.width, visible.width)
            size.height = max(size.height, visible.height)
        }
        tv.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    /// Rango de la línea `line` (1-based); si el documento tiene menos líneas, la última.
    private static func lineRange(_ line: Int, in ns: NSString) -> NSRange {
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        var current = 1
        var found: NSRange?
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) { _, substringRange, _, stop in
            if current == line {
                found = substringRange
                stop.pointee = true
            }
            current += 1
        }
        return found ?? ns.lineRange(for: NSRange(location: ns.length, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextView
        weak var textView: NSTextView?
        weak var gutter: LineNumberGutter?
        var lastScrollRequestID = 0
        private var observer: NSObjectProtocol?
        private var isSettingSelection = false
        private var isApplyingModelText = false

        init(_ parent: JSONTextView) { self.parent = parent }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func observeScrolling(_ scroll: NSScrollView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.gutter?.needsDisplay = true
            }
        }

        func textDidChange(_ notification: Notification) {
            // Si el texto lo acaba de poner el modelo, no hay nada que devolverle — y hacerlo
            // sería escribir en él desde dentro de una actualización de vista. Ver
            // `applyTextFromModel`.
            guard let tv = textView, !isApplyingModelText else { return }
            parent.text = tv.string
            JSONTextView.fitToContent(tv)
            applyHighlighting()
            reportCaret()
        }

        /// Mete en el editor un texto que viene del modelo.
        ///
        /// `didChangeText()` hace falta para que ⌘Z siga deshaciendo, pero llama al delegado de
        /// forma **síncrona**, y el delegado escribía en el modelo (`parent.text`, y el aviso de
        /// cursor). Llamado desde `updateNSView` eso es publicar cambios dentro de una
        /// actualización de vista: es lo que avisaba "Publishing changes from within view
        /// updates is not allowed" al formatear, minificar, ordenar claves, pegar, escapar o
        /// cambiar de pantalla — todas cambian el texto o recrean el editor.
        func applyTextFromModel(_ text: String, to tv: NSTextView) {
            let selection = tv.selectedRange()
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            isApplyingModelText = true
            if tv.shouldChangeText(in: full, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: full, with: text)
                tv.didChangeText()
            } else {
                tv.string = text
            }
            isApplyingModelText = false

            JSONTextView.fitToContent(tv)
            let safe = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
            setSelectionWithoutReporting(safe)
            applyHighlighting()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // También cuando el texto lo está poniendo el modelo: `replaceCharacters` mueve la
            // selección por su cuenta y dispara esto, y `reportCaret` escribe cinco propiedades
            // publicadas (cursor, cadena del cursor, nodo seleccionado). Faltaba esta guarda y
            // por eso el aviso seguía saliendo al formatear, pegar o cambiar de pantalla.
            guard !isSettingSelection, !isApplyingModelText else { return }
            reportCaret()
        }

        /// Mueve la selección sin avisar del cursor en el mismo turno.
        ///
        /// `setSelectedRange` llama al delegado de forma síncrona, y `reportCaret` escribe en
        /// el modelo. Llamado desde `updateNSView` eso es publicar cambios dentro de una
        /// actualización de vista: SwiftUI vuelve a renderizar en el acto y se entra en bucle.
        /// El aviso se difiere un turno del run loop, ya fuera de la actualización.
        func setSelectionWithoutReporting(_ range: NSRange) {
            guard let tv = textView else { return }
            isSettingSelection = true
            tv.setSelectedRange(range)
            isSettingSelection = false
            DispatchQueue.main.async { [weak self] in self?.reportCaret() }
        }

        func apply(_ target: ScrollRequest.Target) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let range: NSRange
            switch target {
            case .line(let line):
                range = JSONTextView.lineRange(line, in: ns)
            case .utf16Range(let start, let end):
                // Los rangos del árbol vienen del último parseo válido; si el texto ha
                // cambiado desde entonces pueden apuntar fuera. Se recortan en vez de romper.
                let from = min(max(0, start), ns.length)
                let to = min(max(from, end), ns.length)
                range = NSRange(location: from, length: to - from)
            }
            tv.scrollRangeToVisible(range)
            setSelectionWithoutReporting(range)
        }

        func applyHighlighting() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let string = tv.string
            let full = NSRange(location: 0, length: (string as NSString).length)
            storage.beginEditing()
            storage.setAttributes([.font: Theme.mono, .foregroundColor: NSColor.textColor], range: full)
            if string.utf8.count <= JSONTextView.highlightLimit {
                let dark = tv.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                for span in SyntaxScanner.spans(string) {
                    let range = NSRange(location: span.location, length: span.length)
                    guard NSMaxRange(range) <= full.length else { continue }
                    storage.addAttribute(
                        .foregroundColor,
                        value: Theme.color(for: span.role, dark: dark),
                        range: range)
                }
            }
            storage.endEditing()
            tv.typingAttributes = [.font: Theme.mono, .foregroundColor: NSColor.textColor]
            gutter?.needsDisplay = true
        }

        private func reportCaret() {
            guard let tv = textView, let handler = parent.onCaretChange else { return }
            let ns = tv.string as NSString
            let location = min(tv.selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = 1
            if lineRange.location > 0 {
                ns.enumerateSubstrings(
                    in: NSRange(location: 0, length: lineRange.location),
                    options: [.byLines, .substringNotRequired]
                ) { _, _, _, _ in
                    line += 1
                }
            }
            let prefix = ns.substring(
                with: NSRange(
                    location: lineRange.location,
                    length: location - lineRange.location))
            handler(CaretPosition(line: line, column: prefix.count + 1, utf16Offset: location))
        }
    }
}

/// Gutter con los números de línea, hermano del NSScrollView (no un NSRulerView — ver la
/// nota en JSONTextView.makeNSView). Marca en rojo la línea del error.
final class LineNumberGutter: NSView {
    var errorLine: Int?
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let layout = tv.layoutManager else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        // Sin retorno de línea forzado (container.widthTracksTextView = false, ancho
        // infinito): cada línea del texto es exactamente un fragmento, todos de la misma
        // altura (fuente monoespaciada fija), así que la posición Y de la línea N sale de
        // aritmética simple con `defaultLineHeight` en vez de preguntarle al layout manager
        // por el fragmento real en cada redibujado.
        let visible = tv.enclosingScrollView?.contentView.bounds ?? .zero
        let ns = tv.string as NSString
        let inset = tv.textContainerInset.height
        let lineHeight = layout.defaultLineHeight(for: tv.font ?? Theme.mono)
        guard lineHeight > 0 else { return }

        let normal: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let bad: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.systemRed,
        ]

        func draw(_ number: Int, atLineTop lineTop: CGFloat) {
            let label = "\(number)" as NSString
            let attributes = number == errorLine ? bad : normal
            let size = label.size(withAttributes: attributes)
            let y = lineTop + inset - visible.minY + (lineHeight - size.height) / 2
            guard y > -lineHeight, y < bounds.height + lineHeight else { return }
            label.draw(at: NSPoint(x: bounds.width - size.width - 7, y: y), withAttributes: attributes)
        }

        let totalLines = max(1, ns.components(separatedBy: "\n").count)
        let firstVisible = max(1, Int((visible.minY - inset) / lineHeight) + 1)
        let lastVisible = min(totalLines, Int((visible.minY + visible.height - inset) / lineHeight) + 1)
        guard firstVisible <= lastVisible else { return }
        for number in firstVisible...lastVisible {
            draw(number, atLineTop: CGFloat(number - 1) * lineHeight)
        }
    }
}
