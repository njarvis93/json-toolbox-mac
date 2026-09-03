import XCTest
@testable import JSONCore

final class XMLTests: XCTestCase {

    private func value(_ json: String) throws -> JSONValue {
        try JSONParser.parse(json).value
    }

    func testEmitsAnnotatedXML() throws {
        let xml = JSONXML.toXML(try value(#"{"nombre":"Marta","edad":41,"activo":true,"tel":null}"#))
        XCTAssertEqual(
            xml,
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <root type="object">
              <nombre>Marta</nombre>
              <edad type="number">41</edad>
              <activo type="bool">true</activo>
              <tel type="null"/>
            </root>

            """)
    }

    func testArraysUseItemElements() throws {
        let xml = JSONXML.toXML(try value(#"{"skus":["A","B"]}"#))
        XCTAssertTrue(xml.contains("<skus type=\"array\">"))
        XCTAssertEqual(xml.components(separatedBy: "<item>").count - 1, 2)
    }

    func testEmptyContainers() throws {
        let xml = JSONXML.toXML(try value(#"{"a":[],"b":{}}"#))
        XCTAssertTrue(xml.contains("<a type=\"array\"/>"))
        XCTAssertTrue(xml.contains("<b type=\"object\"/>"))
    }

    func testKeyThatIsNotAValidXMLNameGoesToEntry() throws {
        let xml = JSONXML.toXML(try value(#"{"mi clave":1,"2fa":true,"xmlns":"x"}"#))
        XCTAssertTrue(xml.contains(#"<entry key="mi clave" type="number">1</entry>"#))
        XCTAssertTrue(xml.contains(#"<entry key="2fa" type="bool">true</entry>"#))
        XCTAssertTrue(xml.contains(#"<entry key="xmlns">x</entry>"#))
    }

    func testEscapesMarkupInTextAndAttributes() throws {
        let xml = JSONXML.toXML(try value(#"{"a & b":"<tag> \"x\""}"#))
        XCTAssertTrue(xml.contains(#"key="a &amp; b""#))
        XCTAssertTrue(xml.contains("&lt;tag&gt; \"x\""))
    }

    // MARK: - Ida y vuelta

    private func assertRoundTrip(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try value(json)
        let xml = JSONXML.toXML(original)
        let back = try JSONXML.toJSON(xml)
        XCTAssertEqual(
            JSONFormatter.render(back, indent: nil),
            JSONFormatter.render(original, indent: nil),
            file: file, line: line)
    }

    func testRoundTripOfTheSampleDocument() throws {
        try assertRoundTrip(
            """
            {
              "pedidoId": "4471-AC",
              "cliente": { "id": 90071992547409931, "nombre": "Marta Ferreira" },
              "envio": { "transportista": null, "urgente": false },
              "lineas": [
                { "sku": "TL-0091", "cantidad": 1, "precio": 42.90 },
                { "sku": "TL-4420", "cantidad": 2, "precio": 7.50 }
              ],
              "etiquetas": [],
              "meta": {}
            }
            """)
    }

    func testRoundTripKeepsNumberLiterals() throws {
        let xml = JSONXML.toXML(try value(#"{"id":90071992547409931,"p":7.50,"e":1e3}"#))
        let back = JSONFormatter.render(try JSONXML.toJSON(xml), indent: nil)
        XCTAssertEqual(back, #"{"id":90071992547409931,"p":7.50,"e":1e3}"#)
    }

    func testRoundTripOfAwkwardKeysAndText() throws {
        try assertRoundTrip(#"{"mi clave":"<b> & \"c\"","2fa":true,"salto":"a\nb"}"#)
    }

    func testRoundTripOfNestedArrays() throws {
        try assertRoundTrip(#"{"m":[[1,2],[3]],"vacio":[[]]}"#)
    }

    func testRoundTripOfScalarRoot() throws {
        try assertRoundTrip(#""hola""#)
        try assertRoundTrip("42")
        try assertRoundTrip("null")
    }

    // MARK: - XML escrito a mano

    func testInfersShapeWithoutTypeAttributes() throws {
        let value = try JSONXML.toJSON(
            """
            <pedido>
              <id>4471</id>
              <cliente><nombre>Marta</nombre></cliente>
            </pedido>
            """)
        XCTAssertEqual(
            JSONFormatter.render(value, indent: nil),
            #"{"id":"4471","cliente":{"nombre":"Marta"}}"#)
    }

    /// Sin `type`, los números y booleanos llegan como cadenas: es lo honesto, el XML no
    /// los distingue. Quien quiera tipos, que anote o convierta desde JSON.
    func testHandWrittenValuesStayStrings() throws {
        let value = try JSONXML.toJSON("<a><n>41</n><b>true</b></a>")
        XCTAssertEqual(JSONFormatter.render(value, indent: nil), #"{"n":"41","b":"true"}"#)
    }

    func testRepeatedElementsBecomeAnArray() throws {
        let value = try JSONXML.toJSON("<l><tag>a</tag><tag>b</tag><tag>c</tag><otro>x</otro></l>")
        XCTAssertEqual(
            JSONFormatter.render(value, indent: nil),
            #"{"tag":["a","b","c"],"otro":"x"}"#)
    }

    func testItemChildrenAreReadAsAnArray() throws {
        let value = try JSONXML.toJSON("<l><item>a</item><item>b</item></l>")
        XCTAssertEqual(JSONFormatter.render(value, indent: nil), #"["a","b"]"#)
    }

    // MARK: - Errores

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try JSONXML.toJSON("<a><b></a>")) { error in
            XCTAssertTrue(error is JSONError)
        }
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try JSONXML.toJSON("   "))
    }

    func testBadTypeAnnotationThrows() {
        XCTAssertThrowsError(try JSONXML.toJSON(#"<a type="number">no soy un número</a>"#))
        XCTAssertThrowsError(try JSONXML.toJSON(#"<a type="bool">quizá</a>"#))
        XCTAssertThrowsError(try JSONXML.toJSON(#"<a type="fecha">hoy</a>"#))
    }
}
