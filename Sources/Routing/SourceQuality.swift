import Foundation
import Discovery
import Geometry

public enum SourceVerdict: Equatable, Sendable { case axGood, axSuspect, axUnusable, forced(grid: Bool) }

public struct SourceQualityConfig: Sendable, Hashable {
    public var minWindowForUnusable: CGFloat = 200
    public var minAreaForDensity: CGFloat = 300_000
    public var minDensityPer100pt: Double = 0.15
    public init() {}
}

/// Shape summary of the AX tree, so the heuristic is testable without a screen.
public struct TreeShape: Sendable, Hashable {
    public var rootChildCount: Int
    public var rootChildRoles: [String]
    public var descendantsWithinDepth4: Int
    public init(rootChildCount: Int, rootChildRoles: [String], descendantsWithinDepth4: Int) {
        self.rootChildCount = rootChildCount; self.rootChildRoles = rootChildRoles; self.descendantsWithinDepth4 = descendantsWithinDepth4
    }
}

public enum SourceQuality {
    /// Pure function. Signals in order of certainty.
    public static func evaluate(axElements: [ActionableElement], window: AXRect, shape: TreeShape?, forced: Bool? = nil,
                                config: SourceQualityConfig = SourceQualityConfig()) -> SourceVerdict {
        if let forced { return .forced(grid: forced) }
        let big = window.width > config.minWindowForUnusable && window.height > config.minWindowForUnusable
        if axElements.isEmpty && big { return .axUnusable }
        if let s = shape, s.rootChildCount >= 1, s.rootChildCount <= 2,
           s.rootChildRoles.allSatisfy({ ["AXGroup", "AXUnknown", "AXImage"].contains($0) }),
           s.descendantsWithinDepth4 < 10 { return .axUnusable }
        if window.area > config.minAreaForDensity {
            let tiles = Double(window.area) / 10_000.0
            if Double(axElements.count) / tiles < config.minDensityPer100pt { return .axSuspect }
        }
        return .axGood
    }
}
