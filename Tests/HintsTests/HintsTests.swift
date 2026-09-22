import XCTest
import Geometry
@testable import Hints

final class HintsTests: XCTestCase {
    func testPrefixFree() {
        for n in [1, 2, 13, 14, 15, 100, 196, 197, 400, 2744] {
            let l = HintLabelGenerator.labels(count: n)
            XCTAssertEqual(l.count, n)
            XCTAssertEqual(Set(l).count, n, "unique for n=\(n)")
            let s = Set(l)
            for a in l { for k in 1..<a.count { XCTAssertFalse(s.contains(String(a.prefix(k))), "\(a) has prefix in set") } }
        }
    }
    func testMinimalMaxLength() {
        XCTAssertEqual(HintLabelGenerator.labels(count: 14).map(\.count).max(), 1)
        XCTAssertEqual(HintLabelGenerator.labels(count: 15).map(\.count).max(), 2)
        XCTAssertEqual(HintLabelGenerator.labels(count: 196).map(\.count).max(), 2)
        XCTAssertEqual(HintLabelGenerator.labels(count: 197).map(\.count).max(), 3)
    }
    func testShortLabelsCommitImmediately() {
        // n=15: 13 single-char labels + 2 two-char labels under the expanded root; no single is a prefix of a pair.
        let l = HintLabelGenerator.labels(count: 15)
        let singles = l.filter { $0.count == 1 }, pairs = l.filter { $0.count == 2 }
        XCTAssertEqual(singles.count, 13); XCTAssertEqual(pairs.count, 2)
        for s in singles { XCTAssertFalse(pairs.contains { $0.hasPrefix(s) }) }
    }
    func testAssignmentDeterministicReadingOrder() {
        let frames = [AXRect(x: 300, y: 5, width: 10, height: 10), AXRect(x: 10, y: 8, width: 10, height: 10), AXRect(x: 0, y: 100, width: 10, height: 10)]
        let a = HintAssignment.assign(frames: frames), b = HintAssignment.assign(frames: frames)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.map(\.index), [1, 0, 2])
    }
    func testFilter() {
        let hints = HintAssignment.assign(frames: (0..<20).map { AXRect(x: CGFloat($0) * 20, y: 0, width: 10, height: 10) })
        let first = hints[0].label
        XCTAssertEqual(HintFilter.apply(hints, buffer: "", char: "z"), .none)
        let r = HintFilter.apply(hints, buffer: String(first.dropLast()), char: first.last!)
        XCTAssertEqual(r, .match(index: hints[0].index))
    }
    func testAlphabetValidation() {
        XCTAssertThrowsError(try HintLabelGenerator.validate(Array("a")))
        XCTAssertThrowsError(try HintLabelGenerator.validate(Array("aa")))
        XCTAssertThrowsError(try HintLabelGenerator.validate(Array("aB")))
        XCTAssertNoThrow(try HintLabelGenerator.validate(Array("ab")))
    }
}
