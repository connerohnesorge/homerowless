import Foundation
import ApplicationServices
import Geometry

/// App-level helpers.
public struct AXApplication: Sendable {
    public let pid: pid_t
    public let element: AXElement
    public init(pid: pid_t, timeout: Float = AXTimeouts.defaultSeconds) {
        self.pid = pid
        element = .application(pid: pid)
        AXTimeouts.apply(to: element, seconds: timeout)
    }
    public func focusedWindow() -> AXElement? {
        element.element(.focusedWindow) ?? element.element(.mainWindow) ?? element.children(.windows, limit: 1).first
    }
    public func windows() -> [AXElement] { element.children(.windows, limit: 64) }
}

/// A window plus its (clamped) frame, the unit the scanner and sources operate on.
public struct AXWindow: Hashable, @unchecked Sendable {
    public let pid: pid_t
    public let element: AXElement
    public let frame: AXRect
    public init(pid: pid_t, element: AXElement, frame: AXRect) { self.pid = pid; self.element = element; self.frame = frame }
}
