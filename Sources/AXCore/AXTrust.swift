import Foundation
import ApplicationServices

public enum AXTrust {
    /// Non-prompting check.
    public static var isTrusted: Bool { AXIsProcessTrusted() }
    /// Triggers the system prompt / adds us to the Accessibility list.
    @discardableResult
    public static func requestPrompt() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    public static let settingsDeepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
