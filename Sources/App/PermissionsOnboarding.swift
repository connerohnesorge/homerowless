import AppKit
import AXCore

/// Plain NSWindow (survives the focus change to System Settings). Polls AXIsProcessTrusted at 1 Hz only while visible.
@MainActor
final class PermissionsOnboarding {
    private var window: NSWindow?
    private var timer: Timer?
    var onGranted: (() -> Void)?

    func show() {
        if window == nil { build() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }
    func poll() {
        guard AXTrust.isTrusted else { return }
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
        onGranted?()
    }
    var isVisible: Bool { window?.isVisible ?? false }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 230), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "homerowless needs Accessibility"
        w.isReleasedWhenClosed = false
        let v = NSView(frame: w.contentView!.bounds)
        let label = NSTextField(wrappingLabelWithString:
            "homerowless reads on-screen controls through the Accessibility API and consumes keystrokes only while hints are visible. It never reads pixels.\n\nGrant access in System Settings → Privacy & Security → Accessibility, then this window closes on its own.")
        label.frame = NSRect(x: 20, y: 90, width: 420, height: 120)
        let prompt = NSButton(title: "Request Access", target: self, action: #selector(request))
        prompt.frame = NSRect(x: 20, y: 30, width: 150, height: 32)
        let open = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        open.frame = NSRect(x: 180, y: 30, width: 190, height: 32)
        open.keyEquivalent = "\r"
        v.addSubview(label); v.addSubview(prompt); v.addSubview(open)
        w.contentView = v
        window = w
    }
    @objc private func request() { AXTrust.requestPrompt() }
    @objc private func openSettings() { NSWorkspace.shared.open(AXTrust.settingsDeepLink) }
}
