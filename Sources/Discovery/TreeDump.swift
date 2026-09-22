import Foundation
import AXCore

/// Diagnostic: compact role/child-count dump of the first few levels.
public enum TreeDump {
    public static func brief(_ root: AXElement, depth maxDepth: Int = 6, maxNodes: Int = 60) -> String {
        var out: [String] = []
        func rec(_ e: AXElement, _ d: Int) {
            guard out.count < maxNodes, d <= maxDepth else { return }
            let b = AXBatch.batch(e)
            let f = b?.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nil"
            let n = b?.children?.count ?? -1
            out.append(String(repeating: " ", count: d) + "\(b?.role ?? "batchFail") [\(f)] kids=\(n) cnt=\(e.childCount())")
            for c in (b?.children ?? []).prefix(8) { rec(c, d + 1) }
        }
        rec(root, 0)
        return out.joined(separator: "\n")
    }
}
