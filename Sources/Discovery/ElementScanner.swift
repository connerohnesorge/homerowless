import Foundation
import ApplicationServices
import AXCore
import Geometry

public struct ScanStats: Sendable {
    public var visited = 0
    public var emitted = 0
    public var pruned = 0
    public var actionQueries = 0
    public var elapsed: TimeInterval = 0
    public var timedOut = false
    public var levels = 0
    public init() {}
}

/// Breadth-first, budgeted, width-limited scan of one window. Never runs AX calls on the main thread:
/// callers must invoke from a non-main context (the actor guarantees that once the executor is a background one).
public actor ElementScanner {
    public let policy: TraversalPolicy
    /// Per-pid cache: does this app implement AXVisibleChildren usefully (per role)?
    private var visibleChildrenSupport: [String: Bool] = [:]  // "\(pid):\(role)"

    public init(policy: TraversalPolicy = .default) { self.policy = policy }

    struct Node: @unchecked Sendable {
        let el: AXElement
        let depth: Int
        let clip: AXRect
        let parentRole: String?
    }
    struct Visit: @unchecked Sendable {
        var found: ActionableElement?
        var children: [Node]
        var pruned: Bool
        var usedActionQuery: Bool
    }

    /// Streams one batch per BFS level. The final batch is followed by stream termination; `stats` is filled after.
    public func scan(window: AXWindow, clip screenClip: AXRect) -> (AsyncStream<[ActionableElement]>, Task<ScanStats, Never>) {
        let policy = self.policy
        let (stream, cont) = AsyncStream<[ActionableElement]>.makeStream()
        let task = Task<ScanStats, Never>(priority: .userInitiated) { [weak self] in
            let start = Date()
            var stats = ScanStats()
            let rootClip = window.frame.intersection(screenClip)
            guard !rootClip.isEmpty else { cont.finish(); return stats }
            var frontier = [Node(el: window.element, depth: 0, clip: rootClip, parentRole: nil)]
            var seen = Set<AXElement>([window.element])
            var actionBudget = policy.maxActionQueries
            outer: while !frontier.isEmpty {
                if Task.isCancelled { break }
                if Date().timeIntervalSince(start) > policy.wallClock { stats.timedOut = true; break }
                if stats.visited >= policy.maxVisited { stats.timedOut = true; break }
                stats.levels += 1
                var levelFound: [ActionableElement] = []
                var next: [Node] = []
                let allowAction = actionBudget > 0
                let batch = frontier
                frontier.removeAll(keepingCapacity: true)
                let visits: [Visit] = await Self.visitLevel(batch, policy: policy, allowActionQuery: allowAction, scanner: self)
                for v in visits {
                    stats.visited += 1
                    if v.usedActionQuery { actionBudget -= 1; stats.actionQueries += 1 }
                    if v.pruned { stats.pruned += 1 }
                    if let f = v.found { levelFound.append(f) }
                    for c in v.children where !seen.contains(c.el) {
                        seen.insert(c.el)
                        if c.depth <= policy.maxDepth { next.append(c) }
                    }
                }
                if !levelFound.isEmpty {
                    stats.emitted += levelFound.count
                    cont.yield(levelFound)
                }
                if stats.emitted >= policy.maxHints { break outer }
                frontier = next
            }
            stats.elapsed = Date().timeIntervalSince(start)
            cont.finish()
            return stats
        }
        return (stream, task)
    }

    private static func visitLevel(_ nodes: [Node], policy: TraversalPolicy, allowActionQuery: Bool, scanner: ElementScanner?) async -> [Visit] {
        if policy.width <= 1 || nodes.count == 1 {
            var out: [Visit] = []
            for n in nodes { out.append(await visit(n, policy: policy, allowActionQuery: allowActionQuery, scanner: scanner)) }
            return out
        }
        var results = [Visit?](repeating: nil, count: nodes.count)
        await withTaskGroup(of: (Int, Visit).self) { group in
            var next = 0
            var inflight = 0
            func enqueue() {
                while inflight < policy.width && next < nodes.count {
                    let i = next; next += 1; inflight += 1
                    let n = nodes[i]
                    group.addTask { (i, await visit(n, policy: policy, allowActionQuery: allowActionQuery, scanner: scanner)) }
                }
            }
            enqueue()
            for await (i, v) in group {
                results[i] = v; inflight -= 1
                enqueue()
            }
        }
        return results.map { $0! }
    }

    private static func visit(_ n: Node, policy: TraversalPolicy, allowActionQuery: Bool, scanner: ElementScanner?) async -> Visit {
        var role: String?, subrole: String?, enabled: Bool?, frame: AXRect?
        var kids: [AXElement] = []
        if policy.naive {
            role = n.el.role; subrole = n.el.subrole; enabled = n.el.bool(.enabled); frame = n.el.frame()
            kids = n.el.children(.children, limit: policy.maxChildrenPerNode)
        } else {
            guard let b = AXBatch.batch(n.el) else { return Visit(found: nil, children: [], pruned: false, usedActionQuery: false) }
            role = b.role; subrole = b.subrole; enabled = b.enabled; frame = b.frame
            if frame == nil { frame = n.el.frame() }
            if let c = b.children {
                kids = c.count > policy.maxChildrenPerNode ? Array(c.prefix(policy.maxChildrenPerNode)) : c
            }
        }
        // Pruning with the validity guard: Chrome's AXWebArea and some Qt apps report zero frames on containers.
        var clip = n.clip
        var pruned = false
        if !policy.naive, let f = frame, f.isValid, let r = role, ActionableClassifier.clippingRoles.contains(r) {
            clip = n.clip.intersection(f)
            if clip.isEmpty { return Visit(found: nil, children: [], pruned: true, usedActionQuery: false) }
        }
        // Prefer AXVisibleChildren where the app implements it (cached per pid:role).
        if !policy.naive, let r = role, r == "AXTable" || r == "AXOutline" || r == "AXList" || r == "AXScrollArea", kids.count > 50 {
            let key = "\(n.el.pid):\(r)"
            let supported = await scanner?.visibleChildrenSupported(key: key, el: n.el)
            if supported == true {
                let vc = n.el.children(.visibleChildren, limit: policy.maxChildrenPerNode)
                if !vc.isEmpty { kids = vc; pruned = true }
            }
        }
        var verdict = ActionableClassifier.classify(role: role, subrole: subrole, enabled: enabled, frame: frame, clip: clip, parentRole: n.parentRole)
        var usedAQ = false
        if verdict == .needsActionQuery {
            if allowActionQuery {
                usedAQ = true
                verdict = n.el.actionNames().contains(kAXPressAction) ? .actionable : .notActionable
            } else { verdict = .notActionable }
        }
        var found: ActionableElement?
        if verdict == .actionable, let f = frame {
            let clipped = f.intersection(n.clip)
            if !clipped.isEmpty {
                found = ActionableElement(element: n.el, role: role ?? "?", subrole: subrole, frame: clipped, depth: n.depth)
            }
        }
        // Don't descend into text fields / menu bars; they are leaves for our purposes.
        if role == "AXTextField" || role == "AXTextArea" || role == "AXMenuBar" || role == "AXSlider" { kids = [] }
        let children = kids.map { Node(el: $0, depth: n.depth + 1, clip: clip, parentRole: role) }
        return Visit(found: found, children: children, pruned: pruned, usedActionQuery: usedAQ)
    }

    private func visibleChildrenSupported(key: String, el: AXElement) -> Bool {
        if let v = visibleChildrenSupport[key] { return v }
        let n = el.childCount(.visibleChildren)
        let total = el.childCount(.children)
        let ok = n > 0 && n < total
        visibleChildrenSupport[key] = ok
        return ok
    }

    /// Convenience: run to completion, return deduped elements + stats.
    public func scanAll(window: AXWindow, clip: AXRect) async -> ([ActionableElement], ScanStats) {
        let (stream, task) = scan(window: window, clip: clip)
        var all: [ActionableElement] = []
        for await batch in stream { all.append(contentsOf: batch) }
        let stats = await task.value
        return (ActionableClassifier.dedupe(all), stats)
    }
}
