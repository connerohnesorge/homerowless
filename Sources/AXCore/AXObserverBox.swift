import Foundation
import ApplicationServices

/// Minimal AXObserver wrapper for window-moved / app-deactivated style notifications.
public final class AXObserverBox: @unchecked Sendable {
    private var observer: AXObserver?
    private let pid: pid_t
    private let handler: @Sendable (String) -> Void
    private var runLoop: CFRunLoop?

    public init?(pid: pid_t, runLoop: CFRunLoop = CFRunLoopGetMain(), handler: @escaping @Sendable (String) -> Void) {
        self.pid = pid; self.handler = handler; self.runLoop = runLoop
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, _, name, refcon in
            guard let refcon else { return }
            let box = Unmanaged<AXObserverBox>.fromOpaque(refcon).takeUnretainedValue()
            box.handler(name as String)
        }
        guard AXObserverCreate(pid, cb, &obs) == .success, let o = obs else { return nil }
        observer = o
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(o), .defaultMode)
    }
    public func add(_ notification: String, on element: AXElement) {
        guard let observer else { return }
        AXObserverAddNotification(observer, element.ref, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }
    deinit {
        if let observer, let runLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
