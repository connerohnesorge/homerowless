import AppKit
import Geometry
import Hints

/// Owns one OverlayWindow per NSScreen; pre-created after launch and reused.
@MainActor
public final class OverlayWindowController {
    private var windows: [OverlayWindow] = []
    public private(set) var layout: ScreenLayout
    public var appearance = HintAppearance() { didSet { windows.forEach { $0.canvas.hintStyle = appearance } } }
    private var visible = false

    public init() {
        layout = Self.currentLayout()
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    public static func currentLayout() -> ScreenLayout {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return ScreenLayout(ids: [0], nsFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)]) }
        return ScreenLayout(ids: screens.map { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 },
                            nsFrames: screens.map { $0.frame })
    }

    public var onScreensChanged: (() -> Void)?

    private func screensChanged() {
        layout = Self.currentLayout()
        rebuild()
        onScreensChanged?()
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = layout.screens.map { s in
            let w = OverlayWindow(screenFrame: s.nsFrame.rect)
            w.canvas.converter = layout.converter
            w.canvas.screenNS = s.nsFrame
            w.canvas.hintStyle = appearance
            return w
        }
    }

    public func render(_ model: RenderModel) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for w in windows { w.canvas.model = model }
        CATransaction.commit()
    }

    public func show() {
        guard !visible else { return }
        visible = true
        for w in windows { w.orderFrontRegardless() }   // never makeKeyAndOrderFront
    }
    public func hide() {
        guard visible else { return }
        visible = false
        for w in windows { w.canvas.model = .empty; w.orderOut(nil) }
    }
    public var isVisible: Bool { visible }
}
