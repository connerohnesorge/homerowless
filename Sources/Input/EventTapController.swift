import Foundation
import CoreGraphics
import os

/// Decoded key event handed to the coordinator (asynchronously, on the main actor).
public struct KeyInput: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case down, up, flags }
    public var kind: Kind
    public var keyCode: UInt16
    public var character: Character?
    public var flags: CGEventFlags
    public var isRepeat: Bool
}

/// Context box reachable from the C callback. Allocate first, create the tap, back-fill `tap`.
final class EventTapContext: @unchecked Sendable {
    var tap: CFMachPort?
    let store: ModeStore
    let translator: KeyTranslator
    let sink: @Sendable (KeyInput) -> Void
    let onDisabled: @Sendable (String) -> Void
    init(store: ModeStore, translator: KeyTranslator, sink: @escaping @Sendable (KeyInput) -> Void, onDisabled: @escaping @Sendable (String) -> Void) {
        self.store = store; self.translator = translator; self.sink = sink; self.onDisabled = onDisabled
    }
}

private let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let ctx = Unmanaged<EventTapContext>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Timeout: re-arm once so the next activation works. UserInput (secure input): leave it disabled —
        // re-enabling immediately is disabled again by the system and spins. The coordinator enables on next activation.
        if type == .tapDisabledByTimeout, let tap = ctx.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        ctx.onDisabled(type == .tapDisabledByTimeout ? "timeout" : "userInput")
        return Unmanaged.passUnretained(event)
    }
    // Take the lock, decide purely from the snapshot, release. No allocation, no Obj-C, no logging in the critical section.
    let snap = ctx.store.read()
    if snap.tag == .idle { return Unmanaged.passUnretained(event) }
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let kind: KeyInput.Kind = type == .keyDown ? .down : type == .keyUp ? .up : .flags
    let ch = kind == .flags ? nil : ctx.translator.character(keyCode: keyCode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    ctx.sink(KeyInput(kind: kind, keyCode: keyCode, character: ch, flags: flags, isRepeat: isRepeat))
    // Let our own hotkey chords through in every mode so Cmd-J / Cmd-Shift-F toggle the mode off.
    if flags.contains(.maskCommand) && snap.hotkeyKeyCodes.contains(keyCode) { return Unmanaged.passUnretained(event) }
    switch snap.tag {
    case .idle: return Unmanaged.passUnretained(event)
    case .scanning, .hinting, .grid:
        // Consume everything except pure modifier changes (pass through so the app sees correct modifier state).
        if kind == .flags { return Unmanaged.passUnretained(event) }
        // Let Cmd-combos through only if they carry command *and* are not our own keys — otherwise consume. Never leak.
        return nil
    case .scrolling:
        if kind == .flags { return Unmanaged.passUnretained(event) }
        if flags.contains(.maskCommand) && !flags.contains(.maskShift) && ch != nil && ch != "j" { return Unmanaged.passUnretained(event) }
        if keyCode == KeyCode.escape || (ch.map { snap.scrollKeys.contains($0) } ?? false) || ch.map({ $0.isLetter }) ?? false { return nil }
        return Unmanaged.passUnretained(event)
    }
}

/// Owns the CGEventTap on a dedicated thread (C1). Created once at launch, disabled while idle.
public final class EventTapController: @unchecked Sendable {
    private var ctx: EventTapContext?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var source: CFRunLoopSource?
    private let ready = DispatchSemaphore(value: 0)
    public private(set) var isCreated = false
    private let log = Logger(subsystem: "com.cohnesor.homerowless", category: "tap")

    public init() {}

    /// Returns false when the tap could not be created — the authoritative runtime check for Accessibility.
    @discardableResult
    public func start(store: ModeStore, translator: KeyTranslator, sink: @escaping @Sendable (KeyInput) -> Void, onDisabled: @escaping @Sendable (String) -> Void) -> Bool {
        if isCreated { return true }
        let ctx = EventTapContext(store: store, translator: translator, sink: sink, onDisabled: onDisabled)
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                          callback: tapCallback, userInfo: Unmanaged.passUnretained(ctx).toOpaque()) else {
            log.error("CGEvent.tapCreate returned nil (Accessibility not granted?)")
            return false
        }
        ctx.tap = tap
        self.ctx = ctx
        CGEvent.tapEnable(tap: tap, enable: false)
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        source = src
        let t = Thread { [weak self] in
            guard let self, let src = self.source else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            self.ready.signal()
            CFRunLoopRun()
        }
        t.name = "com.homerowless.eventtap"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        ready.wait()
        isCreated = true
        return true
    }

    public func setEnabled(_ on: Bool) {
        guard let tap = ctx?.tap else { return }
        CGEvent.tapEnable(tap: tap, enable: on)
    }
    public var isEnabled: Bool { ctx?.tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    public func stop() {
        if let tap = ctx?.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let rl = runLoop { CFRunLoopStop(rl) }
        ctx = nil; source = nil; thread = nil; runLoop = nil
        isCreated = false
    }
}
