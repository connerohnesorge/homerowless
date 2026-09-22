import AppKit
import ApplicationServices
import AXCore
import Discovery
import Geometry
import Hints
import Input
import Overlay
import Routing
import os

public struct CoordinatorConfig: Sendable {
    public var alphabet: [Character] = HintLabelGenerator.defaultAlphabet
    public var excludedBundleIDs: Set<String> = []
    public var dimNonMatching = false
    public var restoreCursorAfterClick = false
    public var scanTimeout: TimeInterval = 1.5
    public var hintIdleTimeout: TimeInterval = 8
    public var gridForcedBundleIDs: Set<String> = []
    public var grid = GridElementSource()
    public var scroll = ScrollSynthesizer.Config()
    public var compat = AppCompatConfig()
    public init() {}
}

/// Single writer of the ModeStore snapshot; performs all effects on the main actor. AX work is dispatched off-main.
@MainActor
public final class ModeCoordinator {
    public private(set) var state: ModeState = .idle
    public var config = CoordinatorConfig() { didSet { compat.config = config.compat; scroller.config = config.scroll } }
    public var onStateChange: ((ModeState) -> Void)?
    public var onToast: ((String) -> Void)?
    public var onMenuBarWarning: ((Bool) -> Void)?
    public var onOpenOnboarding: (() -> Void)?

    private let store: ModeStore
    private let tap: EventTapController
    private let overlay: OverlayWindowController
    private let scanner = ElementScanner()
    private let compat = AppCompat()
    private let scroller = ScrollSynthesizer()
    private let log = Logger(subsystem: "com.cohnesor.homerowless", category: "modes")

    private var scanTask: Task<Void, Never>?
    private var elements: [ActionableElement] = []
    private var hints: [Hint] = []
    private var markers: [AXRect] = []
    private var isGrid = false
    private var pendingG = false
    private var currentWindow: AXWindow?
    private var scrollArea: ScrollArea?
    private var savedCursor: CGPoint?
    private var timeoutTask: Task<Void, Never>?
    private var observer: AXObserverBox?

    public init(store: ModeStore, tap: EventTapController, overlay: OverlayWindowController) {
        self.store = store; self.tap = tap; self.overlay = overlay
        overlay.onScreensChanged = { [weak self] in self?.handle(.contextInvalidated) }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handle(.contextInvalidated)
                if let app { self?.warmUp(app) }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication { warmUp(front) }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.compat.forget(pid: app.processIdentifier)
            }
        }
    }

    /// Window-server truth first; NSWorkspace as fallback.
    private func frontApp() -> NSRunningApplication? {
        if let pid = AXElement.focusedApplicationPID(), let app = NSRunningApplication(processIdentifier: pid) { return app }
        return NSWorkspace.shared.frontmostApplication
    }

    // MARK: entry points
    public func clickHotkeyPressed() {
        Diag.log("click hotkey")
        let front = frontApp()
        let excluded = front?.bundleIdentifier.map { config.excludedBundleIDs.contains($0) } ?? false
        handle(.clickHotkey(trusted: AXTrust.isTrusted, secureInput: SecureInputMonitor.isActive, excluded: excluded))
    }
    public func scrollHotkeyPressed() {
        Diag.log("scroll hotkey")
        if case .scrolling = state { handle(.scrollHotkey(trusted: true, secureInput: false)); return }
        handle(.scrollHotkey(trusted: AXTrust.isTrusted, secureInput: SecureInputMonitor.isActive))
    }
    public func tapDisabled() { handle(.tapDisabled) }
    public func permissionChanged(trusted: Bool) { handle(trusted ? .permissionGranted : .permissionRevoked) }

    /// Called (async, main) for every tap event while a mode is active.
    public func keyInput(_ k: KeyInput) {
        switch k.kind {
        case .flags: handle(.flagsChanged(k.flags.rawValue))
        case .up:
            if case .scrolling = state, let c = k.character, "hjkl".contains(c) { scroller.stop() }
        case .down:
            if k.isRepeat, case .scrolling = state { return }
            handle(.key(k.character, keyCode: k.keyCode, flags: k.flags.rawValue))
        }
    }

    // MARK: machine
    public func handle(_ e: ModeEvent) {
        let (next, effects) = ModeMachine.transition(state, e, alphabet: Set(config.alphabet), pendingG: &pendingG)
        let changed = next != state
        if changed { Diag.log("\(state) -> \(next)") }
        state = next
        if changed { publishSnapshot(); onStateChange?(next) }
        for fx in effects { perform(fx) }
    }

    private func publishSnapshot() {
        var s = ModeSnapshot()
        s.alphabet = Set(config.alphabet)
        switch state {
        case .idle, .blocked: s.tag = .idle
        case .scanning: s.tag = .scanning
        case .hinting: s.tag = .hinting
        case .gridRefining: s.tag = .grid
        case .scrolling: s.tag = .scrolling
        }
        store.write(s)
    }

    private func perform(_ fx: ModeEffect) {
        switch fx {
        case .showOverlay: overlay.show()
        case .hideOverlay: overlay.hide(); timeoutTask?.cancel()
        case .enableTap: tap.setEnabled(true)
        case .disableTap: tap.setEnabled(false)
        case .reenableTap: tap.setEnabled(true); tap.setEnabled(false)
        case .startScan: startScan()
        case .cancelScan: scanTask?.cancel(); scanTask = nil; timeoutTask?.cancel()
        case .renderMarkers: overlay.render(.markers(markers))
        case .assignLabels: assignLabels()
        case .replayBuffer(let b): for c in b { handle(.key(c, keyCode: 0, flags: 0)) }
        case .filter(let prefix): filter(prefix)
        case .beep: NSSound.beep()
        case .toast(let m):
            onToast?(m == "Blocked by secure input" ? "Blocked by secure input: \(SecureInputMonitor.holderDescription)" : m)
        case .openOnboarding: onOpenOnboarding?()
        case .click(let i, let flags): click(index: i, flags: flags)
        case .gridSelect(let i):
            if let h = hints.first(where: { $0.index == i }) { overlay.render(.grid(hints: hints, typed: "", selected: h, nudge: .zero)) }
        case .gridNudge:
            if case .gridRefining(let sel, let nudge, _) = state, let h = hints.first(where: { $0.index == sel }) {
                overlay.render(.grid(hints: hints, typed: "", selected: h, nudge: nudge))
            }
        case .gridCommit(let i, let nudge, let flags):
            guard let h = hints.first(where: { $0.index == i }) else { return }
            let p = CGPoint(x: h.frame.center.x + nudge.x, y: h.frame.center.y + nudge.y)
            postClick(at: p, flags: flags, element: nil)
        case .resolveScrollArea: resolveScrollArea()
        case .parkCursor: break // done inside resolveScrollArea once the area is known
        case .restoreCursor:
            if let s = savedCursor { CGWarpMouseCursorPosition(s); CGAssociateMouseAndMouseCursorPosition(1) }
            savedCursor = nil; scrollArea = nil
        case .scroll(let cmd): scroll(cmd)
        case .log(let m):
            Diag.log(m)
            if SecureInputMonitor.isActive { onToast?("Blocked by secure input: \(SecureInputMonitor.holderDescription)") }
        case .menuBarWarning(let on): onMenuBarWarning?(on)
        }
    }

    /// Chromium builds its web accessibility tree lazily, on the first AX traffic, and the first pass returns a stub.
    /// Traverse it in the background as soon as a Chromium app comes to the front so the hotkey finds a warm tree.
    private var warmTask: Task<Void, Never>?
    private func warmUp(_ app: NSRunningApplication) {
        guard AppCompat.isChromiumLike(bundleURL: app.bundleURL) else { return }
        guard app.bundleIdentifier.map({ !config.excludedBundleIDs.contains($0) }) ?? true else { return }
        warmTask?.cancel()
        let layout = overlay.layout, scanner = self.scanner, pid = app.processIdentifier
        warmTask = Task.detached(priority: .utility) {
            for attempt in 0..<3 {
                if Task.isCancelled { return }
                let ax = AXApplication(pid: pid)
                guard let w = ax.focusedWindow(), let f = w.frame() else { return }
                let window = AXWindow(pid: pid, element: w, frame: layout.clamp(f))
                let (els, stats) = await scanner.scanAll(window: window, clip: layout.unionAX)
                Diag.log("warmup pid=\(pid) attempt=\(attempt) elements=\(els.count) visited=\(stats.visited)")
                if stats.visited >= 60 && els.count >= 5 { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    // MARK: scanning
    private func frontWindow() -> (AXWindow, NSRunningApplication)? {
        guard let app = frontApp() else { return nil }
        let ax = AXApplication(pid: app.processIdentifier)
        guard let w = ax.focusedWindow(), let f = w.frame() else { return nil }
        let clamped = overlay.layout.clamp(f)
        guard !clamped.isEmpty else { return nil }
        return (AXWindow(pid: app.processIdentifier, element: w, frame: clamped), app)
    }

    private func startScan() {
        elements = []; hints = []; markers = []; isGrid = false
        overlay.render(.empty)
        let layout = overlay.layout
        let cfg = config
        let scanner = self.scanner
        let compat = self.compat
        let front = frontApp()
        Diag.log("front app: \(front?.localizedName ?? "nil") (workspace says \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"))")
        let forceGrid = front?.bundleIdentifier.map { cfg.gridForcedBundleIDs.contains($0) } ?? false
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(cfg.scanTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handle(.scanTimeout)
        }
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            // All AX work happens here, off the main thread (R2).
            guard let front else { await self?.scanFinished([], grid: false, window: nil); return }
            let outcome = compat.prepare(pid: front.processIdentifier, bundleID: front.bundleIdentifier, bundleURL: front.bundleURL, voiceOverRunning: voiceOver)
            if outcome == .setManual { try? await Task.sleep(nanoseconds: UInt64(cfg.compat.settleMilliseconds) * 1_000_000) }
            let ax = AXApplication(pid: front.processIdentifier)
            guard let w = ax.focusedWindow(), let f = w.frame() else { await self?.scanFinished([], grid: false, window: nil); return }
            let clamped = layout.clamp(f)
            guard !clamped.isEmpty else { await self?.scanFinished([], grid: false, window: nil); return }
            let window = AXWindow(pid: front.processIdentifier, element: w, frame: clamped)
            if forceGrid {
                await self?.scanFinished(cfg.grid.cells(for: window.frame.intersection(layout.unionAX)), grid: true, window: window)
                return
            }
            let (stream, statsTask) = await scanner.scan(window: window, clip: layout.unionAX)
            var all: [ActionableElement] = []
            for await batch in stream {
                if Task.isCancelled { return }
                all.append(contentsOf: batch)
                let frames = all.map(\.frame)
                await self?.batchArrived(frames)
            }
            var stats = await statsTask.value
            // Settle-and-retry. Chromium builds its accessibility tree lazily after it sees AX traffic: the first pass
            // returns a stub (few elements) or collapsed 1pt frames. Re-scan a few times while that is the case.
            let chromium = AppCompat.isChromiumLike(bundleURL: front.bundleURL)
            Diag.log("first pass: chromium=\(chromium) visited=\(stats.visited) elements=\(all.count) collapsed=\(stats.collapsed)")
            if chromium && stats.visited < 60 { Diag.log("tree:\n" + TreeDump.brief(window.element)) }
            var attempt = 0
            while chromium, attempt < 4, !Task.isCancelled,
                  (stats.visited < 60 || all.count < 5 || stats.collapsed > max(3, all.count)) {
                attempt += 1
                Diag.log("chromium settle: attempt \(attempt), collapsed=\(stats.collapsed), elements=\(all.count)")
                try? await Task.sleep(nanoseconds: 250_000_000)
                let (s2, t2) = await scanner.scan(window: window, clip: layout.unionAX)
                all = []
                for await b in s2 { all.append(contentsOf: b) }
                stats = await t2.value
            }
            if Task.isCancelled { return }
            var deduped = ActionableClassifier.dedupe(all)
            let verdict = SourceQuality.evaluate(axElements: deduped, window: window.frame, shape: nil)
            var grid = false
            if verdict == .axUnusable { deduped = cfg.grid.cells(for: window.frame.intersection(layout.unionAX)); grid = true }
            let ms = Int(stats.elapsed * 1000)
            let count = deduped.count
            let vis = stats.visited
            let isGrid = grid
            await self?.scanFinished(deduped, grid: isGrid, window: window, note: "scan: \(count) elements, visited \(vis), \(ms)ms, grid=\(isGrid), collapsed=\(stats.collapsed), batchFailed=\(stats.batchFailed), err=\(stats.firstError), window=\(window.frame)")
        }
    }

    private func batchArrived(_ frames: [AXRect]) {
        guard case .scanning = state else { return }
        markers = frames
        handle(.batchArrived)
    }

    private func scanFinished(_ els: [ActionableElement], grid: Bool, window: AXWindow?, note: String? = nil) {
        if let note { Diag.log(note) }
        guard case .scanning = state else { return }
        timeoutTask?.cancel()
        elements = els; isGrid = grid; currentWindow = window
        handle(.finalBatch(count: els.count, isGrid: grid))
    }

    private func assignLabels() {
        hints = HintAssignment.assign(frames: elements.map(\.frame), alphabet: config.alphabet)
        render(typed: "")
        armIdleTimeout()
    }

    private func armIdleTimeout() {
        timeoutTask?.cancel()
        let t = config.hintIdleTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handle(.idleTimeout)
        }
    }

    private func render(typed: String) {
        if isGrid { overlay.render(.grid(hints: hints, typed: typed, selected: nil, nudge: .zero)) }
        else { overlay.render(.hints(hints: hints, typed: typed, dimNonMatching: config.dimNonMatching)) }
    }

    private func filter(_ prefix: String) {
        armIdleTimeout()
        guard case .hinting(let buf, let flags) = state else { return }
        if prefix.count < buf.count { render(typed: prefix); return }   // backspace
        let m = HintFilter.matches(hints, prefix: prefix)
        if m.isEmpty { handle(.hintResult(.none)); return }
        if let exact = m.first(where: { $0.label == prefix }) {
            if isGrid {
                // Enter refinement instead of clicking immediately.
                state = .gridRefining(selected: exact.index, nudge: .zero, flags: flags)
                publishSnapshot(); onStateChange?(state)
                perform(.gridSelect(exact.index))
                return
            }
            handle(.hintResult(.match(exact.index)))
            return
        }
        render(typed: prefix)
        handle(.hintResult(.partial))
    }

    // MARK: click
    private func click(index: Int, flags: UInt64) {
        guard elements.indices.contains(index) else { return }
        let el = elements[index]
        let clip = overlay.layout.unionAX
        let target = el.frame.intersection(currentWindow?.frame ?? el.frame).intersection(clip)
        if target.isEmpty, let ax = el.element {
            Task.detached { _ = ClickSynthesizer.axPress(ax) }
            return
        }
        postClick(at: target.center, flags: flags, element: el.element)
    }

    private func postClick(at p: CGPoint, flags: UInt64, element: AXElement?) {
        var o = ClickOptions()
        let f = CGEventFlags(rawValue: flags)
        o.modifiers = f
        o.restoreCursor = config.restoreCursorAfterClick
        // Let one runloop turn pass so the overlay is actually gone before the click lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            ClickSynthesizer.click(at: p, options: o)
        }
    }

    // MARK: scroll
    private func resolveScrollArea() {
        savedCursor = CGEvent(source: nil)?.location
        let layout = overlay.layout
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let app = await self?.frontApp() else { return }
            let ax = AXApplication(pid: app.processIdentifier)
            guard let w = ax.focusedWindow(), let f = w.frame() else { return }
            let window = AXWindow(pid: app.processIdentifier, element: w, frame: layout.clamp(f))
            var areas = ScrollAreaFinder.find(window: window, clip: layout.unionAX)
            // Prefer the area under the cursor, else the largest.
            let cursor = CGEvent(source: nil)?.location ?? .zero
            areas.sort { $0.frame.area > $1.frame.area }
            let chosen = areas.first(where: { $0.frame.contains(cursor) }) ?? areas.first
                ?? ScrollArea(element: w, frame: window.frame, role: "AXWindow", verticalScrollBar: nil)
            await self?.scrollAreaResolved(chosen)
        }
    }
    private func scrollAreaResolved(_ a: ScrollArea) {
        guard case .scrolling = state else { return }
        scrollArea = a
        scroller.park(at: a.frame.center)
        overlay.render(.scroll(area: a.frame, badge: "SCROLL  hjkl · d/u · gg/G · esc"))
    }
    private func scroll(_ c: ScrollCommand) {
        let h = Double(scrollArea?.frame.height ?? 800)
        switch c {
        case .left: scroller.setVelocity(dx: 1, dy: 0)
        case .right: scroller.setVelocity(dx: -1, dy: 0)
        case .up: scroller.setVelocity(dx: 0, dy: 1)
        case .down: scroller.setVelocity(dx: 0, dy: -1)
        case .halfDown: scroller.burst(dy: -1, height: h)
        case .halfUp: scroller.burst(dy: 1, height: h)
        case .top, .bottom:
            let top = c == .top, area = scrollArea
            Task.detached { [scroller] in scroller.jump(toTop: top, area: area?.element, scrollBar: area?.verticalScrollBar) }
        case .stop: scroller.stop()
        }
    }
}
