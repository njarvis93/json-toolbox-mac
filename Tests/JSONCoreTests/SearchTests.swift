import XCTest
@testable import JSONCore

final class SearchTests: XCTestCase {

    private let doc = """
        {
          "precio": 10,
          "nota": "el precio incluye IVA",
          "articulos": [
            { "nombre": "Artículo caro", "precio": 42.90 },
            { "nombre": "Cable", "precio": 7.50 }
          ]
        }
        """

    private func find(_ query: String, _ scope: JSONSearch.Scope = .all) throws -> JSONSearch.Result {
        JSONSearch.find(query, in: try JSONParser.parse(doc).root, scope: scope)
    }

    func testEmptyQueryFindsNothing() throws {
        XCTAssertTrue(try find("").isEmpty)
        XCTAssertTrue(try find("   ").isEmpty)
    }

    /// Lo que un buscador de texto no sabe hacer: distinguir la clave `precio` de la palabra
    /// "precio" escrita dentro de una cadena.
    func testKeyScopeIgnoresValues() throws {
        let result = try find("precio", .keys)
        XCTAssertEqual(
            result.matches.map(\.path),
            ["precio", "articulos[0].precio", "articulos[1].precio"])
    }

    func testValueScopeIgnoresKeys() throws {
        let result = try find("precio", .values)
        XCTAssertEqual(result.matches.map(\.path), ["nota"])
    }

    func testAllScopeFindsBoth() throws {
        XCTAssertEqual(try find("precio").count, 4)
    }

    func testCaseAndDiacriticInsensitive() throws {
        // La clave "articulos" y el valor "Artículo caro": la tilde y la mayúscula dan igual.
        XCTAssertEqual(try find("articulo").map(\.path), ["articulos", "articulos[0].nombre"])
        XCTAssertEqual(try find("ARTÍCULO", .values).map(\.path), ["articulos[0].nombre"])
    }

    func testNumbersAndLiteralsAreSearchableByValue() throws {
        XCTAssertEqual(try find("42.90", .values).map(\.path), ["articulos[0].precio"])
        let root = try JSONParser.parse(#"{"a":null,"b":true}"#).root
        XCTAssertEqual(JSONSearch.find("null", in: root, scope: .values).map(\.path), ["a"])
        XCTAssertEqual(JSONSearch.find("true", in: root, scope: .values).map(\.path), ["b"])
    }

    /// Las coincidencias hundidas necesitan que sus ancestros queden visibles, o el árbol
    /// filtrado no puede enseñarlas sin perder el contexto.
    func testVisiblePathsIncludeAncestors() throws {
        let result = try find("Cable")
        XCTAssertEqual(result.matches.map(\.path), ["articulos[1].nombre"])
        XCTAssertEqual(
            result.visiblePaths,
            ["$", "articulos", "articulos[1]", "articulos[1].nombre"])
    }

    func testMatchesComeInPreorder() throws {
        XCTAssertEqual(
            try find("nombre", .keys).map(\.path),
            ["articulos[0].nombre", "articulos[1].nombre"])
    }

    func testContainerMatchesByItsOwnKey() throws {
        let result = try find("articulos", .keys)
        XCTAssertEqual(result.matches.map(\.path), ["articulos"])
        XCTAssertEqual(result.matches.first?.kind, .array)
    }

    func testNoMatches() throws {
        let result = try find("no-existe")
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.visiblePaths.isEmpty)
    }
}

private extension JSONSearch.Result {
    func map<T>(_ transform: (JSONNode) -> T) -> [T] { matches.map(transform) }
}

/// El ámbito de ruta pasa por `JSONPath` pero sale por el mismo sitio que el resto: mismas
/// coincidencias en orden de documento, mismos ancestros visibles, mismo recuento.
extension SearchTests {

    func testPathScopeUsesJSONPath() throws {
        let result = try find("$.articulos[?(@.precio > 10)]", .path)
        XCTAssertEqual(result.matches.map(\.path), ["articulos[0]"])
        XCTAssertNil(result.error)
    }

    func testPathScopeExposesAncestors() throws {
        let result = try find("$..nombre", .path)
        XCTAssertEqual(result.matches.map(\.path), ["articulos[0].nombre", "articulos[1].nombre"])
        XCTAssertTrue(result.visiblePaths.isSuperset(of: ["$", "articulos", "articulos[0]"]))
    }

    func testBadPathReportsTheErrorInsteadOfThrowing() throws {
        let result = try find("$.articulos[?(", .path)
        XCTAssertTrue(result.isEmpty)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.contains("columna"))
    }

    func testPathScopeDoesNotFallBackToTextSearch() throws {
        // "precio" es una consulta inválida, no una búsqueda de texto disfrazada.
        XCTAssertNotNil(try find("precio", .path).error)
    }
}
