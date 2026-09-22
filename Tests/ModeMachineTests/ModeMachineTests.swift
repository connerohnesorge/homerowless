import XCTest
@testable import Modes

final class ModeMachineTests: XCTestCase {
    func step(_ s: ModeState, _ e: ModeEvent) -> (ModeState, [ModeEffect]) { var g = false; return ModeMachine.transition(s, e, pendingG: &g) }

    func testTable() {
        let esc: ModeEvent = .key(nil, keyCode: 53, flags: 0)
        let cases: [(ModeState, ModeEvent, ModeState, [ModeEffect])] = [
            (.idle, .clickHotkey(trusted: true, secureInput: false, excluded: false), .scanning(buffer: ""), [.showOverlay, .enableTap, .startScan]),
            (.idle, .clickHotkey(trusted: false, secureInput: false, excluded: false), .blocked, [.openOnboarding]),
            (.idle, .clickHotkey(trusted: true, secureInput: true, excluded: false), .idle, [.beep, .toast("Blocked by secure input")]),
            (.idle, .scrollHotkey(trusted: true, secureInput: false), .scrolling, [.enableTap, .resolveScrollArea, .parkCursor, .showOverlay]),
            (.scanning(buffer: ""), .batchArrived, .scanning(buffer: ""), [.renderMarkers]),
            (.scanning(buffer: "a"), .finalBatch(count: 5, isGrid: false), .hinting(buffer: "", flags: 0), [.assignLabels, .replayBuffer("a")]),
            (.scanning(buffer: ""), .key("s", keyCode: 1, flags: 0), .scanning(buffer: "s"), []),
            (.scanning(buffer: "asdf"), .key("s", keyCode: 1, flags: 0), .scanning(buffer: "asdf"), []),
            (.scanning(buffer: ""), esc, .idle, [.cancelScan, .hideOverlay, .disableTap]),
            (.scanning(buffer: ""), .scanTimeout, .idle, [.cancelScan, .hideOverlay, .disableTap, .toast("Couldn't read this window")]),
            (.hinting(buffer: "", flags: 0), .key("a", keyCode: 0, flags: 0), .hinting(buffer: "a", flags: 0), [.filter("a")]),
            (.hinting(buffer: "a", flags: 7), .hintResult(.match(3)), .idle, [.hideOverlay, .disableTap, .click(index: 3, flags: 7)]),
            (.hinting(buffer: "ab", flags: 0), .hintResult(.none), .hinting(buffer: "a", flags: 0), [.beep, .filter("a")]),
            (.hinting(buffer: "", flags: 0), .key("z", keyCode: 6, flags: 0), .hinting(buffer: "", flags: 0), []),
            (.hinting(buffer: "ab", flags: 0), .key(nil, keyCode: 51, flags: 0), .hinting(buffer: "a", flags: 0), [.filter("a")]),
            (.hinting(buffer: "", flags: 0), esc, .idle, [.hideOverlay, .disableTap]),
            (.hinting(buffer: "", flags: 0), .flagsChanged(9), .hinting(buffer: "", flags: 9), []),
            (.hinting(buffer: "", flags: 0), .contextInvalidated, .idle, [.hideOverlay, .disableTap]),
            (.hinting(buffer: "", flags: 0), .idleTimeout, .idle, [.hideOverlay, .disableTap]),
            (.scrolling, .key("j", keyCode: 38, flags: 0), .scrolling, [.scroll(.down)]),
            (.scrolling, esc, .idle, [.scroll(.stop), .restoreCursor, .hideOverlay, .disableTap]),
            (.scrolling, .scrollHotkey(trusted: true, secureInput: false), .idle, [.scroll(.stop), .restoreCursor, .hideOverlay, .disableTap]),
            (.hinting(buffer: "", flags: 0), .tapDisabled, .idle, [.cancelScan, .scroll(.stop), .restoreCursor, .hideOverlay, .disableTap, .log("tap disabled; reset to idle")]),
            (.scanning(buffer: ""), .permissionRevoked, .blocked, [.cancelScan, .scroll(.stop), .hideOverlay, .disableTap, .menuBarWarning(true)]),
            (.blocked, .permissionGranted, .idle, [.menuBarWarning(false)]),
            (.gridRefining(selected: 2, nudge: .zero, flags: 0), .key(nil, keyCode: 124, flags: 0), .gridRefining(selected: 2, nudge: CGPoint(x: 8, y: 0), flags: 0), [.gridNudge(dx: 8, dy: 0)]),
            (.gridRefining(selected: 2, nudge: CGPoint(x: 8, y: 0), flags: 0), .key(nil, keyCode: 36, flags: 0), .idle, [.hideOverlay, .disableTap, .gridCommit(index: 2, nudge: CGPoint(x: 8, y: 0), flags: 0)]),
        ]
        for (i, c) in cases.enumerated() {
            let (s, fx) = step(c.0, c.1)
            XCTAssertEqual(s, c.2, "case \(i) state")
            XCTAssertEqual(fx, c.3, "case \(i) effects")
        }
    }
    func testGGSequence() {
        var g = false
        let (_, fx1) = ModeMachine.transition(.scrolling, .key("g", keyCode: 5, flags: 0), pendingG: &g)
        XCTAssertEqual(fx1, []); XCTAssertTrue(g)
        let (_, fx2) = ModeMachine.transition(.scrolling, .key("g", keyCode: 5, flags: 0), pendingG: &g)
        XCTAssertEqual(fx2, [.scroll(.top)]); XCTAssertFalse(g)
        let (_, fx3) = ModeMachine.transition(.scrolling, .key("g", keyCode: 5, flags: UInt64(CGEventFlags.maskShift.rawValue)), pendingG: &g)
        XCTAssertEqual(fx3, [.scroll(.bottom)])
    }
}
