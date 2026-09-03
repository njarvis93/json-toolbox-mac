import XCTest
@testable import JSONCore

final class FormatterTests: XCTestCase {

    func testPrettyPrint() throws {
        let out = try JSONFormatter.pretty(#"{"a":[1,2],"b":{}}"#)
        XCTAssertEqual(
            out,
            """
            {
              "a": [
                1,
                2
              ],
              "b": {}
            }
            """)
    }

    func testMinify() throws {
        let out = try JSONFormatter.minified(
            """
            {
              "a" : [ 1 , 2 ],
              "b" : "x"
            }
            """)
        XCTAssertEqual(out, #"{"a":[1,2],"b":"x"}"#)
    }

    /// La razón de existir del formateador por tokens.
    func testPreservesLargeIntegerLiteral() throws {
        let big = "90071992547409931"  // > 2^53, Double lo redondea
        let out = try JSONFormatter.minified("{\"id\": \(big)}")
        XCTAssertTrue(out.contains(big), "el literal se degradó: \(out)")
    }

    func testPreservesTrailingZeroInDecimal() throws {
        let out = try JSONFormatter.minified(#"{"precio": 7.50}"#)
        XCTAssertEqual(out, #"{"precio":7.50}"#)
    }

    func testPreservesExponentNotation() throws {
        let out = try JSONFormatter.minified(#"{"n": 1.0e+3}"#)
        XCTAssertEqual(out, #"{"n":1.0e+3}"#)
    }

    func testFormattingIsIdempotent() throws {
        let once = try JSONFormatter.pretty(#"{"a":[1,{"b":2}],"c":"x"}"#)
        let twice = try JSONFormatter.pretty(once)
        XCTAssertEqual(once, twice)
    }

    func testTabIndent() throws {
        let out = try JSONFormatter.pretty(#"{"a":1}"#, indent: .tab)
        XCTAssertEqual(out, "{\n\t\"a\": 1\n}")
    }

    func testEmptyContainersStayInline() throws {
        XCTAssertEqual(
            try JSONFormatter.pretty(#"{"a":{},"b":[]}"#),
            """
            {
              "a": {},
              "b": []
            }
            """)
    }

    func testSortKeysKeepsNumberLiterals() throws {
        let doc = try JSONParser.parse(#"{"z":90071992547409931,"a":7.50}"#)
        let out = JSONFormatter.render(doc.value.keysSorted, indent: nil)
        XCTAssertEqual(out, #"{"a":7.50,"z":90071992547409931}"#)
    }

    func testRenderEscapesControlCharacters() {
        XCTAssertEqual(JSONFormatter.render(.string("a\u{01}b"), indent: nil), "\"a\\u0001b\"")
    }
}
