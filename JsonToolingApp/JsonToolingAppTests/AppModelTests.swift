import XCTest
import JSONCore
@testable import JsonTooling

/// Tests de la **capa de app**, que hasta ahora eran cero: los 168 que había son todos de
/// `JSONCore`. Son la red que pide la Fase 8 antes de partir `AppModel` en tres — mover estado
/// entre objetos sin nada debajo es exactamente cómo se rompen cosas que nadie nota hasta usarlas.
///
/// Todo esto corre en el hilo principal porque los modelos son `@MainActor`, y cada caso usa su
/// propio `UserDefaults`: los tests no pueden pisar la sangría ni los recientes del usuario real.
///
/// Se prueba a través de `AppModel` y de sus cuatro objetos (`preferences`, `document`,
/// `comparison`, `navigation`) en vez de construir cada uno suelto: lo que hay que fijar no es
/// solo lo que hace cada pieza, sino que las costuras entre ellas sigan enganchadas.
@MainActor
final class AppModelTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "JsonToolingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeModel() -> AppModel { AppModel(defaults: defaults) }

    /// Filas visibles del árbol. La navegación no guarda el árbol —es del documento—, así que
    /// se le pasa en cada consulta.
    private func filas(_ model: AppModel) -> [TreeRow] {
        model.navigation.rows(of: model.document.rootNode)
    }

    /// Deja correr lo que `AppModel` difiere al siguiente turno del run loop a propósito: la
    /// búsqueda (`scheduleSearch`) y el resaltado de la diferencia seleccionada
    /// (`revealSelectedChange`). Los dos se difieren para no publicar cambios dentro de una
    /// actualización de vista; desde un test hay que esperarlos igual.
    private func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    // MARK: - Acciones del editor

    func testFormatearUsaLaSangriaElegida() {
        let model = makeModel()
        model.document.text = #"{"a":{"b":1}}"#
        model.preferences.indent = .spaces(4)
        model.document.text = #"{"a":{"b":1}}"#  // `indent` ya reindenta sola; se parte de crudo aposta.
        model.document.format()
        XCTAssertEqual(model.document.text, "{\n    \"a\": {\n        \"b\": 1\n    }\n}")
    }

    func testCambiarLaSangriaReindentaElDocumentoAlMomento() {
        let model = makeModel()
        model.document.text = "{\n  \"a\": 1\n}"
        model.preferences.indent = .tab
        // El bug que motivó esto: el selector solo guardaba la preferencia y no tocaba el texto.
        XCTAssertEqual(model.document.text, "{\n\t\"a\": 1\n}")
    }

    func testMinificarQuitaLosEspaciosYNoPierdeElLiteralDelNumero() {
        let model = makeModel()
        model.document.text = "{\n  \"precio\": 7.50,\n  \"id\": 90071992547409931\n}"
        model.document.minify()
        // Si esto degrada a 7.5 o a 90071992547409930 se ha roto la razón de ser del formateador.
        XCTAssertEqual(model.document.text, #"{"precio":7.50,"id":90071992547409931}"#)
    }

    func testMinificarNoTocaUnDocumentoInvalido() {
        let model = makeModel()
        model.document.text = #"{"a": }"#
        model.document.minify()
        XCTAssertEqual(model.document.text, #"{"a": }"#)
        XCTAssertNotNil(model.document.error)
        XCTAssertFalse(model.document.isValid)
    }

    func testOrdenarClaves() {
        let model = makeModel()
        model.document.text = #"{"b":1,"a":2}"#
        model.document.sortKeys()
        XCTAssertEqual(model.document.text, "{\n  \"a\": 2,\n  \"b\": 1\n}")
    }

    func testEscaparYDesescaparEsUnaIdaYVuelta() {
        let model = makeModel()
        let original = #"{"nombre":"Marta Ferreira"}"#
        model.document.text = original
        model.document.escapeAsString()
        XCTAssertNotEqual(model.document.text, original)
        // Lo escapado sigue siendo JSON válido (una cadena en la raíz): la barra no se pone roja.
        XCTAssertTrue(model.document.isValid)
        model.document.unescapeFromString()
        XCTAssertEqual(model.document.text, original)
    }

    func testDesescaparAlgoQueNoEsUnaCadenaAvisaYNoTocaElTexto() {
        let model = makeModel()
        model.document.text = #""mal \q escapado""#
        model.document.unescapeFromString()
        XCTAssertEqual(model.document.text, #""mal \q escapado""#)
        XCTAssertNotNil(model.document.notice)
    }

    // MARK: - Estado del editor

    func testElErrorLlevaLineaYColumnaYElArbolBuenoSeConserva() throws {
        let model = makeModel()
        model.document.text = "{\n  \"a\": 1\n}"
        let arbolBueno = model.document.rootNode
        XCTAssertNotNil(arbolBueno)

        model.document.text = "{\n  \"a\": \n}"
        let error = try XCTUnwrap(model.document.error)
        XCTAssertEqual(error.line, 3)
        // El panel se queda con la última foto buena y se marca desfasado, en vez de vaciarse
        // con cada carácter a medio escribir.
        XCTAssertEqual(model.document.rootNode, arbolBueno)
        XCTAssertTrue(model.document.isTreeStale)
    }

    func testStatusText() {
        let model = makeModel()
        model.document.text = #"{"a":1}"#
        XCTAssertEqual(model.statusText, "JSON válido")
        XCTAssertEqual(model.statusLevel, .ok)

        model.document.text = "{"
        XCTAssertEqual(model.statusLevel, .error)
        XCTAssertTrue(model.statusText.contains("línea"))
    }

    // MARK: - Árbol y búsqueda

    func testCursorEnElTextoSeleccionaSuNodoYAbreLosAncestros() throws {
        let model = makeModel()
        model.document.text = "{\n  \"envio\": {\n    \"metodo\": \"estandar\"\n  }\n}"
        let metodo = try XCTUnwrap(model.document.rootNode?.node(withPath: "envio.metodo"))

        // Por `reportCaret` y no llamando a la navegación directamente: es la costura que
        // reparte el cursor entre la barra de estado y el árbol, y es lo que hace la vista.
        model.reportCaret(line: 3, column: 5, utf16Offset: metodo.start)

        XCTAssertEqual(model.document.caretLine, 3)
        XCTAssertEqual(model.navigation.selectedPath, "envio.metodo")
        // El contenedor que lo lleva se ve abierto; el propio nodo no se despliega solo.
        XCTAssertTrue(model.navigation.isExpanded("envio"))
    }

    func testClicEnUnNodoDelArbolPideLlevarElTextoAhi() throws {
        let model = makeModel()
        model.document.text = "{\n  \"envio\": { \"metodo\": \"estandar\" }\n}"
        let nodo = try XCTUnwrap(model.document.rootNode?.node(withPath: "envio"))

        model.navigation.reveal(nodo)

        XCTAssertEqual(model.navigation.selectedPath, "envio")
        XCTAssertNotNil(model.document.scrollRequest)
    }

    func testBuscarPorClaveFiltraElArbolYCuentaLasCoincidencias() async {
        let model = makeModel()
        model.navigation.searchScope = .keys
        model.navigation.searchQuery = "precio"
        await drainMainQueue()

        XCTAssertEqual(model.navigation.search.count, 2)  // Una por línea del pedido de ejemplo.
        XCTAssertEqual(model.navigation.searchSummary, "2 coincidencias")
        // El árbol se filtra a las coincidencias y a sus ancestros, no al documento entero.
        let rutas = filas(model).map(\.node.path)
        XCTAssertTrue(rutas.contains("lineas[0].precio"))
        XCTAssertFalse(rutas.contains("cliente.nombre"))
        XCTAssertEqual(filas(model).filter(\.isMatch).count, 2)
    }

    func testBuscarPorClaveNoEncuentraLaPalabraDentroDeUnaCadena() async {
        let model = makeModel()
        model.document.text = #"{"descripcion": "precio especial"}"#
        model.navigation.searchScope = .keys
        model.navigation.searchQuery = "precio"
        await drainMainQueue()

        // Esto es lo que distingue buscar sobre el árbol de buscar sobre el texto.
        XCTAssertTrue(model.navigation.search.isEmpty)
        XCTAssertEqual(model.navigation.searchSummary, "Sin coincidencias")
    }

    func testSaltarEntreCoincidenciasEmpiezaEnLaPrimeraYDaLaVuelta() async {
        let model = makeModel()
        model.navigation.searchScope = .keys
        model.navigation.searchQuery = "precio"
        await drainMainQueue()

        model.navigation.nextMatch()
        XCTAssertEqual(model.navigation.currentMatch, 1)
        XCTAssertEqual(model.navigation.selectedPath, "lineas[0].precio")
        XCTAssertEqual(model.navigation.searchSummary, "1 de 2")

        model.navigation.nextMatch()
        XCTAssertEqual(model.navigation.selectedPath, "lineas[1].precio")
        model.navigation.nextMatch()
        XCTAssertEqual(model.navigation.currentMatch, 1)  // Vuelve a la primera.

        model.navigation.previousMatch()
        XCTAssertEqual(model.navigation.currentMatch, 2)
    }

    func testConsultaDeRutaYElAvisoDeQueElAmbitoNoEsElCorrecto() async {
        let model = makeModel()
        model.navigation.searchQuery = "$..precio"  // Ámbito "Todo", que es el de salida.
        await drainMainQueue()
        XCTAssertTrue(model.navigation.search.isEmpty)
        XCTAssertTrue(model.navigation.looksLikePathQuery)  // Se avisa en vez de cambiarlo solo.

        model.navigation.searchAsPath()
        await drainMainQueue()
        XCTAssertEqual(model.navigation.searchScope, .path)
        XCTAssertEqual(model.navigation.search.count, 2)
        XCTAssertFalse(model.navigation.looksLikePathQuery)
    }

    func testConsultaDeRutaMalEscrita() async {
        let model = makeModel()
        model.navigation.searchScope = .path
        model.navigation.searchQuery = "$.[?(@"
        await drainMainQueue()

        XCTAssertTrue(model.navigation.hasSearchError)
        XCTAssertEqual(model.navigation.searchSummary, "Consulta no válida")
        XCTAssertNotNil(model.navigation.searchErrorDetail)
    }

    func testDesplegarYPlegarTodo() {
        let model = makeModel()
        model.navigation.expandAll(of: model.document.rootNode)
        let desplegado = filas(model).count
        model.navigation.collapseAll(of: model.document.rootNode)
        // Plegado del todo queda la raíz y sus hijos directos.
        XCTAssertLessThan(filas(model).count, desplegado)
        XCTAssertTrue(model.navigation.isExpanded("$"))
        XCTAssertFalse(model.navigation.isExpanded("envio"))
    }

    // MARK: - Comparación

    func testLosDosEjemplosDanLasDiferenciasEsperadas() {
        let model = makeModel()
        XCTAssertNil(model.comparison.error)
        XCTAssertTrue(model.comparison.validA && model.comparison.validB)
        XCTAssertFalse(model.comparison.changes.isEmpty)
        XCTAssertFalse(model.comparison.alignedRows.isEmpty)
    }

    func testReordenarClavesYCambiarEspaciadoNoSonDiferencias() {
        let model = makeModel()
        model.comparison.textA = #"{"a":1,"b":{"c":2}}"#
        model.comparison.textB = "{\n  \"b\": { \"c\": 2.0e0 },\n  \"a\": 1\n}"
        model.mode = .compare
        XCTAssertEqual(model.comparison.changes.count, 0)
        XCTAssertEqual(model.statusText, "Documentos equivalentes")
    }

    func testUnDocumentoInvalidoSeInformaConSuLado() {
        let model = makeModel()
        model.comparison.textB = "{"
        model.mode = .compare
        XCTAssertFalse(model.comparison.validB)
        XCTAssertTrue(model.comparison.validA)
        XCTAssertEqual(model.comparison.error?.hasPrefix("B: "), true)
        XCTAssertEqual(model.statusLevel, .error)
    }

    func testIgnorarClavesQuitaEsasDiferencias() {
        let model = makeModel()
        model.comparison.textA = #"{"id":1,"actualizado":"lunes"}"#
        model.comparison.textB = #"{"id":2,"actualizado":"martes"}"#
        XCTAssertEqual(model.comparison.changes.count, 2)

        model.preferences.ignoredKeysText = "actualizado"
        XCTAssertEqual(model.preferences.ignoredKeys, ["actualizado"])
        XCTAssertEqual(model.comparison.changes.count, 1)
        XCTAssertEqual(model.comparison.changes.first?.path, "id")
    }

    func testSaltarDeDiferenciaEnDiferenciaDaLaVuelta() async {
        let model = makeModel()
        model.comparison.textA = #"{"a":1,"b":1,"c":1}"#
        model.comparison.textB = #"{"a":2,"b":2,"c":2}"#
        XCTAssertEqual(model.comparison.changes.count, 3)

        model.comparison.nextDifference()
        await drainMainQueue()
        XCTAssertEqual(model.comparison.differenceSummary, "1 de 3")
        // Saltar desde las Entradas trae a la vista donde se ve el resaltado.
        XCTAssertEqual(model.compareMode, .differences)

        model.comparison.nextDifference(); model.comparison.nextDifference();
        model.comparison.nextDifference()
        await drainMainQueue()
        XCTAssertEqual(model.comparison.differenceSummary, "1 de 3")

        model.comparison.previousDifference()
        await drainMainQueue()
        XCTAssertEqual(model.comparison.differenceSummary, "3 de 3")
    }

    func testLaDiferenciaSeleccionadaResaltaSuFilaAlineada() async throws {
        let model = makeModel()
        model.mode = .compare
        model.comparison.textA = "{\n  \"estado\": \"EN_PREPARACION\"\n}"
        model.comparison.textB = "{\n  \"estado\": \"ENVIADO\"\n}"
        let cambio = try XCTUnwrap(model.comparison.changes.first)

        model.comparison.selectedChangeID = cambio.id
        await drainMainQueue()

        // La fila se **deriva** de la diferencia seleccionada; no es estado en paralelo.
        XCTAssertNotNil(model.comparison.highlightedAlignedRow)
        XCTAssertEqual(
            model.comparison.highlightedAlignedRow, model.comparison.alignedRowIndex(forPath: "estado"))
        XCTAssertNotNil(model.comparison.alignedScroll)
    }

    func testLaSeleccionSeLimpiaSiEsaDiferenciaDejaDeExistir() async {
        let model = makeModel()
        model.comparison.textA = #"{"a":1}"#
        model.comparison.textB = #"{"a":2}"#
        model.comparison.selectedChangeID = model.comparison.changes.first?.id
        await drainMainQueue()

        model.comparison.textB = #"{"a":1}"#
        XCTAssertTrue(model.comparison.changes.isEmpty)
        XCTAssertNil(model.comparison.selectedChangeID)
    }

    func testIntercambiarLadosLlevaTambienLosNombres() {
        let model = makeModel()
        model.comparison.textA = #"{"a":1}"#; model.comparison.nameA = "izquierda.json"
        model.comparison.textB = #"{"a":2}"#; model.comparison.nameB = "derecha.json"

        model.comparison.swapSides()

        XCTAssertEqual(model.comparison.textA, #"{"a":2}"#)
        XCTAssertEqual(model.comparison.nameA, "derecha.json")
        XCTAssertEqual(model.comparison.textB, #"{"a":1}"#)
        XCTAssertEqual(model.comparison.nameB, "izquierda.json")
    }

    // MARK: - Preferencias y recientes

    func testLaSangriaYLasClavesIgnoradasSobrevivenAlRelanzamiento() {
        let primera = makeModel()
        primera.preferences.indent = .tab
        primera.preferences.ignoredKeysText = "actualizado, version"
        primera.preferences.showTree = false

        let segunda = makeModel()  // Como volver a abrir la app.
        XCTAssertEqual(segunda.preferences.indent, .tab)
        XCTAssertEqual(segunda.preferences.ignoredKeysText, "actualizado, version")
        XCTAssertFalse(segunda.preferences.showTree)
    }

    func testUnModeloNuevoNoEscribePreferenciasQueNadieHaTocado() {
        _ = makeModel()
        // Arrancar la app no debe dejar rastro: si no, el "por defecto" deja de poder cambiar.
        XCTAssertNil(defaults.string(forKey: "indentStyle"))
        XCTAssertNil(defaults.object(forKey: "showTree"))
    }

    func testLosRecientesSePersistenSinRepetirYConTope() throws {
        let model = makeModel()
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }

        var urls: [URL] = []
        for i in 0..<10 {
            let url = carpeta.appendingPathComponent("doc\(i).json")
            try #"{"n":\#(i)}"#.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
            model.document.load(url)
        }
        model.document.load(urls[9])  // Repetido: sube al principio, no se duplica.

        XCTAssertEqual(model.preferences.recentDocuments.count, 8)
        XCTAssertEqual(model.preferences.recentDocuments.first, urls[9])
        XCTAssertEqual(Set(model.preferences.recentDocuments).count, 8)

        let otra = makeModel()
        XCTAssertEqual(otra.preferences.recentDocuments, model.preferences.recentDocuments)

        model.preferences.clearRecentDocuments()
        XCTAssertTrue(makeModel().preferences.recentDocuments.isEmpty)
    }

    func testAbrirUnArchivoLoCargaYLoDejaSinCambiosPendientes() throws {
        let model = makeModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try #"{"a":1}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        model.document.load(url)

        XCTAssertEqual(model.document.text, #"{"a":1}"#)
        XCTAssertEqual(model.document.name, url.lastPathComponent)
        XCTAssertFalse(model.document.isDirty)

        model.document.text = #"{"a":2}"#
        XCTAssertTrue(model.document.isDirty)
    }

    // MARK: - Las costuras entre los cuatro objetos

    /// Estos tres prueban lo único que `AppModel` sigue haciendo tras partirlo en cuatro. Si
    /// alguna costura se suelta, la app no falla al compilar: simplemente deja de reaccionar.

    func testElParseoDelDocumentoLlegaALaNavegacion() async {
        let model = makeModel()
        model.document.text = #"{"envio": {"metodo": "estandar"}}"#
        model.navigation.searchScope = .keys
        model.navigation.searchQuery = "metodo"
        await drainMainQueue()
        XCTAssertEqual(model.navigation.search.count, 1)

        // Al reescribir el documento, la búsqueda se rehace sobre el árbol nuevo y la selección
        // que ya no existe se suelta.
        model.navigation.reveal(try! XCTUnwrap(model.document.rootNode?.node(withPath: "envio")))
        XCTAssertEqual(model.navigation.selectedPath, "envio")

        model.document.text = #"{"otra": 1}"#
        await drainMainQueue()
        XCTAssertNil(model.navigation.selectedPath)
        XCTAssertTrue(model.navigation.search.isEmpty)
    }

    func testEnsenarUnNodoDelArbolMueveElTexto() throws {
        let model = makeModel()
        model.document.text = "{\n  \"envio\": { \"metodo\": \"estandar\" }\n}"
        let nodo = try XCTUnwrap(model.document.rootNode?.node(withPath: "envio"))

        model.navigation.reveal(nodo)

        // La navegación decide qué nodo; llevar el texto hasta ahí es del documento.
        XCTAssertEqual(model.navigation.selectedPath, "envio")
        XCTAssertNotNil(model.document.scrollRequest)
    }

    func testLaSangriaLlegaAlDocumentoYALaComparacion() {
        let model = makeModel()
        model.document.text = "{\n  \"a\": 1\n}"
        model.comparison.textA = #"{"a":1}"#
        model.comparison.textB = #"{"a":1}"#

        model.preferences.indent = .spaces(4)

        // Al editor se le aplica al momento...
        XCTAssertEqual(model.document.text, "{\n    \"a\": 1\n}")
        // ...y las columnas de Comparar se realinean con la sangría nueva.
        XCTAssertTrue(model.comparison.alignedRows.contains { $0.row.left?.contains("    \"a\"") == true })
    }

    func testHumanSize() {
        XCTAssertEqual(AppModel.humanSize(512), "512 B")
        XCTAssertEqual(AppModel.humanSize(2048), "2.0 KB")
        XCTAssertEqual(AppModel.humanSize(3 * 1_048_576), "3.0 MB")
    }
}
