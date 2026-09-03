import XCTest
@testable import JSONCore

final class ParserTests: XCTestCase {

    func testParsesNestedDocument() throws {
        let doc = try JSONParser.parse(#"{"a":[1,2,{"b":null}],"c":true}"#)
        guard case .object(let root) = doc.value else { return XCTFail("raíz no es objeto") }
        XCTAssertEqual(root.keys, ["a", "c"])
        XCTAssertEqual(root["c"], .bool(true))
    }

    func testPreservesKeyOrder() throws {
        let doc = try JSONParser.parse(#"{"z":1,"a":2,"m":3}"#)
        guard case .object(let root) = doc.value else { return XCTFail("raíz no es objeto") }
        XCTAssertEqual(root.keys, ["z", "a", "m"])
    }

    func testEmptyDocument() {
        let err = JSONParser.validate("   \n  ")
        XCTAssertEqual(err?.message, "Documento vacío")
    }

    // MARK: - Posición de los errores

    func testErrorReportsLineAndColumn() {
        let src = """
            {
              "a": 1,
              "b": ,
            }
            """
        let err = JSONParser.validate(src)
        XCTAssertNotNil(err)
        XCTAssertEqual(err?.line, 3)
        XCTAssertEqual(err?.column, 8)
    }

    func testTrailingCommaInObject() {
        let err = JSONParser.validate(#"{"a": 1,}"#)
        XCTAssertEqual(err?.message, "Coma sobrante antes de \"}\"")
        XCTAssertEqual(err?.line, 1)
    }

    func testTrailingCommaInArray() {
        let err = JSONParser.validate("[1, 2, ]")
        XCTAssertEqual(err?.message, "Coma sobrante antes de \"]\"")
    }

    func testUnterminatedString() {
        let err = JSONParser.validate("{\"a\": \"sin cerrar}")
        XCTAssertEqual(err?.message, "Cadena sin cerrar")
    }

    func testDuplicateKeyIsRejected() {
        let err = JSONParser.validate(#"{"a": 1, "a": 2}"#)
        XCTAssertEqual(err?.message, "Clave duplicada \"a\"")
    }

    func testColumnCountsCharactersNotBytes() {
        // "ñ" ocupa 2 bytes: la columna del error debe ser 12, no 13.
        let err = JSONParser.validate(#"{"añ": 1 "b": 2}"#)
        XCTAssertEqual(err?.line, 1)
        XCTAssertEqual(err?.column, 10)
    }

    func testTrailingContent() {
        let err = JSONParser.validate("{} {}")
        XCTAssertEqual(err?.message, "Contenido sobrante tras el valor raíz")
        XCTAssertEqual(err?.column, 4)
    }

    func testLeadingZeroRejected() {
        XCTAssertNotNil(JSONParser.validate("[01]"))
    }

    // MARK: - Cadenas

    func testUnescapesEscapeSequences() throws {
        let doc = try JSONParser.parse(#"{"k":"a\nb\t\"c\\dñ"}"#)
        guard case .object(let root) = doc.value, case .string(let s)? = root["k"] else {
            return XCTFail("no es cadena")
        }
        XCTAssertEqual(s, "a\nb\t\"c\\dñ")
    }

    func testSurrogatePair() throws {
        let doc = try JSONParser.parse(#"["😀"]"#)
        guard case .array(let items) = doc.value, case .string(let s) = items[0] else {
            return XCTFail("no es cadena")
        }
        XCTAssertEqual(s, "😀")
    }
}
