import Foundation
import CoreGraphics

/// Plain-data description of one display, in both spaces.
public struct ScreenInfo: Hashable, Sendable, Identifiable {
    public let id: UInt32          // CGDirectDisplayID
    public let nsFrame: NSSpaceRect
    public let axFrame: AXRect
    public let isPrimary: Bool
    public init(id: UInt32, nsFrame: NSSpaceRect, axFrame: AXRect, isPrimary: Bool) {
        self.id = id; self.nsFrame = nsFrame; self.axFrame = axFrame; self.isPrimary = isPrimary
    }
}

/// Pure snapshot of the display configuration. Built from NSScreen by the app layer; testable with synthetic configs.
public struct ScreenLayout: Hashable, Sendable {
    public let screens: [ScreenInfo]
    public let converter: CoordinateConverter
    public let unionAX: AXRect

    /// - Parameter nsFrames: AppKit frames in `NSScreen.screens` order (index 0 must be the primary display).
    public init(ids: [UInt32], nsFrames: [CGRect]) {
        precondition(!nsFrames.isEmpty && ids.count == nsFrames.count)
        let conv = CoordinateConverter(primaryHeight: nsFrames[0].maxY)
        var infos: [ScreenInfo] = []
        var u = AXRect.zero
        for (i, f) in nsFrames.enumerated() {
            let ax = conv.toAX(NSSpaceRect(f))
            infos.append(ScreenInfo(id: ids[i], nsFrame: NSSpaceRect(f), axFrame: ax, isPrimary: i == 0))
            u = u.union(ax)
        }
        screens = infos; converter = conv; unionAX = u
    }

    public var primary: ScreenInfo { screens[0] }

    /// Match by rect center, then greatest overlap, then primary.
    public func screen(containing r: AXRect) -> ScreenInfo {
        if let s = screens.first(where: { $0.axFrame.contains(r.center) }) { return s }
        let best = screens.max { $0.axFrame.intersection(r).area < $1.axFrame.intersection(r).area }
        if let b = best, b.axFrame.intersection(r).area > 0 { return b }
        return primary
    }
    public func screen(containing p: CGPoint) -> ScreenInfo {
        screens.first(where: { $0.axFrame.contains(p) }) ?? primary
    }
    /// Clamp to the union of all screens; garbage frames become empty.
    public func clamp(_ r: AXRect) -> AXRect {
        guard r.isValid else { return .zero }
        return r.intersection(unionAX)
    }
}
