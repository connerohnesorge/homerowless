import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// A parsed hotkey like "cmd+shift+f".
public struct Hotkey: Hashable, Sendable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32   // Carbon modifier mask
    public var display: String
    public init(keyCode: UInt32, modifiers: UInt32, display: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.display = display }

    private static let keyNames: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50, "space": 49, "return": 36, "tab": 48, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
    /// Parses "cmd+shift+f", "ctrl+alt+space". Returns nil on unknown key.
    public init?(_ spec: String) {
        var mods: UInt32 = 0
        var key: UInt32?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": mods |= UInt32(cmdKey)
            case "shift", "⇧": mods |= UInt32(shiftKey)
            case "alt", "opt", "option", "⌥": mods |= UInt32(optionKey)
            case "ctrl", "control", "⌃": mods |= UInt32(controlKey)
            default: key = Hotkey.keyNames[part]
            }
        }
        guard let k = key else { return nil }
        self.init(keyCode: k, modifiers: mods, display: spec)
    }
}

/// Carbon RegisterEventHotKey: no TCC, registers with the window server, immune to tap timeouts.
public final class HotkeyManager: @unchecked Sendable {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @Sendable () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x484D5257 // 'HMRW'

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let cb: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            mgr.handlers[hk.id]?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), cb, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    @discardableResult
    public func register(_ hk: Hotkey, handler: @escaping @Sendable () -> Void) -> UInt32? {
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hk.keyCode, hk.modifiers, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref; handlers[id] = handler
        return id
    }
    public func unregisterAll() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs.removeAll(); handlers.removeAll()
    }
}
