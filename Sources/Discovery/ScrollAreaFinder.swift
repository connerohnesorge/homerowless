import Foundation
import AXCore
import Geometry

public struct ScrollArea: Hashable, @unchecked Sendable {
    public let element: AXElement
    public let frame: AXRect
    public let role: String
    public let verticalScrollBar: AXElement?
    public init(element: AXElement, frame: AXRect, role: String, verticalScrollBar: AXElement?) {
        self.element = element; self.frame = frame; self.role = role; self.verticalScrollBar = verticalScrollBar
    }
}

/// Candidates: AXScrollArea, anything exposing a scroll bar, or AXWebArea (Chromium). ≥100×100 and inside the window.
public enum ScrollAreaFinder {
    public static let minSize: CGFloat = 100

    public static func find(window: AXWindow, clip: AXRect, maxVisited: Int = 3000, deadline: TimeInterval = 0.4) -> [ScrollArea] {
        let start = Date()
        let rootClip = window.frame.intersection(clip)
        var out: [ScrollArea] = []
        var frontier = [(window.element, rootClip)]
        var seen = Set<AXElement>([window.element])
        var visited = 0
        while !frontier.isEmpty, visited < maxVisited, Date().timeIntervalSince(start) < deadline {
            var next: [(AXElement, AXRect)] = []
            for (el, c) in frontier {
                visited += 1
                guard let b = AXBatch.batch(el, [.role, .frame, .children, .verticalScrollBar, .horizontalScrollBar]) else { continue }
                let role = b.role ?? "?"
                let frame = b.frame ?? el.frame()
                var clip = c
                if let f = frame, f.isValid, ActionableClassifier.clippingRoles.contains(role) {
                    clip = c.intersection(f); if clip.isEmpty { continue }
                }
                let vbar = AXUnwrap.element(b[.verticalScrollBar])
                let hbar = AXUnwrap.element(b[.horizontalScrollBar])
                if let f = frame, f.isValid, role == "AXScrollArea" || role == "AXWebArea" || vbar != nil || hbar != nil {
                    let visible = f.intersection(rootClip)
                    if visible.width >= minSize && visible.height >= minSize {
                        out.append(ScrollArea(element: el, frame: visible, role: role, verticalScrollBar: vbar))
                    }
                }
                if role == "AXTextField" || role == "AXMenuBar" { continue }
                let kids = b.children ?? []
                for k in kids.prefix(300) where !seen.contains(k) { seen.insert(k); next.append((k, clip)) }
            }
            frontier = next
        }
        // Dedupe nested areas with identical frames (AXWebArea inside AXScrollArea): keep the outermost (first seen).
        var byFrame: [AXRect: ScrollArea] = [:]
        var order: [AXRect] = []
        for s in out { let k = s.frame.integral; if byFrame[k] == nil { byFrame[k] = s; order.append(k) } }
        return order.compactMap { byFrame[$0] }
    }
}
