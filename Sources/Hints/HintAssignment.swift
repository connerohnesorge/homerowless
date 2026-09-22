import Foundation
import Geometry

public struct Hint: Hashable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let label: String
    public let frame: AXRect
    public init(index: Int, label: String, frame: AXRect) { self.index = index; self.label = label; self.frame = frame }
}

public enum HintAssignment {
    public static let rowQuantum: CGFloat = 12

    /// Reading order: bucket by floor(y/12), then x. Deterministic for a fixed element set.
    public static func readingOrder(_ frames: [AXRect]) -> [Int] {
        frames.indices.sorted { a, b in
            let fa = frames[a], fb = frames[b]
            let ra = (fa.minY / rowQuantum).rounded(.down), rb = (fb.minY / rowQuantum).rounded(.down)
            if ra != rb { return ra < rb }
            if fa.minX != fb.minX { return fa.minX < fb.minX }
            return a < b
        }
    }

    public static func assign(frames: [AXRect], alphabet: [Character] = HintLabelGenerator.defaultAlphabet) -> [Hint] {
        let order = readingOrder(frames)
        let labels = HintLabelGenerator.labels(count: frames.count, alphabet: alphabet)
        return order.enumerated().map { (i, idx) in Hint(index: idx, label: labels[i], frame: frames[idx]) }
    }
}
