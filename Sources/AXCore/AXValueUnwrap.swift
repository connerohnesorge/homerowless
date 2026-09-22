import Foundation
import ApplicationServices
import Geometry

/// Turns a CFTypeRef from the AX API into a plain Swift value.
public enum AXUnwrap {
    public static func string(_ v: CFTypeRef?) -> String? {
        guard let v, CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
        return v as? String
    }
    public static func bool(_ v: CFTypeRef?) -> Bool? {
        guard let v else { return nil }
        if CFGetTypeID(v) == CFBooleanGetTypeID() { return CFBooleanGetValue((v as! CFBoolean)) }
        if CFGetTypeID(v) == CFNumberGetTypeID() { return (v as! NSNumber).boolValue }
        return nil
    }
    public static func double(_ v: CFTypeRef?) -> Double? {
        guard let v, CFGetTypeID(v) == CFNumberGetTypeID() else { return nil }
        return (v as! NSNumber).doubleValue
    }
    public static func element(_ v: CFTypeRef?) -> AXElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXElement(v as! AXUIElement)
    }
    public static func elements(_ v: CFTypeRef?) -> [AXElement]? {
        guard let v, CFGetTypeID(v) == CFArrayGetTypeID() else { return nil }
        let arr = v as! [AnyObject]
        return arr.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? AXElement($0 as! AXUIElement) : nil }
    }
    public static func rect(_ v: CFTypeRef?) -> AXRect? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let av = v as! AXValue
        guard AXValueGetType(av) == .cgRect else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(av, .cgRect, &r) else { return nil }
        return AXRect(axSpace: r)
    }
    public static func point(_ v: CFTypeRef?) -> CGPoint? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let av = v as! AXValue
        guard AXValueGetType(av) == .cgPoint else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue(av, .cgPoint, &p) else { return nil }
        return p
    }
    public static func size(_ v: CFTypeRef?) -> CGSize? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let av = v as! AXValue
        guard AXValueGetType(av) == .cgSize else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue(av, .cgSize, &s) else { return nil }
        return s
    }
    /// True when the value is an AXValue of type `.axError` (the placeholder used by CopyMultipleAttributeValues).
    public static func isError(_ v: CFTypeRef?) -> Bool {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return false }
        return AXValueGetType(v as! AXValue) == .axError
    }
}
