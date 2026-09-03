import XCTest
@testable import JSONCore

/// Ignorar claves que cambian solas (marcas de tiempo, identificadores de petición) es lo que
/// hace que comparar dos respuestas reales no produzca ruido.
final class IgnoredKeysTests: XCTestCase {

    private func paths(_ a: String, _ b: String, ignoring keys: Set<String> = []) throws -> [String] {
        try JSONDiff.compare(a, b, options: DiffOptions(ignoredKeys: keys)).map(\.path)
    }

    func testIgnoringAKeyRemovesItsDifference() throws {
        let a = #"{"total":10,"generadoEn":"2026-09-02T10:00:00Z"}"#
        let b = #"{"total":10,"generadoEn":"2026-09-02T11:31:44Z"}"#
        XCTAssertEqual(try paths(a, b), ["generadoEn"])
        XCTAssertEqual(try paths(a, b, ignoring: ["generadoEn"]), [])
    }

    func testIgnoredAtAnyDepth() throws {
        let a = #"{"meta":{"requestId":"a"},"l":[{"id":1,"requestId":"x"}]}"#
        let b = #"{"meta":{"requestId":"b"},"l":[{"id":1,"requestId":"y"}]}"#
        XCTAssertEqual(try paths(a, b).count, 2)
        XCTAssertEqual(try paths(a, b, ignoring: ["requestId"]), [])
    }

    /// Una clave ignorada que solo está en uno de los dos documentos tampoco se informa.
    func testIgnoredKeyPresentOnlyOnOneSide() throws {
        XCTAssertEqual(try paths(#"{"a":1}"#, #"{"a":1,"traza":"x"}"#, ignoring: ["traza"]), [])
        XCTAssertEqual(try paths(#"{"a":1,"traza":"x"}"#, #"{"a":1}"#, ignoring: ["traza"]), [])
    }

    func testIgnoringDoesNotHideRealDifferences() throws {
        let a = #"{"total":10,"ts":"1"}"#
        let b = #"{"total":99,"ts":"2"}"#
        XCTAssertEqual(try paths(a, b, ignoring: ["ts"]), ["total"])
    }

    func testIgnoringAKeyThatDoesNotExistChangesNothing() throws {
        XCTAssertEqual(try paths(#"{"a":1}"#, #"{"a":2}"#, ignoring: ["zzz"]), ["a"])
    }

    /// Las claves son sensibles a mayúsculas, como en JSON.
    func testMatchIsExact() throws {
        XCTAssertEqual(try paths(#"{"ts":1}"#, #"{"ts":2}"#, ignoring: ["TS"]), ["ts"])
    }

    /// Ignorar no puede romper el emparejado por clave de identidad.
    func testIgnoringDoesNotBreakArrayPairing() throws {
        let a = #"{"l":[{"id":1,"ts":"a","n":1},{"id":2,"ts":"a","n":2}]}"#
        let b = #"{"l":[{"id":9,"ts":"b"},{"id":1,"ts":"b","n":1},{"id":2,"ts":"b","n":99}]}"#
        XCTAssertEqual(try paths(a, b, ignoring: ["ts"]), ["l[1].n", "l[0]"])
    }

    // MARK: - Lectura de la lista escrita a mano

    func testParsingTheList() {
        XCTAssertEqual(
            DiffOptions.parseIgnoredKeys("generadoEn, requestId"),
            ["generadoEn", "requestId"])
        XCTAssertEqual(DiffOptions.parseIgnoredKeys(" a ,\nb ,, "), ["a", "b"])
        XCTAssertEqual(DiffOptions.parseIgnoredKeys("   "), [])
        XCTAssertEqual(DiffOptions.parseIgnoredKeys(""), [])
    }
}
