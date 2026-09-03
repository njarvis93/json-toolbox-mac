import XCTest
@testable import JSONCore

final class DiffTests: XCTestCase {

    func testIdenticalDocuments() throws {
        XCTAssertTrue(try JSONDiff.compare(#"{"a":1}"#, #"{"a":1}"#).isEmpty)
    }

    /// Lo que un diff de texto marcaría y este no.
    func testKeyOrderIsNotADifference() throws {
        let changes = try JSONDiff.compare(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#)
        XCTAssertTrue(changes.isEmpty, "el orden de claves no debe generar diferencias")
    }

    func testWhitespaceIsNotADifference() throws {
        let changes = try JSONDiff.compare("{\"a\":  1}", "{\n  \"a\": 1\n}")
        XCTAssertTrue(changes.isEmpty)
    }

    func testModifiedValue() throws {
        let changes = try JSONDiff.compare(#"{"estado":"NUEVO"}"#, #"{"estado":"ENVIADO"}"#)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].path, "estado")
        XCTAssertEqual(changes[0].kind, .modified)
        XCTAssertEqual(changes[0].before, .string("NUEVO"))
        XCTAssertEqual(changes[0].after, .string("ENVIADO"))
    }

    func testAddedAndRemovedKeys() throws {
        let changes = try JSONDiff.compare(#"{"a":1,"b":2}"#, #"{"a":1,"c":3}"#)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].path, "b")
        XCTAssertEqual(changes[0].kind, .removed)
        XCTAssertEqual(changes[1].path, "c")
        XCTAssertEqual(changes[1].kind, .added)
    }

    func testNestedPath() throws {
        let a = #"{"lineas":[{"sku":"X","cantidad":2}]}"#
        let b = #"{"lineas":[{"sku":"X","cantidad":3}]}"#
        let changes = try JSONDiff.compare(a, b)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].path, "lineas[0].cantidad")
    }

    func testArrayGrowsAndShrinks() throws {
        let grow = try JSONDiff.compare("[1]", "[1,2]")
        XCTAssertEqual(grow.map(\.kind), [.added])
        XCTAssertEqual(grow[0].path, "$[1]")

        let shrink = try JSONDiff.compare("[1,2]", "[1]")
        XCTAssertEqual(shrink.map(\.kind), [.removed])
    }

    func testTypeChange() throws {
        let changes = try JSONDiff.compare(#"{"a":1}"#, #"{"a":"1"}"#)
        XCTAssertEqual(changes.map(\.kind), [.modified])
    }

    func testNumericallyEqualLiteralsAreNotADifference() throws {
        XCTAssertTrue(try JSONDiff.compare(#"{"p":1.50}"#, #"{"p":1.5}"#).isEmpty)
    }

    func testRootScalarChange() throws {
        let changes = try JSONDiff.compare("1", "2")
        XCTAssertEqual(changes.map(\.path), ["$"])
    }

    func testNodeCount() throws {
        let doc = try JSONParser.parse(#"{"a":[1,2],"b":null}"#)
        XCTAssertEqual(doc.nodeCount, 5)  // objeto + array + 2 números + null
    }
}
