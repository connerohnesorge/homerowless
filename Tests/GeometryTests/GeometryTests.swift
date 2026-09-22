import XCTest
@testable import Geometry

final class GeometryTests: XCTestCase {
    // Primary 1920x1080 at origin; second display 1440x900 placed above and to the left (negative x, y above primary top).
    let layout = ScreenLayout(ids: [1, 2], nsFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: -1440, y: 1080, width: 1440, height: 900)])

    func testPrimaryRoundTrip() {
        let ax = AXRect(x: 100, y: 50, width: 200, height: 30)
        let ns = layout.converter.toAppKit(ax)
        XCTAssertEqual(ns.rect, CGRect(x: 100, y: 1080 - 80, width: 200, height: 30))
        XCTAssertEqual(layout.converter.toAX(ns), ax)
    }
    func testSecondaryAboveLeftHasNegativeCoordsInBothSpaces() {
        let s = layout.screens[1]
        XCTAssertEqual(s.axFrame, AXRect(x: -1440, y: -900, width: 1440, height: 900))
        let ax = AXRect(x: -1000, y: -500, width: 10, height: 10)
        let ns = layout.converter.toAppKit(ax).rect
        XCTAssertEqual(ns.origin, CGPoint(x: -1000, y: 1080 + 490))
        XCTAssertEqual(layout.converter.toAX(NSSpaceRect(ns)), ax)
        XCTAssertEqual(layout.screen(containing: ax).id, 2)
    }
    func testWindowLocal() {
        let ax = AXRect(x: -1400, y: -880, width: 100, height: 20)
        let local = layout.converter.toWindowLocal(ax, screenNS: layout.screens[1].nsFrame)
        XCTAssertEqual(local, CGRect(x: 40, y: 900 - 40, width: 100, height: 20))
    }
    func testClampRejectsGarbage() {
        XCTAssertEqual(layout.clamp(AXRect(x: -1, y: -1, width: 0, height: 0)), .zero)
        XCTAssertEqual(layout.clamp(AXRect(x: 0, y: 0, width: 1e9, height: 1e9)), .zero)
        XCTAssertEqual(layout.clamp(AXRect(x: 1900, y: 1000, width: 100, height: 100)), AXRect(x: 1900, y: 1000, width: 20, height: 80))
    }
    func testScreenFallbackByOverlapThenPrimary() {
        XCTAssertEqual(layout.screen(containing: AXRect(x: 1910, y: 10, width: 40, height: 10)).id, 1)
        XCTAssertEqual(layout.screen(containing: AXRect(x: 5000, y: 5000, width: 1, height: 1)).id, 1)
    }
}
