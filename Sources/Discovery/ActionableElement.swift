import Foundation
import AXCore
import Geometry

/// A clickable thing found on screen. Plain data; the AXElement is retained for the AXPress fallback.
public struct ActionableElement: Hashable, @unchecked Sendable {
    public let element: AXElement?
    public let role: String
    public let subrole: String?
    /// Frame in AX space, already clipped to window ∩ screens.
    public let frame: AXRect
    public let depth: Int
    public var title: String?

    public init(element: AXElement?, role: String, subrole: String? = nil, frame: AXRect, depth: Int, title: String? = nil) {
        self.element = element; self.role = role; self.subrole = subrole; self.frame = frame; self.depth = depth; self.title = title
    }
}
