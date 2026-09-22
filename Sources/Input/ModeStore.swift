import Foundation
import os

/// The tap callback's entire decision input. Tiny value type behind an unfair lock; the coordinator is the single writer.
public struct ModeSnapshot: Sendable, Equatable {
    public enum Tag: Sendable, Equatable { case idle, scanning, hinting, grid, scrolling }
    public var tag: Tag = .idle
    /// Characters the tap should treat as hint input.
    public var alphabet: Set<Character> = []
    /// Consume every key while active (hint modes). Scroll mode also consumes its bound keys.
    public var scrollKeys: Set<Character> = ["h", "j", "k", "l", "d", "u", "g", "G"]
    public init() {}
}

public final class ModeStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: ModeSnapshot())
    public init() {}
    public func read() -> ModeSnapshot { lock.withLock { $0 } }
    public func write(_ s: ModeSnapshot) { lock.withLock { $0 = s } }
    public func update(_ f: @Sendable (inout ModeSnapshot) -> Void) { lock.withLock { f(&$0) } }
}
