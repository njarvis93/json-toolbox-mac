import XCTest
@testable import JSONCore

final class AlignmentTests: XCTestCase {

    func testIdenticalInputsAreAllEqual() {
        let rows = LineAlignment.align(["a", "b", "c"], ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.kind), [.equal, .equal, .equal])
        XCTAssertEqual(rows.map(\.leftNumber), [1, 2, 3])
        XCTAssertEqual(rows.map(\.rightNumber), [1, 2, 3])
    }

    func testInsertedLineCreatesGapOnTheLeft() {
        let rows = LineAlignment.align(["a", "c"], ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.kind), [.equal, .added, .equal])
        XCTAssertNil(rows[1].left)
        XCTAssertEqual(rows[1].right, "b")
        XCTAssertNil(rows[1].leftNumber, "una línea ausente no consume número")
        XCTAssertEqual(rows[1].rightNumber, 2)
        XCTAssertEqual(rows[2].leftNumber, 2)
        XCTAssertEqual(rows[2].rightNumber, 3)
    }

    func testRemovedLine() {
        let rows = LineAlignment.align(["a", "b", "c"], ["a", "c"])
        XCTAssertEqual(rows.map(\.kind), [.equal, .removed, .equal])
        XCTAssertNil(rows[1].right)
    }

    func testCompletelyDifferentInputs() {
        let rows = LineAlignment.align(["a"], ["b"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.kind)), [.removed, .added])
    }

    func testEmptySides() {
        XCTAssertEqual(LineAlignment.align([], []).count, 0)
        XCTAssertEqual(LineAlignment.align(["a"], []).map(\.kind), [.removed])
        XCTAssertEqual(LineAlignment.align([], ["a"]).map(\.kind), [.added])
    }

    func testNumberingSurvivesMultipleGaps() {
        let rows = LineAlignment.align(["a", "b", "c", "d"], ["a", "x", "d"])
        XCTAssertEqual(rows.compactMap(\.leftNumber), [1, 2, 3, 4])
        XCTAssertEqual(rows.compactMap(\.rightNumber), [1, 2, 3])
    }

    func testAlignsFromText() {
        let rows = LineAlignment.align(textA: "a\nb", textB: "a\nb")
        XCTAssertEqual(rows.count, 2)
    }
}

final class HighlightingTests: XCTestCase {

    func testKeysAndStringsAreDistinguished() {
        let spans = SyntaxScanner.spans(#"{"a":"b"}"#)
        XCTAssertEqual(spans.map(\.role), [.punctuation, .key, .punctuation, .string, .punctuation])
    }

    func testOffsetsAreUTF16() {
        // "😀" ocupa 2 unidades UTF-16 y 4 bytes UTF-8.
        let spans = SyntaxScanner.spans(#"["😀",1]"#)
        let number = spans.first { $0.role == .number }
        XCTAssertEqual(number?.location, 6)
        XCTAssertEqual(number?.length, 1)
    }

    func testInvalidDocumentStillHighlightsWhatItCan() {
        let spans = SyntaxScanner.spans(#"{"a": 1, @"#)
        XCTAssertFalse(spans.isEmpty)
        XCTAssertEqual(spans.first?.role, .punctuation)
    }
}
