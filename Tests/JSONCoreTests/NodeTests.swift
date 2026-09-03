import XCTest
@testable import JSONCore

final class NodeTests: XCTestCase {

    private let doc = """
        {
          "pedidoId": "4471-AC",
          "cliente": { "id": 90071992547409931, "nombre": "Marta" },
          "lineas": [
            { "sku": "TL-0091", "cantidad": 1 },
            { "sku": "TL-4420", "cantidad": 2 }
          ],
          "vacio": {},
          "nada": null
        }
        """

    private func root(_ text: String) throws -> JSONNode {
        try JSONParser.parse(text).root
    }

    /// El rango tiene que recortar exactamente el valor sobre el texto original.
    private func slice(_ node: JSONNode, of text: String) -> String {
        (text as NSString).substring(with: NSRange(location: node.start, length: node.end - node.start))
    }

    private func sliceWithKey(_ node: JSONNode, of text: String) -> String {
        (text as NSString).substring(
            with: NSRange(
                location: node.startWithKey,
                length: node.end - node.startWithKey))
    }

    func testRootCoversTheWholeDocument() throws {
        let r = try root(doc)
        XCTAssertEqual(r.kind, .object)
        XCTAssertEqual(r.path, "$")
        XCTAssertNil(r.key)
        XCTAssertEqual(slice(r, of: doc), doc)
    }

    func testScalarRanges() throws {
        let r = try root(doc)
        let id = try XCTUnwrap(r.node(withPath: "cliente.id"))
        XCTAssertEqual(slice(id, of: doc), "90071992547409931")
        XCTAssertEqual(sliceWithKey(id, of: doc), #""id": 90071992547409931"#)
        XCTAssertEqual(id.kind, .number)
        XCTAssertEqual(id.line, 3)
    }

    func testContainerRangesIncludeBraces() throws {
        let r = try root(doc)
        let cliente = try XCTUnwrap(r.node(withPath: "cliente"))
        XCTAssertEqual(slice(cliente, of: doc), #"{ "id": 90071992547409931, "nombre": "Marta" }"#)
        let vacio = try XCTUnwrap(r.node(withPath: "vacio"))
        XCTAssertEqual(slice(vacio, of: doc), "{}")
    }

    func testArrayItemPathsAndRanges() throws {
        let r = try root(doc)
        let item = try XCTUnwrap(r.node(withPath: "lineas[1]"))
        XCTAssertEqual(slice(item, of: doc), #"{ "sku": "TL-4420", "cantidad": 2 }"#)
        XCTAssertNil(item.key)
        XCTAssertEqual(item.label, "1")
        let cantidad = try XCTUnwrap(r.node(withPath: "lineas[1].cantidad"))
        XCTAssertEqual(slice(cantidad, of: doc), "2")
        XCTAssertEqual(cantidad.line, 6)
    }

    func testRootArrayPaths() throws {
        let r = try root(#"[10,20]"#)
        XCTAssertEqual(r.children.map(\.path), ["$[0]", "$[1]"])
    }

    /// Las rutas del árbol y las del diff tienen que ser la misma cosa: si no, no se puede
    /// saltar desde una fila de diferencias al nodo correspondiente (Fase 5).
    func testPathsMatchDiffPaths() throws {
        let other = doc.replacingOccurrences(of: #""cantidad": 2"#, with: #""cantidad": 9"#)
        let changes = try JSONDiff.compare(doc, other)
        XCTAssertEqual(changes.map(\.path), ["lineas[1].cantidad"])
        let r = try root(doc)
        for change in changes {
            XCTAssertNotNil(r.node(withPath: change.path), "sin nodo para \(change.path)")
        }
    }

    // MARK: - De texto a árbol

    func testNodeAtOffsetFindsTheDeepestNode() throws {
        let r = try root(doc)
        let nombre = try XCTUnwrap(r.node(withPath: "cliente.nombre"))
        let hit = try XCTUnwrap(r.node(atUTF16: nombre.start + 2))
        XCTAssertEqual(hit.path, "cliente.nombre")
    }

    func testOffsetOnAKeyFindsItsValue() throws {
        let r = try root(doc)
        let nombre = try XCTUnwrap(r.node(withPath: "cliente.nombre"))
        XCTAssertEqual(r.node(atUTF16: nombre.startWithKey)?.path, "cliente.nombre")
    }

    /// Entre valores (en una coma, un espacio) el nodo que toca es el contenedor.
    func testOffsetBetweenValuesFindsTheContainer() throws {
        let r = try root(doc)
        let lineas = try XCTUnwrap(r.node(withPath: "lineas"))
        XCTAssertEqual(r.node(atUTF16: lineas.start + 1)?.path, "lineas")
    }

    func testOffsetOutsideTheDocument() throws {
        let r = try root(doc)
        XCTAssertNil(r.node(atUTF16: r.end + 5))
    }

    /// Los desplazamientos son UTF-16 porque es lo que usa NSTextView. Con bytes UTF-8 esto
    /// se descuadraría en cuanto aparece un emoji o una tilde.
    func testOffsetsAreUTF16() throws {
        let text = #"{"a":"añ😀o","b":42}"#
        let r = try root(text)
        let b = try XCTUnwrap(r.node(withPath: "b"))
        XCTAssertEqual(slice(b, of: text), "42")
        XCTAssertEqual(sliceWithKey(b, of: text), #""b":42"#)
        let a = try XCTUnwrap(r.node(withPath: "a"))
        XCTAssertEqual(slice(a, of: text), #""añ😀o""#)
        XCTAssertEqual(a.scalarText, "añ😀o")
    }

    // MARK: - Presentación

    func testLabelsAndSummaries() throws {
        let r = try root(doc)
        XCTAssertEqual(r.summary, "{ 5 claves }")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "lineas")).summary, "[ 2 elementos ]")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "vacio")).summary, "{}")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "nada")).summary, "null")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "pedidoId")).summary, "\"4471-AC\"")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "cliente")).label, "cliente")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "lineas[0]")).label, "0")
    }

    func testSingularSummaries() throws {
        let r = try root(#"{"a":[1],"b":{"c":1}}"#)
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "a")).summary, "[ 1 elemento ]")
        XCTAssertEqual(try XCTUnwrap(r.node(withPath: "b")).summary, "{ 1 clave }")
    }

    func testPreorderWalkVisitsEveryNode() throws {
        let r = try root(doc)
        var paths: [String] = []
        r.forEachNode { paths.append($0.path) }
        XCTAssertEqual(paths.prefix(4), ["$", "pedidoId", "cliente", "cliente.id"])
        // Mismo recuento que `JSONValue.nodeCount`, que es lo que enseña la barra de estado.
        XCTAssertEqual(paths.count, try JSONParser.parse(doc).nodeCount)
    }

    func testScalarRootHasANode() throws {
        let r = try root("42")
        XCTAssertEqual(r.kind, .number)
        XCTAssertEqual(r.path, "$")
        XCTAssertEqual(r.label, "$")
        XCTAssertEqual(r.summary, "42")
        XCTAssertTrue(r.children.isEmpty)
    }
}

extension NodeTests {

    func testChainFromRootToTheDeepestNode() throws {
        let text = """
            {
              "lineas": [
                { "sku": "TL-0091" }
              ]
            }
            """
        let r = try JSONParser.parse(text).root
        let sku = try XCTUnwrap(r.node(withPath: "lineas[0].sku"))
        XCTAssertEqual(
            r.chain(atUTF16: sku.start + 1).map(\.path),
            ["$", "lineas", "lineas[0]", "lineas[0].sku"])
    }

    func testChainIsEmptyOutsideTheDocument() throws {
        let r = try JSONParser.parse(#"{"a":1}"#).root
        XCTAssertTrue(r.chain(atUTF16: 999).isEmpty)
    }

    func testBranchIsNilOnLeaves() throws {
        let r = try JSONParser.parse(#"{"a":1}"#).root
        XCTAssertNil(try XCTUnwrap(r.node(withPath: "a")).branch)
        XCTAssertEqual(r.branch?.count, 1)
    }
}

/// La regla de "qué nodo señala el cursor", que es la mitad delicada de la sincronización.
extension NodeTests {

    private var muestra: String {
        """
        {
          "cliente": { "id": 1, "nombre": "Marta" },
          "lineas": [
            { "sku": "A" },
            { "sku": "B" }
          ]
        }
        """
    }

    /// Cursor en la sangría de la línea 5: lo escrito ahí es `lineas[1]`, no el array.
    func testChainWithLinePrefersWhatIsWrittenOnThatLine() throws {
        let r = try JSONParser.parse(muestra).root
        let item = try XCTUnwrap(r.node(withPath: "lineas[1]"))
        let lineStart = item.startWithKey - 4  // la sangría de esa línea
        XCTAssertEqual(r.chain(atUTF16: lineStart).last?.path, "lineas")
        XCTAssertEqual(r.chain(atUTF16: lineStart, line: item.line).last?.path, "lineas[1]")
    }

    /// Solo un nivel: con todo en una línea, bajar sin freno señalaría `cliente.id`.
    func testChainWithLineDescendsOnlyOneLevel() throws {
        let r = try JSONParser.parse(muestra).root
        let cliente = try XCTUnwrap(r.node(withPath: "cliente"))
        XCTAssertEqual(
            r.chain(atUTF16: cliente.startWithKey - 2, line: cliente.line).last?.path,
            "cliente")
    }

    /// Justo en el inicio de un contenedor no se baja: es lo que selecciona "revelar" desde
    /// el árbol, y bajar sería deshacer lo que el usuario acaba de pedir.
    func testChainWithLineStaysOnAContainerAtItsOwnStart() throws {
        let r = try JSONParser.parse(muestra).root
        let cliente = try XCTUnwrap(r.node(withPath: "cliente"))
        XCTAssertEqual(r.chain(atUTF16: cliente.start, line: cliente.line).last?.path, "cliente")
        XCTAssertEqual(r.chain(atUTF16: cliente.startWithKey, line: cliente.line).last?.path, "cliente")
    }

    func testChainWithLineOnALeafIsUnchanged() throws {
        let r = try JSONParser.parse(muestra).root
        let sku = try XCTUnwrap(r.node(withPath: "lineas[0].sku"))
        XCTAssertEqual(r.chain(atUTF16: sku.start + 1, line: sku.line).last?.path, "lineas[0].sku")
    }
}
