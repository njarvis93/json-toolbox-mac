import XCTest
@testable import JSONCore

/// El defecto conocido del diff: comparar `a[0]` con `b[0]` hace que insertar un elemento al
/// principio marque el array entero. Estos tests fijan el emparejado por clave de identidad.
final class ArrayPairingTests: XCTestCase {

    private func changes(
        _ a: String, _ b: String,
        options: DiffOptions = DiffOptions()
    ) throws -> [JSONChange] {
        try JSONDiff.compare(a, b, options: options)
    }

    private func summary(_ changes: [JSONChange]) -> [String] {
        changes.map { "\($0.kind.rawValue) \($0.path)" }
    }

    // MARK: - Lo que venía a arreglar

    func testInsertingAtTheFrontDoesNotMarkTheWholeArray() throws {
        let a = #"{"l":[{"id":1,"n":"uno"},{"id":2,"n":"dos"}]}"#
        let b = #"{"l":[{"id":9,"n":"nuevo"},{"id":1,"n":"uno"},{"id":2,"n":"dos"}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["added l[0]"])
    }

    /// Antes de emparejar por clave, este mismo caso producía ruido en cascada.
    func testWithoutIdentityKeyItStillComparesByPosition() throws {
        let a = #"{"l":[{"n":"uno"},{"n":"dos"}]}"#
        let b = #"{"l":[{"n":"nuevo"},{"n":"uno"},{"n":"dos"}]}"#
        XCTAssertEqual(
            summary(try changes(a, b)),
            ["modified l[0].n", "modified l[1].n", "added l[2]"])
    }

    func testRemovingFromTheMiddle() throws {
        let a = #"{"l":[{"id":1},{"id":2},{"id":3}]}"#
        let b = #"{"l":[{"id":1},{"id":3}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["removed l[1]"])
    }

    func testChangeInsideAPairedElementIsReportedOnItsPath() throws {
        let a = #"{"l":[{"id":1,"n":1},{"id":2,"n":2}]}"#
        let b = #"{"l":[{"id":2,"n":2},{"id":1,"n":99}]}"#
        let result = try changes(a, b)
        XCTAssertTrue(summary(result).contains("modified l[0].n"))
        let modified = try XCTUnwrap(result.first { $0.kind == .modified })
        XCTAssertEqual(modified.before, .number(raw: "1"))
        XCTAssertEqual(modified.after, .number(raw: "99"))
    }

    // MARK: - Reordenar

    func testARealReorderIsReportedAsMoved() throws {
        let a = #"{"l":[{"id":1},{"id":2},{"id":3}]}"#
        let b = #"{"l":[{"id":3},{"id":1},{"id":2}]}"#
        let moved = try changes(a, b).filter { $0.kind == .moved }
        XCTAssertEqual(moved.map(\.path), ["l[2]"])
        XCTAssertEqual(moved.first?.before, .number(raw: "2"))
        XCTAssertEqual(moved.first?.after, .number(raw: "0"))
    }

    /// La parte que hace que esto sirva: una inserción desplaza el índice de todos los demás,
    /// y marcarlos a todos como movidos sería el mismo ruido que se venía a quitar.
    func testShiftingByAnInsertionIsNotAMove() throws {
        let a = #"{"l":[{"id":1},{"id":2},{"id":3}]}"#
        let b = #"{"l":[{"id":0},{"id":1},{"id":2},{"id":3}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["added l[0]"])
    }

    func testShiftingByARemovalIsNotAMove() throws {
        let a = #"{"l":[{"id":0},{"id":1},{"id":2}]}"#
        let b = #"{"l":[{"id":1},{"id":2}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["removed l[0]"])
    }

    func testSameOrderIsNotAMove() throws {
        let a = #"{"l":[{"id":1,"n":1},{"id":2,"n":2}]}"#
        let b = #"{"l":[{"id":1,"n":1},{"id":2,"n":9}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["modified l[1].n"])
    }

    // MARK: - Cuándo NO se empareja por clave

    func testDuplicatedIdentityFallsBackToPosition() throws {
        // Con ids repetidos la clave no identifica, así que no se puede emparejar por ella.
        let a = #"{"l":[{"id":1,"n":1},{"id":1,"n":2}]}"#
        let b = #"{"l":[{"id":1,"n":9},{"id":1,"n":2}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["modified l[0].n"])
    }

    func testMissingKeyInOneElementFallsBackToPosition() throws {
        let a = #"{"l":[{"id":1,"n":1},{"n":2}]}"#
        let b = #"{"l":[{"id":1,"n":1},{"n":9}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["modified l[1].n"])
    }

    func testNullOrContainerIdentityDoesNotCount() throws {
        let a = #"{"l":[{"id":null,"n":1}]}"#
        let b = #"{"l":[{"id":null,"n":9}]}"#
        XCTAssertEqual(summary(try changes(a, b)), ["modified l[0].n"])
        let c = #"{"l":[{"id":{"x":1},"n":1}]}"#
        let d = #"{"l":[{"id":{"x":1},"n":9}]}"#
        XCTAssertEqual(summary(try changes(c, d)), ["modified l[0].n"])
    }

    func testArraysOfScalarsComparePositionally() throws {
        XCTAssertEqual(
            summary(try changes(#"{"l":[1,2,3]}"#, #"{"l":[1,9,3]}"#)),
            ["modified l[1]"])
    }

    func testEmptyArrays() throws {
        XCTAssertEqual(summary(try changes(#"{"l":[]}"#, #"{"l":[{"id":1}]}"#)), ["added l[0]"])
        XCTAssertEqual(summary(try changes(#"{"l":[{"id":1}]}"#, #"{"l":[]}"#)), ["removed l[0]"])
    }

    // MARK: - Elección de la clave

    func testPrefersTheFirstCandidateThatIdentifies() throws {
        // `id` está repetido, así que no vale; `sku` sí identifica.
        let a = #"{"l":[{"id":1,"sku":"A","n":1},{"id":1,"sku":"B","n":2}]}"#
        let b = #"{"l":[{"id":1,"sku":"B","n":2},{"id":1,"sku":"A","n":9}]}"#
        XCTAssertTrue(summary(try changes(a, b)).contains("modified l[0].n"))
    }

    func testIdentityKeysAreConfigurable() throws {
        let a = #"{"l":[{"matricula":"X","n":1},{"matricula":"Y","n":2}]}"#
        let b = #"{"l":[{"matricula":"Y","n":2},{"matricula":"X","n":9}]}"#
        // Sin configurar, `matricula` no es candidata: se compara por posición y cambian las
        // dos matrículas además de los dos valores.
        XCTAssertEqual(
            summary(try changes(a, b)).filter { $0.hasPrefix("modified") },
            [
                "modified l[0].matricula", "modified l[0].n",
                "modified l[1].matricula", "modified l[1].n",
            ])
        let options = DiffOptions(identityKeys: ["matricula"])
        XCTAssertEqual(
            summary(try changes(a, b, options: options)).filter { $0.hasPrefix("modified") },
            ["modified l[0].n"])
    }

    /// Un identificador de más de 2^53 no puede pasar por `Double` sin arriesgar confusiones.
    func testLargeIntegerIdentifiersAreComparedByLiteral() throws {
        let a = #"{"l":[{"id":90071992547409931,"n":1},{"id":90071992547409932,"n":2}]}"#
        let b = #"{"l":[{"id":90071992547409932,"n":2},{"id":90071992547409931,"n":9}]}"#
        XCTAssertEqual(
            summary(try changes(a, b)).filter { $0.hasPrefix("modified") },
            ["modified l[0].n"])
    }

    // MARK: - Anidamiento

    func testPairingWorksAtAnyDepth() throws {
        let a = #"{"p":{"l":[{"id":1,"x":{"y":1}},{"id":2}]}}"#
        let b = #"{"p":{"l":[{"id":2},{"id":1,"x":{"y":9}}]}}"#
        XCTAssertTrue(summary(try changes(a, b)).contains("modified p.l[0].x.y"))
    }

    func testRootLevelArray() throws {
        let a = #"[{"id":1,"n":1},{"id":2}]"#
        let b = #"[{"id":2},{"id":1,"n":9}]"#
        XCTAssertTrue(summary(try changes(a, b)).contains("modified $[0].n"))
    }
}

/// Lo que se gana, medido sobre el caso que motivaba el cambio: un pedido al que se le mete una
/// línea nueva al principio y se le cambia la cantidad de otra.
extension ArrayPairingTests {

    private var pedidoA: String {
        """
        {"lineas":[
          {"sku":"TL-0091","descripcion":"Router dual-band","cantidad":1,"precio":42.90},
          {"sku":"TL-4420","descripcion":"Cable Cat6 3m","cantidad":2,"precio":7.50}
        ]}
        """
    }

    private var pedidoB: String {
        """
        {"lineas":[
          {"sku":"TL-7777","descripcion":"Switch 8 puertos","cantidad":1,"precio":59.00},
          {"sku":"TL-0091","descripcion":"Router dual-band","cantidad":1,"precio":42.90},
          {"sku":"TL-4420","descripcion":"Cable Cat6 3m","cantidad":3,"precio":7.50}
        ]}
        """
    }

    func testPairingRemovesTheCascade() throws {
        let paired = try changes(pedidoA, pedidoB)
        XCTAssertEqual(summary(paired), ["modified lineas[1].cantidad", "added lineas[0]"])
    }

    /// El mismo caso comparando por posición, que es lo que hacía antes: ocho diferencias, de
    /// las que solo dos son reales.
    func testPositionalComparisonOnTheSameCase() throws {
        let positional = try changes(pedidoA, pedidoB, options: DiffOptions(identityKeys: []))
        XCTAssertEqual(positional.count, 8)
    }
}
