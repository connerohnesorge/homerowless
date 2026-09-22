import Foundation
import CoreGraphics

/// Pure §10 state machine. No effects; returns the effects for the coordinator to perform. Table-tested.
public enum ModeState: Equatable, Sendable {
    case idle
    case blocked
    case scanning(buffer: String)
    case hinting(buffer: String, flags: UInt64)
    /// Grid: label resolved → refine with arrows before Return.
    case gridRefining(selected: Int, nudge: CGPoint, flags: UInt64)
    case scrolling
}

public enum ModeEvent: Equatable, Sendable {
    case clickHotkey(trusted: Bool, secureInput: Bool, excluded: Bool)
    case scrollHotkey(trusted: Bool, secureInput: Bool)
    case batchArrived
    case finalBatch(count: Int, isGrid: Bool)
    case key(Character?, keyCode: UInt16, flags: UInt64)
    case flagsChanged(UInt64)
    case escape
    case scanTimeout
    case idleTimeout
    case contextInvalidated   // app deactivated, display reconfig, window moved
    case tapDisabled
    case permissionRevoked
    case permissionGranted
    /// Filter result computed by the coordinator for a hint key.
    case hintResult(HintKeyResult)
}

public enum HintKeyResult: Equatable, Sendable { case match(Int), partial, none }

public enum ModeEffect: Equatable, Sendable {
    case showOverlay, hideOverlay, enableTap, disableTap
    case startScan, cancelScan
    case renderMarkers, assignLabels, replayBuffer(String)
    case filter(String)
    case beep
    case toast(String)
    case openOnboarding
    case click(index: Int, flags: UInt64)
    case gridSelect(Int)
    case gridNudge(dx: CGFloat, dy: CGFloat)
    case gridCommit(index: Int, nudge: CGPoint, flags: UInt64)
    case resolveScrollArea, parkCursor, restoreCursor
    case scroll(ScrollCommand)
    case reenableTap, log(String)
    case menuBarWarning(Bool)
}

public enum ScrollCommand: Equatable, Sendable { case left, down, up, right, halfDown, halfUp, top, bottom, stop }

public enum ModeMachine {
    public static let bufferCap = 4
    public static let alphabetDefault: Set<Character> = Set("asdfghjklqwert")

    public static func transition(_ s: ModeState, _ e: ModeEvent, alphabet: Set<Character> = alphabetDefault, pendingG: inout Bool) -> (ModeState, [ModeEffect]) {
        switch (s, e) {
        // ---- idle ----
        case (.idle, .clickHotkey(let trusted, let secure, let excluded)):
            if !trusted { return (.blocked, [.openOnboarding]) }
            if secure { return (.idle, [.beep, .toast("Blocked by secure input")]) }
            if excluded { return (.idle, []) }
            return (.scanning(buffer: ""), [.showOverlay, .enableTap, .startScan])
        case (.idle, .scrollHotkey(let trusted, let secure)):
            if !trusted { return (.blocked, [.openOnboarding]) }
            if secure { return (.idle, [.beep, .toast("Blocked by secure input")]) }
            return (.scrolling, [.enableTap, .resolveScrollArea, .parkCursor, .showOverlay])
        case (.blocked, .permissionGranted): return (.idle, [.menuBarWarning(false)])
        case (.blocked, .clickHotkey), (.blocked, .scrollHotkey): return (.blocked, [.openOnboarding])

        // ---- scanning ----
        case (.scanning, .batchArrived): return (s, [.renderMarkers])
        case (.scanning(let buf), .finalBatch(let count, _)):
            if count == 0 { return (.idle, [.hideOverlay, .disableTap, .toast("Nothing clickable found")]) }
            return (.hinting(buffer: "", flags: 0), [.assignLabels] + (buf.isEmpty ? [] : [.replayBuffer(buf)]))
        case (.scanning(let buf), .key(let c, let code, _)):
            if code == 53 { return (.idle, [.cancelScan, .hideOverlay, .disableTap]) }
            if let c, alphabet.contains(c), buf.count < bufferCap { return (.scanning(buffer: buf + String(c)), []) }
            return (s, [])
        case (.scanning, .clickHotkey), (.scanning, .escape): return (.idle, [.cancelScan, .hideOverlay, .disableTap])
        case (.scanning, .scanTimeout): return (.idle, [.cancelScan, .hideOverlay, .disableTap, .toast("Couldn't read this window")])

        // ---- hinting ----
        case (.hinting(let buf, let flags), .key(let c, let code, let f)):
            if code == 53 { return (.idle, [.hideOverlay, .disableTap]) }
            if code == 51 { let nb = String(buf.dropLast()); return (.hinting(buffer: nb, flags: flags), [.filter(nb)]) }
            guard let c, alphabet.contains(c) else { return (s, []) }   // consume and ignore — never leak
            return (.hinting(buffer: buf + String(c), flags: f), [.filter(buf + String(c))])
        case (.hinting(let buf, let flags), .hintResult(let r)):
            switch r {
            case .match(let i): return (.idle, [.hideOverlay, .disableTap, .click(index: i, flags: flags)])
            case .partial: return (.hinting(buffer: buf, flags: flags), [])
            case .none: return (.hinting(buffer: String(buf.dropLast()), flags: flags), [.beep, .filter(String(buf.dropLast()))])
            }
        case (.hinting(let buf, _), .flagsChanged(let f)): return (.hinting(buffer: buf, flags: f), [])
        case (.hinting, .escape), (.hinting, .clickHotkey): return (.idle, [.hideOverlay, .disableTap])
        case (.hinting, .contextInvalidated), (.hinting, .idleTimeout): return (.idle, [.hideOverlay, .disableTap])
        case (.hinting(_, let flags), .finalBatch(_, let isGrid)) where isGrid: return (.hinting(buffer: "", flags: flags), [.assignLabels])

        // ---- grid refinement ----
        case (.gridRefining(let sel, let nudge, let flags), .key(_, let code, let f)):
            switch code {
            case 53: return (.idle, [.hideOverlay, .disableTap])
            case 36, 49: return (.idle, [.hideOverlay, .disableTap, .gridCommit(index: sel, nudge: nudge, flags: f != 0 ? f : flags)])
            case 123: return (.gridRefining(selected: sel, nudge: CGPoint(x: nudge.x - 8, y: nudge.y), flags: flags), [.gridNudge(dx: -8, dy: 0)])
            case 124: return (.gridRefining(selected: sel, nudge: CGPoint(x: nudge.x + 8, y: nudge.y), flags: flags), [.gridNudge(dx: 8, dy: 0)])
            case 125: return (.gridRefining(selected: sel, nudge: CGPoint(x: nudge.x, y: nudge.y + 8), flags: flags), [.gridNudge(dx: 0, dy: 8)])
            case 126: return (.gridRefining(selected: sel, nudge: CGPoint(x: nudge.x, y: nudge.y - 8), flags: flags), [.gridNudge(dx: 0, dy: -8)])
            default: return (s, [])
            }
        case (.gridRefining, .escape), (.gridRefining, .clickHotkey), (.gridRefining, .contextInvalidated), (.gridRefining, .idleTimeout):
            return (.idle, [.hideOverlay, .disableTap])

        // ---- scrolling ----
        case (.scrolling, .key(let c, let code, let flags)):
            if code == 53 { return (.idle, [.scroll(.stop), .restoreCursor, .hideOverlay, .disableTap]) }
            guard let c else { return (s, []) }
            let shift = flags & UInt64(CGEventFlags.maskShift.rawValue) != 0
            switch c {
            case "h": pendingG = false; return (s, [.scroll(.left)])
            case "j": pendingG = false; return (s, [.scroll(.down)])
            case "k": pendingG = false; return (s, [.scroll(.up)])
            case "l": pendingG = false; return (s, [.scroll(.right)])
            case "d": pendingG = false; return (s, [.scroll(.halfDown)])
            case "u": pendingG = false; return (s, [.scroll(.halfUp)])
            case "g":
                if shift { pendingG = false; return (s, [.scroll(.bottom)]) }
                if pendingG { pendingG = false; return (s, [.scroll(.top)]) }
                pendingG = true; return (s, [])
            default: pendingG = false; return (s, [])
            }
        case (.scrolling, .scrollHotkey), (.scrolling, .escape): return (.idle, [.scroll(.stop), .restoreCursor, .hideOverlay, .disableTap])
        case (.scrolling, .contextInvalidated): return (.idle, [.scroll(.stop), .restoreCursor, .hideOverlay, .disableTap])

        // ---- any ----
        case (_, .tapDisabled):
            if case .idle = s { return (.idle, []) }
            return (.idle, [.cancelScan, .scroll(.stop), .restoreCursor, .hideOverlay, .disableTap, .log("tap disabled; reset to idle")])
        case (_, .permissionRevoked):
            return (.blocked, [.cancelScan, .scroll(.stop), .hideOverlay, .disableTap, .menuBarWarning(true)])
        default:
            return (s, [])
        }
    }
}
