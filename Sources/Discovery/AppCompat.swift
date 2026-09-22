import Foundation
import AXCore

/// Chromium / Electron detection and the AXManualAccessibility handshake. Scoped strictly to the frontmost app.
public struct AppCompatConfig: Sendable, Hashable {
    /// Bundle IDs the user opted into AXEnhancedUserInterface (last resort, sticky, breaks window managers).
    public var enhancedUIBundleIDs: Set<String> = []
    public var settleMilliseconds: Int = 150
    public init() {}
}

public final class AppCompat: @unchecked Sendable {
    private let lock = NSLock()
    private var handled = Set<pid_t>()
    public var config = AppCompatConfig()
    public init() {}

    /// Detect without IPC: look for the Chromium/Electron framework inside the bundle.
    public static func isChromiumLike(bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        let fw = bundleURL.appendingPathComponent("Contents/Frameworks")
        for name in ["Electron Framework.framework", "Chromium Embedded Framework.framework", "Google Chrome Framework.framework",
                     "Microsoft Edge Framework.framework", "Brave Browser Framework.framework", "Arc Framework.framework", "Chromium Framework.framework"] {
            if FileManager.default.fileExists(atPath: fw.appendingPathComponent(name).path) { return true }
        }
        if let items = try? FileManager.default.contentsOfDirectory(atPath: fw.path) {
            return items.contains { $0.hasSuffix("Framework.framework") && ($0.contains("Chrom") || $0.contains("Electron")) }
        }
        return false
    }

    public enum Outcome: Sendable, Equatable { case alreadyHandled, notNeeded, setManual, setEnhanced }

    /// Call before scanning. Returns whether a settle-and-retry is warranted (true on first-time set).
    @discardableResult
    public func prepare(pid: pid_t, bundleID: String?, bundleURL: URL?, voiceOverRunning: Bool) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        if handled.contains(pid) { return .alreadyHandled }
        handled.insert(pid)
        let app = AXElement.application(pid: pid)
        var outcome: Outcome = .notNeeded
        if Self.isChromiumLike(bundleURL: bundleURL) {
            _ = app.set(.manualAccessibility, bool: true)
            outcome = .setManual
        }
        if let b = bundleID, config.enhancedUIBundleIDs.contains(b), !voiceOverRunning {
            _ = app.set(.enhancedUserInterface, bool: true)
            outcome = .setEnhanced
        }
        return outcome
    }

    public func forget(pid: pid_t) { lock.lock(); handled.remove(pid); lock.unlock() }
    public func isHandled(pid: pid_t) -> Bool { lock.lock(); defer { lock.unlock() }; return handled.contains(pid) }
}
