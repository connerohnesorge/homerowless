import Foundation
import Carbon.HIToolbox
import IOKit

/// While a password field has focus, IsSecureEventInputEnabled() is true and both the hotkey and the tap go dark.
/// loginwindow sometimes keeps the flag set after a lock/unlock cycle; the tap still gets disabled
/// (`.tapDisabledByUserInput`), so it is genuinely blocking. Name the holder so the user can fix it.
public enum SecureInputMonitor {
    public static var isActive: Bool { IsSecureEventInputEnabled() }
    /// Human-readable description of who holds secure input, for the notice.
    public static var holderDescription: String {
        guard let pid = holderPID else { return "unknown process" }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return "pid \(pid)" }
        let name = URL(fileURLWithPath: String(cString: buf)).lastPathComponent
        return name == "loginwindow" ? "loginwindow (lock and unlock the screen to clear it)" : name
    }
    /// PID that enabled secure input, from IORegistry root → IOConsoleUsers → kCGSSessionSecureInputPID.
    public static var holderPID: pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let v = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let users = v as? [[String: Any]] else { return nil }
        for u in users {
            if let pid = (u["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value { return pid }
        }
        return nil
    }
}
