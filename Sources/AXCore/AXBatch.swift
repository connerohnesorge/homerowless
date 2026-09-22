import Foundation
import ApplicationServices
import Geometry

/// One IPC round trip for several attributes via `AXUIElementCopyMultipleAttributeValues`.
/// Options 0 (NOT StopOnError) so a missing attribute yields an `.axError` placeholder instead of aborting the batch.
public struct AXBatchResult: Sendable {
    public var values: [AXAttribute: AnyCF] = [:]
    public subscript(a: AXAttribute) -> CFTypeRef? { values[a]?.value }
    public var role: String? { AXUnwrap.string(self[.role]) }
    public var subrole: String? { AXUnwrap.string(self[.subrole]) }
    public var enabled: Bool? { AXUnwrap.bool(self[.enabled]) }
    public var frame: AXRect? { AXUnwrap.rect(self[.frame]) }
    public var children: [AXElement]? { AXUnwrap.elements(self[.children]) }
    public var title: String? { AXUnwrap.string(self[.title]) }
    public var description: String? { AXUnwrap.string(self[.description]) }
}

/// Sendable box for a CF value. CF types are immutable once returned from AX.
public struct AnyCF: @unchecked Sendable {
    public let value: CFTypeRef
    public init(_ v: CFTypeRef) { value = v }
}

public enum AXBatch {
    public static let probeAttributes: [AXAttribute] = [.role, .subrole, .frame, .enabled, .children]

    public static func batch(_ e: AXElement, _ attrs: [AXAttribute] = probeAttributes) -> AXBatchResult? {
        let names = attrs.map { $0.cf } as CFArray
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(e.ref, names, AXCopyMultipleAttributeOptions(rawValue: 0), &out)
        guard err == .success, let arr = out as? [AnyObject], arr.count == attrs.count else { return nil }
        var r = AXBatchResult()
        for (i, a) in attrs.enumerated() {
            let v = arr[i] as CFTypeRef
            if AXUnwrap.isError(v) { continue }
            r.values[a] = AnyCF(v)
        }
        return r
    }
}
