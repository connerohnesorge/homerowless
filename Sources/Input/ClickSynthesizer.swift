import Foundation
import CoreGraphics
import ApplicationServices
import AXCore
import Geometry

public struct ClickOptions: Sendable, Equatable {
    public var modifiers: CGEventFlags = []
    public var rightClick = false
    public var doubleClick = false
    public var restoreCursor = false
    public init() {}
}

/// CGEvent primary (modifiers, works in Electron), AXPress fallback when the target is fully occluded.
public enum ClickSynthesizer {
    /// Must be called off the main thread only for the AXPress fallback; CGEvent posting is fine anywhere.
    public static func click(at point: CGPoint, options: ClickOptions) {
        let saved = CGEvent(source: nil)?.location
        let src = CGEventSource(stateID: .hidSystemState)
        src?.localEventsSuppressionInterval = 0
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        let mods = options.modifiers.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        let downT: CGEventType = options.rightClick ? .rightMouseDown : .leftMouseDown
        let upT: CGEventType = options.rightClick ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = options.rightClick ? .right : .left
        let clicks = options.doubleClick ? 2 : 1
        for n in 1...clicks {
            for t in [downT, upT] {
                guard let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: point, mouseButton: button) else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e.flags = mods
                e.post(tap: .cghidEventTap)
            }
        }
        if options.restoreCursor, let s = saved {
            usleep(30_000)
            CGWarpMouseCursorPosition(s)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    /// Fallback for fully-occluded elements. Dispatch off-main.
    public static func axPress(_ el: AXElement) -> Bool { el.press() == .success }
}
