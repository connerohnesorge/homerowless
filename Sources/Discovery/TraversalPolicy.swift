import Foundation

public struct TraversalPolicy: Sendable, Hashable {
    public var maxDepth = 60
    public var maxVisited = 6000
    public var maxChildrenPerNode = 500
    public var wallClock: TimeInterval = 0.400
    public var firstPaint: TimeInterval = 0.120
    public var maxHints = 400
    public var width = 6
    public var maxActionQueries = 400
    /// Disable batching / pruning / concurrency for the M2 baseline benchmark.
    public var naive = false
    public init() {}
    public static let `default` = TraversalPolicy()
    public static var naive: TraversalPolicy { var p = TraversalPolicy(); p.naive = true; p.width = 1; p.wallClock = 30; p.maxVisited = 200_000; return p }
}
