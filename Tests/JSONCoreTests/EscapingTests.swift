import XCTest
@testable import JSONCore

final class EscapingTests: XCTestCase {

    func testEscapeProducesValidJSONString() throws {
        let json = """
            {
              "a": 1
            }
            """
        let escaped = JSONEscaping.escape(json)
        XCTAssertEqual(escaped, #""{\n  \"a\": 1\n}""#)
        // Lo escapado sigue siendo un documento JSON válido (una cadena en la raíz).
        XCTAssertNil(JSONParser.validate(escaped))
    }

    func testRoundTrip() throws {
        let json = try JSONFormatter.pretty(#"{"texto":"con \"comillas\" y \\ barra","n":7.50}"#)
        XCTAssertEqual(try JSONEscaping.unescape(JSONEscaping.escape(json)), json)
    }

    func testUnescapeAcceptsBodyWithoutQuotes() throws {
        XCTAssertEqual(try JSONEscaping.unescape(#"{\"a\":1}"#), #"{"a":1}"#)
    }

    func testUnescapeIgnoresSurroundingWhitespace() throws {
        XCTAssertEqual(try JSONEscaping.unescape("  \n \"a\\tb\" \n "), "a\tb")
    }

    /// `"a": "b"` empieza y acaba por comilla sin ser un literal: no hay que despellejarlo.
    func testUnescapeDoesNotStripQuotesOfNonLiteral() throws {
        XCTAssertEqual(try JSONEscaping.unescape(#""a": "b""#), #""a": "b""#)
    }

    func testUnescapeUnicodeAndSurrogatePair() throws {
        XCTAssertEqual(try JSONEscaping.unescape(#""año 😀""#), "año 😀")
    }

    func testControlCharactersRoundTrip() throws {
        let original = "tab\there\nsalto\u{0}nulo"
        let escaped = JSONEscaping.escape(original)
        XCTAssertEqual(escaped, #""tab\there\nsalto\u0000nulo""#)
        XCTAssertEqual(try JSONEscaping.unescape(escaped), original)
    }

    func testUnknownEscapeReportsPosition() {
        XCTAssertThrowsError(try JSONEscaping.unescape(#""ab\qc""#)) { error in
            guard let e = error as? JSONError else { return XCTFail("no es JSONError") }
            XCTAssertTrue(e.message.contains("Escape desconocido"))
            XCTAssertEqual(e.line, 1)
            XCTAssertEqual(e.column, 3)
        }
    }

    func testTruncatedUnicodeEscapeThrows() {
        XCTAssertThrowsError(try JSONEscaping.unescape(#""\u12""#))
        XCTAssertThrowsError(try JSONEscaping.unescape(#""\u12zz""#))
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try JSONEscaping.unescape("   \n "))
    }

    func testErrorPositionCountsLines() {
        XCTAssertThrowsError(try JSONEscaping.unescape("linea1\\nliteral\nlinea2\\q")) { error in
            guard let e = error as? JSONError else { return XCTFail("no es JSONError") }
            XCTAssertEqual(e.line, 2)
            XCTAssertEqual(e.column, 7)
        }
    }

    /// El escapado va encima del formateador, así que no puede degradar los literales.
    func testPreservesNumberLiterals() throws {
        let json = try JSONFormatter.pretty(#"{"id":90071992547409931,"p":7.50}"#)
        let back = try JSONEscaping.unescape(JSONEscaping.escape(json))
        XCTAssertTrue(back.contains("90071992547409931"))
        XCTAssertTrue(back.contains("7.50"))
    }
}
