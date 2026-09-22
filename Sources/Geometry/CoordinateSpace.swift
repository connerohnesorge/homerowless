import Foundation
import CoreGraphics

/// Rectangle in the Accessibility / CGEvent coordinate space: global, origin top-left, +y down.
/// Deliberately distinct from `CGRect`/`NSRect` (AppKit: bottom-left, +y up) so the compiler catches mixups.
public struct AXRect: Hashable, Sendable, Codable {
    public var origin: CGPoint
    public var size: CGSize

    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = CGPoint(x: x, y: y); size = CGSize(width: width, height: height)
    }
    /// Reinterpret a CGRect that is already in AX space (e.g. from `AXValueGetValue`). No conversion.
    public init(axSpace r: CGRect) { origin = r.origin; size = r.size }

    public static let zero = AXRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: CGFloat { origin.x }
    public var minY: CGFloat { origin.y }
    public var maxX: CGFloat { origin.x + size.width }
    public var maxY: CGFloat { origin.y + size.height }
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public var center: CGPoint { CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2) }
    public var area: CGFloat { max(0, size.width) * max(0, size.height) }
    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    /// Reinterpret as CGRect in AX space (for CGEvent APIs). No conversion.
    public var cgRectAXSpace: CGRect { CGRect(origin: origin, size: size) }

    /// Finite, non-empty, and of sane magnitude. Apps emit (-1,-1,0,0) and 1e9-sized garbage.
    public var isValid: Bool {
        let vals = [origin.x, origin.y, size.width, size.height]
        guard vals.allSatisfy({ $0.isFinite && abs($0) < 1_000_000 }) else { return false }
        return size.width > 0 && size.height > 0
    }

    public func intersection(_ other: AXRect) -> AXRect {
        let x0 = max(minX, other.minX), y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        if x1 <= x0 || y1 <= y0 { return .zero }
        return AXRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    public func intersects(_ other: AXRect) -> Bool { !intersection(other).isEmpty }
    public func union(_ other: AXRect) -> AXRect {
        if isEmpty { return other }; if other.isEmpty { return self }
        let x0 = min(minX, other.minX), y0 = min(minY, other.minY)
        return AXRect(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }
    public func contains(_ p: CGPoint) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }
    public func insetBy(dx: CGFloat, dy: CGFloat) -> AXRect {
        AXRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
    /// Rounded to integer points; used as the dedupe key.
    public var integral: AXRect {
        AXRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width.rounded(), height: size.height.rounded())
    }
}

/// Rectangle in AppKit space: global, origin bottom-left, +y up. A distinct wrapper so it can't be confused with AXRect.
public struct NSSpaceRect: Hashable, Sendable {
    public var rect: CGRect
    public init(_ rect: CGRect) { self.rect = rect }
}

/// The single conversion boundary between AX space and AppKit space.
/// `primaryHeight` is `NSScreen.screens[0].frame.maxY` (primary display, NOT `NSScreen.main`).
public struct CoordinateConverter: Sendable, Hashable {
    public let primaryHeight: CGFloat
    public init(primaryHeight: CGFloat) { self.primaryHeight = primaryHeight }

    public func toAppKit(_ ax: AXRect) -> NSSpaceRect {
        NSSpaceRect(CGRect(x: ax.minX, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height))
    }
    public func toAX(_ ns: NSSpaceRect) -> AXRect {
        let r = ns.rect
        return AXRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    public func toAppKit(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    public func toAX(appKitPoint p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    /// Convert an AX rect into a view-local rect for an overlay window whose frame is `screenNS` (AppKit space).
    public func toWindowLocal(_ ax: AXRect, screenNS: NSSpaceRect) -> CGRect {
        let g = toAppKit(ax).rect
        return CGRect(x: g.minX - screenNS.rect.minX, y: g.minY - screenNS.rect.minY, width: g.width, height: g.height)
    }
}
