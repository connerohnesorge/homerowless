import AppKit
import ServiceManagement

@MainActor
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    var onDebugHints: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOnboarding: (() -> Void)?
    var onForceGrid: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    init() {
        setWarning(false)
        let m = NSMenu()
        statusLine.isEnabled = false
        m.addItem(statusLine)
        m.addItem(.separator())
        m.addItem(withTitle: "Click mode  ⌘⇧F", action: nil, keyEquivalent: "").isEnabled = false
        m.addItem(withTitle: "Scroll mode  ⌘J", action: nil, keyEquivalent: "").isEnabled = false
        m.addItem(.separator())
        m.addItem(item(title: "Open config.json", #selector(openConfig)))
        m.addItem(item(title: "Accessibility permission…", #selector(onboarding)))
        let login = item(title: "Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        m.addItem(item(title: "Check for Updates…", #selector(checkForUpdates)))
        m.addItem(.separator())
        m.addItem(item(title: "Debug: render synthetic label grid (3s)", #selector(debugHints)))
        m.addItem(item(title: "Debug: force grid on next activation", #selector(forceGrid)))
        m.addItem(.separator())
        m.addItem(item(title: "Quit homerowless", #selector(quit), key: "q"))
        item.menu = m
    }
    private func item(title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; return i
    }
    func setStatus(_ s: String) { statusLine.title = s }
    func setWarning(_ on: Bool) {
        let name = on ? "exclamationmark.triangle" : "keyboard"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "homerowless")
        item.button?.toolTip = on ? "homerowless: Accessibility not granted" : "homerowless"
    }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func onboarding() { onOnboarding?() }
    @objc private func debugHints() { onDebugHints?() }
    @objc private func forceGrid() { onForceGrid?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister(); sender.state = .off }
            else { try SMAppService.mainApp.register(); sender.state = .on }
        } catch { NSSound.beep() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
