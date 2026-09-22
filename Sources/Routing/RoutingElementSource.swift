import Foundation
import AXCore
import Discovery
import Geometry

/// Runs AX, evaluates quality on the final result, and substitutes the grid when AX is unusable.
/// Grid is all-or-nothing, so `.axSuspect` keeps the AX results.
public struct RoutingElementSource: ElementSource {
    public let ax: AXElementSource
    public let grid: GridElementSource
    public let config: SourceQualityConfig
    /// Per-activation override: nil = heuristic, true = force grid, false = force AX.
    public var forced: Bool?

    public init(ax: AXElementSource, grid: GridElementSource = GridElementSource(), config: SourceQualityConfig = SourceQualityConfig(), forced: Bool? = nil) {
        self.ax = ax; self.grid = grid; self.config = config; self.forced = forced
    }

    public func elements(in window: AXWindow, clip: AXRect) -> AsyncStream<[ActionableElement]> {
        if forced == true { return grid.elements(in: window, clip: clip) }
        let axStream = ax.elements(in: window, clip: clip)
        let forced = self.forced, grid = self.grid, config = self.config
        return AsyncStream { cont in
            let t = Task {
                var all: [ActionableElement] = []
                for await b in axStream { all.append(contentsOf: b); cont.yield(b) }
                let deduped = ActionableClassifier.dedupe(all)
                let verdict = SourceQuality.evaluate(axElements: deduped, window: window.frame, shape: nil, forced: forced, config: config)
                if verdict == .axUnusable {
                    cont.yield(grid.cells(for: window.frame.intersection(clip)))
                }
                cont.finish()
            }
            cont.onTermination = { _ in t.cancel() }
        }
    }
}
