import Foundation
import CoreGraphics
import CoreVideo
import AXCore
import os

/// Continuous pixel scrolling driven by a CVDisplayLink while a key is held; ramps ~6 → ~30 px/tick over 200ms.
/// Events route by cursor location, so the caller parks the cursor in the target area first.
public final class ScrollSynthesizer: @unchecked Sendable {
    public struct Config: Sendable, Hashable, Codable {
        public var startPxPerTick: Double = 6
        public var maxPxPerTick: Double = 30
        public var rampSeconds: Double = 0.2
        public var halfPageFraction: Double = 0.5
        public init() {}
    }
    public var config = Config()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private struct State { var dx = 0.0; var dy = 0.0; var since: TimeInterval = 0; var point = CGPoint.zero }
    private var link: CVDisplayLink?
    private let src = CGEventSource(stateID: .hidSystemState)

    public init() { src?.localEventsSuppressionInterval = 0 }

    public func park(at p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        lock.withLock { $0.point = p }
    }

    /// Direction: +dy scrolls content up (like wheel "up"). Hardcoded mapping; ignores natural-scrolling preference.
    public func setVelocity(dx: Double, dy: Double) {
        let wasIdle = lock.withLock { s -> Bool in
            let idle = s.dx == 0 && s.dy == 0
            if idle && (dx != 0 || dy != 0) { s.since = CFAbsoluteTimeGetCurrent() }
            s.dx = dx; s.dy = dy
            return idle
        }
        if wasIdle && (dx != 0 || dy != 0) { startLink() }
        if dx == 0 && dy == 0 { stopLink() }
    }
    public func stop() { setVelocity(dx: 0, dy: 0) }

    private func startLink() {
        if link != nil { return }
        var l: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&l)
        guard let l else { return }
        CVDisplayLinkSetOutputCallback(l, { _, _, _, _, _, user in
            guard let user else { return kCVReturnSuccess }
            Unmanaged<ScrollSynthesizer>.fromOpaque(user).takeUnretainedValue().tick()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(l)
        link = l
    }
    private func stopLink() {
        if let l = link { CVDisplayLinkStop(l) }
        link = nil
    }

    private func tick() {
        let (dx, dy, since, p) = lock.withLock { ($0.dx, $0.dy, $0.since, $0.point) }
        guard dx != 0 || dy != 0 else { return }
        let t = min(1, (CFAbsoluteTimeGetCurrent() - since) / config.rampSeconds)
        let speed = config.startPxPerTick + (config.maxPxPerTick - config.startPxPerTick) * t
        post(wheel1: Int32(dy * speed), wheel2: Int32(dx * speed), units: .pixel, at: p, continuous: true)
    }

    private func post(wheel1: Int32, wheel2: Int32, units: CGScrollEventUnit, at p: CGPoint, continuous: Bool) {
        guard let e = CGEvent(scrollWheelEvent2Source: src, units: units, wheelCount: 2, wheel1: wheel1, wheel2: wheel2, wheel3: 0) else { return }
        e.location = p
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }

    /// One-shot burst (half page etc.) in pixels.
    public func burst(dy: Double, height: Double) {
        let p = lock.withLock { $0.point }
        let total = Int32(dy * height * config.halfPageFraction)
        post(wheel1: total, wheel2: 0, units: .pixel, at: p, continuous: true)
    }

    /// gg / G: exact via AXVerticalScrollBar value. Where no scrollbar is exposed (Chromium web content) synthesize
    /// Home / End, which browsers and NSScrollView map to top / bottom. A single huge wheel event is clamped by Chrome.
    public func jump(toTop: Bool, area: AXElement?, scrollBar: AXElement?) {
        if let bar = scrollBar, bar.set(.value, double: toTop ? 0.0 : 1.0) == .success { return }
        let key: CGKeyCode = toTop ? 115 : 119   // Home / End
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = []
            e.post(tap: .cghidEventTap)
        }
    }
}
