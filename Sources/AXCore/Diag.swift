import Foundation
import os

/// Append-only diagnostic log at ~/Library/Logs/homerowless.log (os_log is not always readable from sandboxes/CI).
public enum Diag {
    private static let lock = OSAllocatedUnfairLock(initialState: FileHandle?.none)
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/homerowless.log")
    public static func log(_ s: @autoclosure () -> String) {
        let line = "\(Date().timeIntervalSince1970) \(s())\n"
        lock.withLock { h in
            if h == nil {
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                h = try? FileHandle(forWritingTo: url); h?.seekToEndOfFile()
            }
            h?.write(line.data(using: .utf8)!)
        }
    }
}
