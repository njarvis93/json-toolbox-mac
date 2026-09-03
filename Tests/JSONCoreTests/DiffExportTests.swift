import XCTest
@testable import JSONCore

final class DiffExportTests: XCTestCase {

    private let a = #"{"estado":"EN_PREPARACION","lineas":[{"id":1,"cantidad":2}]}"#
    private let b = #"{"estado":"ENVIADO","lineas":[{"id":1,"cantidad":3}],"seguimiento":"SE99"}"#

    private func changes(ignoring keys: Set<String> = []) throws -> [JSONChange] {
        try JSONDiff.compare(a, b, options: DiffOptions(ignoredKeys: keys))
    }

    private func render(
        _ format: JSONDiffExport.Format,
        ignoring keys: Set<String> = []
    ) throws -> String {
        JSONDiffExport.render(
            try changes(ignoring: keys), format: format,
            nameA: "pedido.json", nameB: "pedido.remoto.json",
            ignoredKeys: keys)
    }

    // MARK: - Texto plano

    func testPlainTextHasHeaderSummaryAndRows() throws {
        let out = try render(.plain)
        XCTAssertTrue(out.hasPrefix("pedido.json  vs  pedido.remoto.json\n"))
        XCTAssertTrue(out.contains("3 diferencias · 1 añadida, 2 modificadas"))
        XCTAssertTrue(out.contains("\"EN_PREPARACION\"  →  \"ENVIADO\""))
        XCTAssertTrue(out.contains("lineas[0].cantidad"))
    }

    /// Sin alinear no se lee: todas las flechas tienen que caer en la misma columna.
    func testPlainTextColumnsAreAligned() throws {
        let rows = try render(.plain).components(separatedBy: "\n")
            .filter { $0.contains(" →  ") }
        XCTAssertEqual(rows.count, 3)
        let positions = Set(rows.map { $0.range(of: " →  ")!.lowerBound.utf16Offset(in: $0) })
        XCTAssertEqual(positions.count, 1, "las flechas no están alineadas")
    }

    func testPlainTextWhenThereAreNoDifferences() throws {
        let out = JSONDiffExport.render([], format: .plain, nameA: "a", nameB: "b")
        XCTAssertTrue(out.contains("Sin diferencias estructurales."))
        XCTAssertFalse(out.contains("→"))
    }

    // MARK: - Markdown

    func testMarkdownIsATable() throws {
        let out = try render(.markdown)
        XCTAssertTrue(out.hasPrefix("**pedido.json** vs **pedido.remoto.json**"))
        XCTAssertTrue(out.contains("| Cambio | Ruta | A | B |"))
        XCTAssertTrue(out.contains("|---|---|---|---|"))
        XCTAssertTrue(out.contains("| modificado | `estado` | `\"EN_PREPARACION\"` | `\"ENVIADO\"` |"))
        XCTAssertTrue(out.contains("| añadido | `seguimiento` | — | `\"SE99\"` |"))
    }

    /// Una barra vertical dentro de un valor partiría la fila en dos celdas.
    func testMarkdownEscapesPipes() throws {
        let changes = try JSONDiff.compare(#"{"a":"x|y"}"#, #"{"a":"z"}"#)
        let out = JSONDiffExport.render(changes, format: .markdown, nameA: "a", nameB: "b")
        XCTAssertTrue(out.contains(#"`"x\|y"`"#))
        for line in out.components(separatedBy: "\n") where line.hasPrefix("| ") {
            // Cabecera, separador y filas: siempre cinco barras sin escapar.
            let bars = line.enumerated().filter {
                $0.element == "|" && ($0.offset == 0 || Array(line)[$0.offset - 1] != "\\")
            }
            XCTAssertEqual(bars.count, 5, "fila con celdas de más: \(line)")
        }
    }

    func testMarkdownWhenThereAreNoDifferences() throws {
        let out = JSONDiffExport.render([], format: .markdown, nameA: "a", nameB: "b")
        XCTAssertFalse(out.contains("| Cambio |"))
    }

    // MARK: - Comunes

    /// Quien lea el volcado en un ticket tiene que poder saber que no se miró todo.
    func testIgnoredKeysAppearInTheExport() throws {
        for format in JSONDiffExport.Format.allCases {
            let out = try render(format, ignoring: ["estado"])
            XCTAssertTrue(out.contains("ignorando estado"), "\(format)")
            XCTAssertFalse(out.contains("EN_PREPARACION"), "\(format)")
        }
    }

    func testIgnoredKeysAppearEvenWithNoDifferences() {
        let out = JSONDiffExport.render(
            [], format: .plain, nameA: "a", nameB: "b",
            ignoredKeys: ["ts", "requestId"])
        XCTAssertTrue(out.contains("ignorando requestId, ts"))
    }

    func testContainersAreMinifiedIntoOneLine() throws {
        let changes = try JSONDiff.compare(#"{"a":1}"#, #"{"a":1,"b":{"x":[1,2]}}"#)
        for format in JSONDiffExport.Format.allCases {
            let out = JSONDiffExport.render(changes, format: format, nameA: "a", nameB: "b")
            XCTAssertTrue(out.contains(#"{"x":[1,2]}"#), "\(format)")
        }
    }

    func testMovedRowsShowTheirIndices() throws {
        let changes = try JSONDiff.compare(
            #"{"l":[{"id":1},{"id":2}]}"#,
            #"{"l":[{"id":2},{"id":1}]}"#)
        let out = JSONDiffExport.render(changes, format: .plain, nameA: "a", nameB: "b")
        XCTAssertTrue(out.contains("movido"))
        XCTAssertTrue(out.contains("0  →  1"), out)
    }
}
