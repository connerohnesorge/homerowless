import Foundation
import Geometry
import Hints

/// What the canvas draws. Built on the main actor by the coordinator; immutable snapshot for drawing.
public enum RenderModel: Sendable, Equatable {
    case empty
    /// Streaming: positions known, labels not yet assigned (C2).
    case markers([AXRect])
    case hints(hints: [Hint], typed: String, dimNonMatching: Bool)
    case grid(hints: [Hint], typed: String, selected: Hint?, nudge: CGPoint)
    case scroll(area: AXRect, badge: String)
    case notice(String)
}

public struct HintAppearance: Sendable, Hashable, Codable {
    public var fontSize: CGFloat = 13
    public var fontName: String = "Menlo-Bold"
    public var background: String = "#F5D95AEE"
    public var foreground: String = "#1A1A1A"
    public var typedForeground: String = "#7A6A1A"
    public var borderColor: String = "#00000066"
    public var cornerRadius: CGFloat = 3
    public var dimNonMatching: Bool = false
    public var accent: String = "#3B82F6"
    public init() {}
}
