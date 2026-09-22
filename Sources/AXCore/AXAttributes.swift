import Foundation
import ApplicationServices
import Geometry

/// Single-attribute accessors. Each is one synchronous Mach round trip serviced on the *target app's* main thread.
/// Never call from the main thread of this process.
extension AXElement {
    public func copy(_ attr: AXAttribute) -> CFTypeRef? {
        var out: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(ref, attr.cf, &out)
        return err == .success ? out : nil
    }
    public func copyRaw(_ attr: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(ref, attr as CFString, &out) == .success ? out : nil
    }
    public func string(_ a: AXAttribute) -> String? { AXUnwrap.string(copy(a)) }
    public func bool(_ a: AXAttribute) -> Bool? { AXUnwrap.bool(copy(a)) }
    public func double(_ a: AXAttribute) -> Double? { AXUnwrap.double(copy(a)) }
    public func element(_ a: AXAttribute) -> AXElement? { AXUnwrap.element(copy(a)) }
    public var role: String? { string(.role) }
    public var subrole: String? { string(.subrole) }
    public var parent: AXElement? { element(.parent) }

    /// `AXFrame` first (one round trip); fall back to AXPosition + AXSize.
    public func frame() -> AXRect? {
        if let r = AXUnwrap.rect(copy(.frame)) { return r }
        guard let p = AXUnwrap.point(copy(.position)), let s = AXUnwrap.size(copy(.size)) else { return nil }
        return AXRect(origin: p, size: s)
    }

    @discardableResult
    public func set(_ attr: AXAttribute, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(ref, attr.cf, value)
    }
    public func set(_ attr: AXAttribute, bool: Bool) -> AXError { set(attr, bool ? kCFBooleanTrue : kCFBooleanFalse) }
    public func set(_ attr: AXAttribute, double: Double) -> AXError { set(attr, double as CFNumber) }

    public func actionNames() -> [String] {
        var out: CFArray?
        guard AXUIElementCopyActionNames(ref, &out) == .success, let a = out as? [String] else { return [] }
        return a
    }
    @discardableResult
    public func perform(action: String) -> AXError { AXUIElementPerformAction(ref, action as CFString) }
    public func press() -> AXError { perform(action: kAXPressAction) }

    public func isAttributeSettable(_ attr: AXAttribute) -> Bool {
        var s = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(ref, attr.cf, &s) == .success && s.boolValue
    }
    public func attributeNames() -> [String] {
        var out: CFArray?
        guard AXUIElementCopyAttributeNames(ref, &out) == .success, let a = out as? [String] else { return [] }
        return a
    }

    /// Element at a global AX-space point, scoped to an app element or system-wide.
    public func elementAt(_ p: CGPoint) -> AXElement? {
        var out: AXUIElement?
        guard AXUIElementCopyElementAtPosition(ref, Float(p.x), Float(p.y), &out) == .success, let o = out else { return nil }
        return AXElement(o)
    }
}

public enum AXTimeouts {
    public static let defaultSeconds: Float = 0.25
    /// Sets the process-global default (system-wide element) and is also applied per app element by callers.
    /// A timeout of 0.0 means "restore the default (~6s)", not "no timeout".
    public static func installGlobal(_ seconds: Float = defaultSeconds) {
        AXUIElementSetMessagingTimeout(AXElement.systemWide.ref, seconds)
    }
    public static func apply(to e: AXElement, seconds: Float = defaultSeconds) {
        AXUIElementSetMessagingTimeout(e.ref, seconds)
    }
}
