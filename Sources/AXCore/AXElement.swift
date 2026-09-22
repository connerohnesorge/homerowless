import Foundation
import ApplicationServices

/// Hashable wrapper so the same widget reached via two paths dedupes. `===` doesn't work on AXUIElement.
/// `@unchecked Sendable` is honest: the AX API is documented as callable from any thread.
public struct AXElement: Hashable, @unchecked Sendable {
    public let ref: AXUIElement
    public init(_ ref: AXUIElement) { self.ref = ref }
    public static func == (a: AXElement, b: AXElement) -> Bool { CFEqual(a.ref, b.ref) }
    public func hash(into h: inout Hasher) { h.combine(CFHash(ref)) }

    public var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(ref, &p)
        return p
    }
    public static func application(pid: pid_t) -> AXElement { AXElement(AXUIElementCreateApplication(pid)) }
    public static let systemWide = AXElement(AXUIElementCreateSystemWide())
}

/// Attribute names. Several (`AXFrame`, `AXManualAccessibility`, `AXEnhancedUserInterface`, `AXScrollToVisible`)
/// are not in any public header of MacOSX27.0.sdk and are passed as raw strings.
public enum AXAttribute: String, CaseIterable, Sendable {
    case role = "AXRole"
    case subrole = "AXSubrole"
    case frame = "AXFrame"
    case position = "AXPosition"
    case size = "AXSize"
    case enabled = "AXEnabled"
    case children = "AXChildren"
    case visibleChildren = "AXVisibleChildren"
    case title = "AXTitle"
    case description = "AXDescription"
    case value = "AXValue"
    case focusedWindow = "AXFocusedWindow"
    case focusedUIElement = "AXFocusedUIElement"
    case windows = "AXWindows"
    case mainWindow = "AXMainWindow"
    case parent = "AXParent"
    case verticalScrollBar = "AXVerticalScrollBar"
    case horizontalScrollBar = "AXHorizontalScrollBar"
    case manualAccessibility = "AXManualAccessibility"
    case enhancedUserInterface = "AXEnhancedUserInterface"
    case minimized = "AXMinimized"
    case hidden = "AXHidden"
    case url = "AXURL"
    case identifier = "AXIdentifier"
    case orientation = "AXOrientation"

    public var cf: CFString { rawValue as CFString }
}

public enum AXError2: Error, Sendable, Equatable {
    case ax(AXError)
    case wrongType
}

extension AXError {
    public var isTimeout: Bool { self == .cannotComplete }
}
