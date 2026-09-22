import Foundation
import Carbon.HIToolbox
import os

/// UCKeyTranslate with the current layout, cached and refreshed on input-source change. Pure C, safe on the tap thread.
/// Modifier state is passed empty so shift+s → "s"; the shift flag travels separately as click intent.
public final class KeyTranslator: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())
    private var observerToken: NSObjectProtocol?

    public init() {
        reload()
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: nil) { [weak self] _ in self?.reload() }
    }
    deinit { if let t = observerToken { DistributedNotificationCenter.default().removeObserver(t) } }

    private func reload() {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        lock.withLock { $0 = data }
    }

    /// Unmodified character for a virtual key code (nil for non-printing keys).
    public func character(keyCode: UInt16) -> Character? {
        let data = lock.withLock { $0 }
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw -> Character? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let err = UCKeyTranslate(base, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                     UInt32(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &len, &chars)
            guard err == noErr, len > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: len)
            guard let c = s.first, !c.isNewline, c != "\t", c.asciiValue.map({ $0 >= 32 }) ?? true else { return nil }
            return c
        }
    }
}

public enum KeyCode {
    public static let escape: UInt16 = 53
    public static let delete: UInt16 = 51
    public static let `return`: UInt16 = 36
    public static let space: UInt16 = 49
    public static let tab: UInt16 = 48
    public static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
}
