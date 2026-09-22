import Foundation
import Geometry

/// Pure role/subrole tables. No AX calls except the optional fallback action query, which the caller performs.
public enum ActionableClassifier {
    public static let allowedRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
        "AXLink", "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle",
        "AXCell", "AXRow", "AXTabButton", "AXColorWell", "AXDockItem",
    ]
    public static let allowedSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton", "AXToggle", "AXSearchField",
        "AXSecureTextField", "AXOutlineRow", "AXTabButton", "AXSwitch", "AXTableRow",
    ]
    /// Roles that are clickable only if an action query confirms AXPress (Electron puts AXPress on bare groups).
    public static let fallbackRoles: Set<String> = ["AXGroup", "AXUnknown", "AXSplitGroup", "AXLayoutArea", "AXImage", "AXStaticText"]
    /// Containers whose frame clips their children; safe to prune against.
    public static let clippingRoles: Set<String> = [
        "AXScrollArea", "AXGroup", "AXList", "AXTable", "AXOutline", "AXBrowser", "AXSplitGroup", "AXRow", "AXTabGroup",
    ]
    /// Parents under which AXStaticText counts as clickable.
    public static let clickableContainers: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXCell", "AXRow", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXTabButton"]
    /// Roles that only count when their parent is a table/outline/list.
    public static let rowRoles: Set<String> = ["AXRow", "AXCell"]

    public enum Verdict: Equatable, Sendable {
        case actionable
        case notActionable
        /// Needs `AXPress` confirmed via an action query (capped per scan).
        case needsActionQuery
    }

    public static func classify(role: String?, subrole: String?, enabled: Bool?, frame: AXRect?, clip: AXRect, parentRole: String?) -> Verdict {
        guard let role else { return .notActionable }
        if enabled == false { return .notActionable }
        guard let frame, frame.isValid, frame.width > 1, frame.height > 1, frame.intersects(clip) else { return .notActionable }
        if let subrole, allowedSubroles.contains(subrole) { return .actionable }
        if role == "AXStaticText" {
            if let p = parentRole, clickableContainers.contains(p) { return .actionable }
            return .notActionable
        }
        if role == "AXImage" { return .needsActionQuery }
        if allowedRoles.contains(role) { return .actionable }
        if fallbackRoles.contains(role) { return .needsActionQuery }
        return .notActionable
    }

    /// Role priority for dedupe: deeper allowlisted roles win; among equals, prefer specific roles over rows/cells.
    public static func priority(role: String) -> Int {
        switch role {
        case "AXLink", "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXPopUpButton", "AXMenuItem", "AXTabButton": return 3
        case "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXMenuButton": return 2
        case "AXCell", "AXRow": return 1
        default: return 0
        }
    }

    /// Dedupe by integral frame, keeping the deepest / highest-priority element. Web content otherwise yields 2–4 stacked hints per link.
    public static func dedupe(_ els: [ActionableElement]) -> [ActionableElement] {
        var best: [AXRect: ActionableElement] = [:]
        var order: [AXRect] = []
        for e in els {
            let k = e.frame.integral
            if let cur = best[k] {
                let a = (priority(role: e.role), e.depth), b = (priority(role: cur.role), cur.depth)
                if a > b { best[k] = e }
            } else { best[k] = e; order.append(k) }
        }
        return order.compactMap { best[$0] }
    }
}
