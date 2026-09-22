import Foundation
import ApplicationServices

/// Paged child access. A virtualized list can report 20,000 children; never fetch blindly.
extension AXElement {
    public func childCount(_ attr: AXAttribute = .children) -> Int {
        var n: CFIndex = 0
        return AXUIElementGetAttributeValueCount(ref, attr.cf, &n) == .success ? n : 0
    }
    public func children(_ attr: AXAttribute = .children, limit: Int = 500) -> [AXElement] {
        let n = childCount(attr)
        guard n > 0 else { return [] }
        var out: CFArray?
        guard AXUIElementCopyAttributeValues(ref, attr.cf, 0, min(n, limit), &out) == .success,
              let arr = out as? [AnyObject] else { return [] }
        return arr.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? AXElement($0 as! AXUIElement) : nil }
    }
}
