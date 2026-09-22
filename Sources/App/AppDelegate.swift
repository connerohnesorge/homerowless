import AppKit
import AXCore
import Geometry
import Hints
import Input
import Modes
import Overlay
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.cohnesor.homerowless", category: "app")
    private var menu: MenuBarController!
    private var overlay: OverlayWindowController!
    private var coordinator: ModeCoordinator!
    private let store = ModeStore()
    private let tap = EventTapController()
    private let translator = KeyTranslator()
    private let hotkeys = HotkeyManager()
    private let onboarding = PermissionsOnboarding()
    private var configStore: ConfigStore!
    private var permissionTimer: Timer?
    private var lastTrusted = false
    private var toastTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // LaunchServices caches LSUIElement by path+mtime; belt and braces
        AXTimeouts.installGlobal()
        menu = MenuBarController()
        overlay = OverlayWindowController()      // pre-create panels now that NSApplication has finished launching
        coordinator = ModeCoordinator(store: store, tap: tap, overlay: overlay)
        configStore = ConfigStore()
        applyConfig(configStore.config)
        configStore.onChange = { [weak self] c in
            guard let self, case .idle = self.coordinator.state else { return }   // reload only takes effect in idle
            self.applyConfig(c)
        }
        configStore.onError = { [weak self] m in self?.toast(m) }

        coordinator.onStateChange = { [weak self] s in self?.menu.setStatus(Self.describe(s)) }
        coordinator.onToast = { [weak self] m in self?.toast(m) }
        coordinator.onMenuBarWarning = { [weak self] on in self?.menu.setWarning(on) }
        coordinator.onOpenOnboarding = { [weak self] in self?.onboarding.show() }
        onboarding.onGranted = { [weak self] in self?.permissionBecameTrusted() }

        menu.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.configStore.url)
        }
        menu.onOnboarding = { [weak self] in self?.onboarding.show() }
        menu.onDebugHints = { [weak self] in self?.debugHints() }
        menu.onForceGrid = { [weak self] in
            guard let self else { return }
            var c = self.coordinator.config
            if let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { c.gridForcedBundleIDs.insert(b) }
            self.coordinator.config = c
        }

        lastTrusted = AXTrust.isTrusted
        if lastTrusted { startInput() } else { onboarding.show(); menu.setWarning(true); coordinator.handle(.permissionRevoked) }

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
        // Cheap 5s watchdog for revocation (there is no TCC notification).
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
        Diag.log("launched; trusted=\(lastTrusted) tap=\(tap.isCreated)")
    }

    private func startInput() {
        let ok = tap.start(store: store, translator: translator,
                           sink: { [weak self] k in DispatchQueue.main.async { self?.coordinator.keyInput(k) } },
                           onDisabled: { [weak self] why in Diag.log("tap disabled by \(why)"); DispatchQueue.main.async { self?.coordinator.tapDisabled() } })
        Diag.log("tap start ok=\(ok)")
        if !ok { Diag.log("tap creation failed despite trust"); lastTrusted = false; onboarding.show(); menu.setWarning(true); return }
        registerHotkeys(configStore.config)
        menu.setWarning(false)
    }

    private func registerHotkeys(_ c: Config) {
        hotkeys.unregisterAll()
        if let hk = Hotkey(c.clickHotkey) {
            hotkeys.register(hk) { DispatchQueue.main.async { [weak self] in self?.coordinator.clickHotkeyPressed() } }
        } else { toast("Bad clickHotkey \"\(c.clickHotkey)\"") }
        coordinator.hotkeyKeyCodes = Set([Hotkey(c.clickHotkey), Hotkey(c.scrollHotkey)].compactMap { $0 }.map { UInt16($0.keyCode) })
        Diag.log("hotkeys registered: \(c.clickHotkey), \(c.scrollHotkey)")
        if let hk = Hotkey(c.scrollHotkey) {
            hotkeys.register(hk) { DispatchQueue.main.async { [weak self] in self?.coordinator.scrollHotkeyPressed() } }
        } else { toast("Bad scrollHotkey \"\(c.scrollHotkey)\"") }
    }

    private func applyConfig(_ c: Config) {
        coordinator.config = c.coordinatorConfig
        overlay.appearance = c.hintAppearance
        if tap.isCreated { registerHotkeys(c) }
    }

    private func checkPermission() {
        let t = AXTrust.isTrusted
        guard t != lastTrusted else { return }
        lastTrusted = t
        if t { permissionBecameTrusted() } else { coordinator.permissionChanged(trusted: false); tap.stop(); hotkeys.unregisterAll(); onboarding.show() }
    }
    private func permissionBecameTrusted() {
        lastTrusted = true
        startInput()
        coordinator.permissionChanged(trusted: true)
    }

    private func toast(_ m: String) {
        Diag.log("toast: \(m)")
        menu.setStatus(m)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.menu.setStatus(Self.describe(self.coordinator.state))
        }
    }

    /// M4 harness: render 400 labelled hints across all displays, no click.
    private func debugHints() {
        let layout = overlay.layout
        var frames: [AXRect] = []
        for s in layout.screens {
            let f = s.axFrame
            let cols = 20, rows = 400 / (20 * layout.screens.count)
            for r in 0..<rows { for c in 0..<cols {
                frames.append(AXRect(x: f.minX + CGFloat(c) * f.width / CGFloat(cols) + 10, y: f.minY + CGFloat(r) * f.height / CGFloat(rows) + 40, width: 60, height: 20))
            } }
        }
        let hints = HintAssignment.assign(frames: frames, alphabet: coordinator.config.alphabet)
        overlay.render(.hints(hints: hints, typed: "", dimNonMatching: false))
        overlay.show()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.overlay.hide()
        }
    }

    static func describe(_ s: ModeState) -> String {
        switch s {
        case .idle: return "Idle"
        case .blocked: return "Blocked: Accessibility not granted"
        case .scanning: return "Scanning…"
        case .hinting(let b, _): return b.isEmpty ? "Hints shown" : "Hints: \(b)"
        case .gridRefining: return "Grid: arrows nudge, ⏎ clicks"
        case .scrolling: return "Scroll mode"
        }
    }
}
