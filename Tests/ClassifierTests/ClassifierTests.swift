import XCTest
import Geometry
@testable import Discovery

final class ClassifierTests: XCTestCase {
    let clip = AXRect(x: 0, y: 0, width: 1000, height: 1000)
    func testAllowlist() {
        XCTAssertEqual(ActionableClassifier.classify(role: "AXButton", subrole: nil, enabled: true, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: nil), .actionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXButton", subrole: nil, enabled: false, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: nil), .notActionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXButton", subrole: nil, enabled: true, frame: AXRect(x: 1, y: 1, width: 1, height: 10), clip: clip, parentRole: nil), .notActionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXButton", subrole: nil, enabled: true, frame: AXRect(x: 2000, y: 1, width: 10, height: 10), clip: clip, parentRole: nil), .notActionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXGroup", subrole: nil, enabled: nil, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: nil), .needsActionQuery)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXStaticText", subrole: nil, enabled: nil, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: "AXButton"), .actionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXStaticText", subrole: nil, enabled: nil, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: "AXGroup"), .notActionable)
        XCTAssertEqual(ActionableClassifier.classify(role: "AXGroup", subrole: "AXTabButton", enabled: nil, frame: AXRect(x: 1, y: 1, width: 10, height: 10), clip: clip, parentRole: nil), .actionable)
    }
    func testDedupeKeepsDeepestPriority() {
        let f = AXRect(x: 10.2, y: 10.4, width: 100, height: 20)
        let els = [ActionableElement(element: nil, role: "AXGroup", frame: f, depth: 3),
                   ActionableElement(element: nil, role: "AXLink", frame: f.integral, depth: 5),
                   ActionableElement(element: nil, role: "AXStaticText", frame: f, depth: 6)]
        let d = ActionableClassifier.dedupe(els)
        XCTAssertEqual(d.count, 1); XCTAssertEqual(d[0].role, "AXLink")
    }
    func testChromiumDetection() {
        XCTAssertFalse(AppCompat.isChromiumLike(bundleURL: URL(fileURLWithPath: "/Applications/Finder.app")))
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        if FileManager.default.fileExists(atPath: chrome.path) { XCTAssertTrue(AppCompat.isChromiumLike(bundleURL: chrome)) }
    }
}
