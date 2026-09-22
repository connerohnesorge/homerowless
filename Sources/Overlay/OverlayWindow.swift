import AppKit

/// Borderless, non-activating, click-through panel above everything. One per screen.
public final class OverlayWindow: NSPanel {
    /// Single constant so the level is one-line-tunable. Above menu bar, Dock and native fullscreen.
    public static let overlayLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    public let canvas: HintCanvasView

    public init(screenFrame: CGRect) {
        canvas = HintCanvasView(frame: CGRect(origin: .zero, size: screenFrame.size))
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        contentView = canvas
    }
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
