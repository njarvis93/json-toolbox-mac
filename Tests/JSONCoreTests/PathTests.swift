import XCTest
@testable import JSONCore

final class PathTests: XCTestCase {

    private let doc = """
        {
          "pedidoId": "4471-AC",
          "cliente": { "id": 7, "nombre": "Marta", "vip": true, "baja": null },
          "clave con espacios": 1,
          "lineas": [
            { "sku": "TL-0091", "cantidad": 1, "precio": 42.90 },
            { "sku": "TL-4420", "cantidad": 3, "precio": 7.50 },
            { "sku": "TL-9000", "cantidad": 2 }
          ],
          "totales": { "total": 70.06 }
        }
        """

    private func paths(_ expression: String) throws -> [String] {
        let root = try JSONParser.parse(doc).root
        return try JSONPath.evaluate(expression, in: root).map(\.path)
    }

    // MARK: - Navegación

    func testRoot() throws {
        XCTAssertEqual(try paths("$"), ["$"])
    }

    func testChild() throws {
        XCTAssertEqual(try paths("$.cliente.nombre"), ["cliente.nombre"])
    }

    func testIndex() throws {
        XCTAssertEqual(try paths("$.lineas[1].sku"), ["lineas[1].sku"])
    }

    func testNegativeIndexCountsFromTheEnd() throws {
        XCTAssertEqual(try paths("$.lineas[-1].sku"), ["lineas[2].sku"])
    }

    func testIndexOutOfRangeGivesNothing() throws {
        XCTAssertEqual(try paths("$.lineas[9]"), [])
        XCTAssertEqual(try paths("$.lineas[-9]"), [])
    }

    /// La forma con corchetes existe justo para las claves que no se pueden escribir con punto.
    func testQuotedKey() throws {
        XCTAssertEqual(try paths("$['clave con espacios']"), ["clave con espacios"])
        XCTAssertEqual(try paths(#"$["cliente"].id"#), ["cliente.id"])
    }

    func testWildcards() throws {
        XCTAssertEqual(
            try paths("$.lineas[*].sku"),
            ["lineas[0].sku", "lineas[1].sku", "lineas[2].sku"])
        XCTAssertEqual(try paths("$.totales.*"), ["totales.total"])
    }

    func testRecursiveDescent() throws {
        XCTAssertEqual(try paths("$..sku"), ["lineas[0].sku", "lineas[1].sku", "lineas[2].sku"])
        XCTAssertEqual(try paths("$..nombre"), ["cliente.nombre"])
    }

    func testRecursiveDescentFindsAtAnyDepth() throws {
        let root = try JSONParser.parse(#"{"a":{"x":1,"b":{"x":2}},"x":3}"#).root
        XCTAssertEqual(try JSONPath.evaluate("$..x", in: root).map(\.path), ["a.x", "a.b.x", "x"])
    }

    func testAllDescendants() throws {
        let root = try JSONParser.parse(#"{"a":{"b":1}}"#).root
        XCTAssertEqual(try JSONPath.evaluate("$..*", in: root).map(\.path), ["a", "a.b"])
    }

    // MARK: - Filtros

    func testFilterByExistence() throws {
        XCTAssertEqual(try paths("$.lineas[?(@.precio)]"), ["lineas[0]", "lineas[1]"])
    }

    func testFilterByNumericComparison() throws {
        XCTAssertEqual(try paths("$.lineas[?(@.precio > 10)]"), ["lineas[0]"])
        XCTAssertEqual(try paths("$.lineas[?(@.cantidad >= 2)]"), ["lineas[1]", "lineas[2]"])
        XCTAssertEqual(try paths("$.lineas[?(@.cantidad == 3)].sku"), ["lineas[1].sku"])
    }

    /// Comparar números como números y no como texto: `9` no puede ser mayor que `10`.
    func testNumericComparisonIsNotTextual() throws {
        let root = try JSONParser.parse(#"{"l":[{"n":9},{"n":10}]}"#).root
        XCTAssertEqual(try JSONPath.evaluate("$.l[?(@.n > 9)]", in: root).map(\.path), ["l[1]"])
    }

    func testFilterByString() throws {
        XCTAssertEqual(try paths("$.lineas[?(@.sku == 'TL-4420')]"), ["lineas[1]"])
        XCTAssertEqual(try paths(#"$.lineas[?(@.sku != "TL-4420")]"#), ["lineas[0]", "lineas[2]"])
    }

    func testFilterByBoolAndNull() throws {
        XCTAssertEqual(try paths("$[?(@.vip == true)]"), ["cliente"])
        XCTAssertEqual(try paths("$[?(@.baja == null)]"), ["cliente"])
    }

    func testFilterOnAMissingKeyMatchesNothing() throws {
        XCTAssertEqual(try paths("$.lineas[?(@.descuento > 0)]"), [])
    }

    /// Comparar tipos distintos no es un error, sencillamente no cumple.
    func testComparingDifferentTypesIsNotAnError() throws {
        XCTAssertEqual(try paths("$.lineas[?(@.sku > 10)]"), [])
    }

    // MARK: - Errores

    private func assertError(
        _ expression: String, column: Int? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let root = try JSONParser.parse(doc).root
        XCTAssertThrowsError(try JSONPath.evaluate(expression, in: root), file: file, line: line) {
            guard let e = $0 as? JSONError else { return XCTFail("no es JSONError", file: file, line: line) }
            if let column { XCTAssertEqual(e.column, column, file: file, line: line) }
        }
    }

    func testMustStartWithDollar() throws {
        try assertError("cliente.id", column: 1)
        try assertError("", column: 1)
    }

    func testMalformedExpressions() throws {
        try assertError("$cliente")
        try assertError("$.")
        try assertError("$.lineas[")
        try assertError("$.lineas[abc]")
        try assertError("$.lineas[?(@.precio ~ 3)]")
        try assertError("$.lineas[?(precio > 3)]")
        try assertError("$['sin cerrar")
    }

    /// La columna del error sirve para señalar dónde está el fallo en la consulta.
    func testErrorCarriesTheColumn() throws {
        let root = try JSONParser.parse(doc).root
        XCTAssertThrowsError(try JSONPath.evaluate("$.lineas[?(@.precio ~ 3)]", in: root)) {
            guard let e = $0 as? JSONError else { return XCTFail("no es JSONError") }
            XCTAssertEqual(e.line, 1)
            XCTAssertEqual(e.column, 21)
        }
    }

    // MARK: - Los resultados llevan posición, que es para lo que sirven

    func testResultsCarryTheirRange() throws {
        let root = try JSONParser.parse(doc).root
        let node = try XCTUnwrap(try JSONPath.evaluate("$.lineas[0].precio", in: root).first)
        let slice = (doc as NSString).substring(
            with: NSRange(
                location: node.start,
                length: node.end - node.start))
        XCTAssertEqual(slice, "42.90")
    }
}
