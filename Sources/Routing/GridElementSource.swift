import Foundation
import AXCore
import Discovery
import Geometry

/// Tiles the window with ~60×40pt cells. No permission, no latency, 100% coverage.
public struct GridElementSource: ElementSource {
    public var cellWidth: CGFloat = 60
    public var cellHeight: CGFloat = 40
    public init(cellWidth: CGFloat = 60, cellHeight: CGFloat = 40) { self.cellWidth = cellWidth; self.cellHeight = cellHeight }

    public func cells(for rect: AXRect) -> [ActionableElement] {
        guard rect.isValid else { return [] }
        let cols = max(1, Int((rect.width / cellWidth).rounded()))
        let rows = max(1, Int((rect.height / cellHeight).rounded()))
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        var out: [ActionableElement] = []
        out.reserveCapacity(cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let f = AXRect(x: rect.minX + CGFloat(c) * cw, y: rect.minY + CGFloat(r) * ch, width: cw, height: ch)
                out.append(ActionableElement(element: nil, role: "GridCell", frame: f, depth: 0))
            }
        }
        return out
    }
    public func elements(in window: AXWindow, clip: AXRect) -> AsyncStream<[ActionableElement]> {
        let cs = cells(for: window.frame.intersection(clip))
        return AsyncStream { c in c.yield(cs); c.finish() }
    }
}
