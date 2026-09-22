import Foundation

public enum HintFilterResult: Equatable, Sendable {
    case match(index: Int)
    case partial(remaining: Int)
    case none
}

public enum HintFilter {
    public static func matches(_ hints: [Hint], prefix: String) -> [Hint] {
        prefix.isEmpty ? hints : hints.filter { $0.label.hasPrefix(prefix) }
    }
    /// Outcome of appending `char` to `buffer`. Labels are prefix-free so a full match is unconditionally a commit.
    public static func apply(_ hints: [Hint], buffer: String, char: Character) -> HintFilterResult {
        let next = buffer + String(char)
        let m = matches(hints, prefix: next)
        if m.isEmpty { return .none }
        if m.count == 1, m[0].label == next { return .match(index: m[0].index) }
        if let exact = m.first(where: { $0.label == next }) { return .match(index: exact.index) }
        return .partial(remaining: m.count)
    }
}
