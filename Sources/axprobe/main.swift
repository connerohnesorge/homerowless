import Foundation
import AppKit
import ApplicationServices
import AXCore
import Geometry
import Discovery

// axprobe — dev CLI. Inherits the terminal's Accessibility grant. Links no AppKit UI.
// usage: axprobe dump|scan|bench|compat|scrolls [--front | --app NAME | --pid N] [--repeat N] [--naive] [--apps A,B,C] [--depth N]

struct Args {
    var cmd = "scan"
    var appName: String?
    var pid: pid_t?
    var repeatN = 1
    var naive = false
    var apps: [String] = []
    var maxDepth = 8
    init() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
        if let c = it.next() { cmd = c }
        while let a = it.next() {
            switch a {
            case "--front": break
            case "--app": appName = it.next()
            case "--pid": pid = pid_t(it.next() ?? "") ?? nil
            case "--repeat": repeatN = Int(it.next() ?? "1") ?? 1
            case "--naive": naive = true
            case "--apps": apps = (it.next() ?? "").split(separator: ",").map(String.init)
            case "--depth": maxDepth = Int(it.next() ?? "8") ?? 8
            default: FileHandle.standardError.write("unknown arg \(a)\n".data(using: .utf8)!)
            }
        }
    }
}

func layout() -> ScreenLayout {
    let screens = NSScreen.screens
    return ScreenLayout(ids: screens.map { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 },
                        nsFrames: screens.map { $0.frame })
}

func resolveApp(_ a: Args) -> NSRunningApplication? {
    if let pid = a.pid { return NSRunningApplication(processIdentifier: pid) }
    if let name = a.appName {
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == name || $0.bundleIdentifier == name }
    }
    // --front: the frontmost app that isn't Terminal running us.
    return NSWorkspace.shared.frontmostApplication
}

func focusedWindow(_ app: NSRunningApplication) -> AXWindow? {
    let ax = AXApplication(pid: app.processIdentifier)
    guard let w = ax.focusedWindow(), let f = w.frame() else { return nil }
    let l = layout()
    return AXWindow(pid: app.processIdentifier, element: w, frame: l.clamp(f))
}

func pct(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted(); guard !s.isEmpty else { return 0 }
    return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
}

func dump(_ w: AXWindow, maxDepth: Int) {
    func rec(_ e: AXElement, _ d: Int) {
        guard d <= maxDepth else { return }
        let b = AXBatch.batch(e)
        let role = b?.role ?? "?"
        let sub = b?.subrole.map { " (\($0))" } ?? ""
        let f = b?.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "no-frame"
        let title = b?.title.map { " \"\($0.prefix(30))\"" } ?? ""
        let n = b?.children?.count ?? 0
        print(String(repeating: "  ", count: d) + "\(role)\(sub) [\(f)] kids=\(n)\(title)")
        for c in (b?.children ?? []).prefix(60) { rec(c, d + 1) }
    }
    rec(w.element, 0)
}

func runScan(_ w: AXWindow, naive: Bool, repeatN: Int, quiet: Bool = false) async -> (count: Int, p50: Double, p95: Double, max: Double, stats: ScanStats) {
    let policy: TraversalPolicy = naive ? .naive : .default
    let scanner = ElementScanner(policy: policy)
    let l = layout()
    var times: [Double] = []
    var lastCount = 0
    var lastStats = ScanStats()
    for _ in 0..<repeatN {
        let t = Date()
        let (els, stats) = await scanner.scanAll(window: w, clip: l.unionAX)
        times.append(Date().timeIntervalSince(t) * 1000)
        lastCount = els.count; lastStats = stats
        if !quiet && repeatN == 1 {
            for e in els.prefix(400) {
                print("\(e.role)\(e.subrole.map { "/" + $0 } ?? "") d=\(e.depth) [\(Int(e.frame.minX)),\(Int(e.frame.minY)) \(Int(e.frame.width))x\(Int(e.frame.height))]")
            }
        }
    }
    return (lastCount, pct(times, 0.5), pct(times, 0.95), times.max() ?? 0, lastStats)
}

let args = Args()
AXTimeouts.installGlobal()
guard AXIsProcessTrusted() else { print("Accessibility not granted to this terminal"); exit(2) }

let sema = DispatchSemaphore(value: 0)
Task.detached {
    defer { sema.signal() }
    switch args.cmd {
    case "dump":
        guard let app = resolveApp(args), let w = focusedWindow(app) else { print("no focused window"); return }
        print("# \(app.localizedName ?? "?") pid=\(app.processIdentifier) window=\(w.frame)")
        dump(w, maxDepth: args.maxDepth)
    case "scan":
        guard let app = resolveApp(args), let w = focusedWindow(app) else { print("no focused window"); return }
        let r = await runScan(w, naive: args.naive, repeatN: args.repeatN)
        print("# \(app.localizedName ?? "?") elements=\(r.count) visited=\(r.stats.visited) pruned=\(r.stats.pruned) aq=\(r.stats.actionQueries) levels=\(r.stats.levels) timedOut=\(r.stats.timedOut) collapsed=\(r.stats.collapsed) batchFailed=\(r.stats.batchFailed) err=\(r.stats.firstError)")
        print(String(format: "# p50=%.1fms p95=%.1fms max=%.1fms (n=%d, %@)", r.p50, r.p95, r.max, args.repeatN, args.naive ? "naive" : "optimized"))
    case "bench":
        let names = args.apps.isEmpty ? ["Finder", "Safari", "Mail", "Slack", "Code", "Xcode", "Google Chrome"] : args.apps
        let compat = AppCompat()
        print("| app | mode | elements | visited | p50 ms | p95 ms | max ms | timedOut |")
        print("|---|---|---|---|---|---|---|---|")
        for n in names {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == n || $0.bundleIdentifier == n }) else {
                print("| \(n) | — | not running | | | | | |"); continue
            }
            if !args.naive {
                let o = compat.prepare(pid: app.processIdentifier, bundleID: app.bundleIdentifier, bundleURL: app.bundleURL, voiceOverRunning: false)
                if o == .setManual { try? await Task.sleep(nanoseconds: 200_000_000) }
            }
            guard let w = focusedWindow(app) else { print("| \(n) | — | no window | | | | | |"); continue }
            let r = await runScan(w, naive: args.naive, repeatN: max(args.repeatN, 5), quiet: true)
            print(String(format: "| %@ | %@ | %d | %d | %.1f | %.1f | %.1f | %@ |", n, args.naive ? "naive" : "opt", r.count, r.stats.visited, r.p50, r.p95, r.max, r.stats.timedOut ? "yes" : "no"))
        }
    case "compat":
        guard let app = resolveApp(args) else { print("no app"); return }
        let chromium = AppCompat.isChromiumLike(bundleURL: app.bundleURL)
        print("# \(app.localizedName ?? "?") bundle=\(app.bundleIdentifier ?? "?") chromiumLike=\(chromium)")
        guard let w = focusedWindow(app) else { print("no focused window"); return }
        let before = await runScan(w, naive: false, repeatN: 3, quiet: true)
        print(String(format: "before AXManualAccessibility: elements=%d visited=%d p50=%.1fms", before.count, before.stats.visited, before.p50))
        let compat = AppCompat()
        let o = compat.prepare(pid: app.processIdentifier, bundleID: app.bundleIdentifier, bundleURL: app.bundleURL, voiceOverRunning: false)
        print("prepare -> \(o)")
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard let w2 = focusedWindow(app) else { return }
        let after = await runScan(w2, naive: false, repeatN: 3, quiet: true)
        print(String(format: "after:  elements=%d visited=%d p50=%.1fms", after.count, after.stats.visited, after.p50))
    case "scrolls":
        guard let app = resolveApp(args), let w = focusedWindow(app) else { print("no focused window"); return }
        let t = Date()
        let areas = ScrollAreaFinder.find(window: w, clip: layout().unionAX)
        print(String(format: "# %d scroll areas in %.1fms", areas.count, Date().timeIntervalSince(t) * 1000))
        for a in areas { print("\(a.role) [\(Int(a.frame.minX)),\(Int(a.frame.minY)) \(Int(a.frame.width))x\(Int(a.frame.height))] vbar=\(a.verticalScrollBar != nil)") }
    default:
        print("usage: axprobe dump|scan|bench|compat|scrolls [--front|--app NAME|--pid N] [--repeat N] [--naive] [--apps A,B] [--depth N]")
    }
}
sema.wait()
