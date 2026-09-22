import XCTest
import Geometry
import Discovery
@testable import Routing

final class SourceQualityTests: XCTestCase {
    func el(_ x: CGFloat, _ y: CGFloat) -> ActionableElement { ActionableElement(element: nil, role: "AXButton", frame: AXRect(x: x, y: y, width: 20, height: 20), depth: 2) }
    let big = AXRect(x: 0, y: 0, width: 1200, height: 800)
    func testForcedWins() {
        XCTAssertEqual(SourceQuality.evaluate(axElements: [el(1, 1)], window: big, shape: nil, forced: true), .forced(grid: true))
    }
    func testZeroElementsUnusable() {
        XCTAssertEqual(SourceQuality.evaluate(axElements: [], window: big, shape: nil), .axUnusable)
        XCTAssertEqual(SourceQuality.evaluate(axElements: [], window: AXRect(x: 0, y: 0, width: 150, height: 150), shape: nil), .axGood)
    }
    func testDegenerateTree() {
        let s = TreeShape(rootChildCount: 1, rootChildRoles: ["AXGroup"], descendantsWithinDepth4: 3)
        XCTAssertEqual(SourceQuality.evaluate(axElements: [el(1, 1)], window: big, shape: s), .axUnusable)
    }
    func testLowDensitySuspect() {
        XCTAssertEqual(SourceQuality.evaluate(axElements: [el(1, 1), el(50, 50)], window: big, shape: nil), .axSuspect)
        let many = (0..<40).map { el(CGFloat($0) * 25, 10) }
        XCTAssertEqual(SourceQuality.evaluate(axElements: many, window: big, shape: nil), .axGood)
    }
    func testGridCells() {
        let cells = GridElementSource().cells(for: AXRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertEqual(cells.count, 100)
        XCTAssertEqual(cells[0].frame, AXRect(x: 0, y: 0, width: 60, height: 40))
    }
}
