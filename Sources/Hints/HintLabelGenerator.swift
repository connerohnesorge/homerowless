import Foundation

public enum HintLabelGenerator {
    /// Home-row-weighted default alphabet, lowercase only. |A| = 14.
    public static let defaultAlphabet: [Character] = Array("asdfghjklqwert")

    public enum AlphabetError: Error, Equatable { case tooShort, duplicate(Character), uppercase(Character) }

    public static func validate(_ alphabet: [Character]) throws {
        guard alphabet.count >= 2 else { throw AlphabetError.tooShort }
        var seen = Set<Character>()
        for c in alphabet {
            if c.isUppercase { throw AlphabetError.uppercase(c) }
            if !seen.insert(c).inserted { throw AlphabetError.duplicate(c) }
        }
    }

    /// Vimium construction: the BFS frontier is a prefix-free set with minimal maximum length, so completing a
    /// label is unconditionally a commit (no disambiguation timeout).
    /// NOTE: do not `reversed()` the result. Reversing an append-built frontier turns prefix-free into suffix-free
    /// and yields collisions like `b` / `ba`. Vimium prepends then reverses, which is identical to appending.
    public static func labels(count n: Int, alphabet A: [Character] = defaultAlphabet) -> [String] {
        guard n > 0 else { return [] }
        var hints: [[Character]] = [[]]
        var offset = 0
        while hints.count - offset < n || hints.count == 1 {
            let h = hints[offset]; offset += 1
            for c in A { hints.append(h + [c]) }
        }
        return hints[offset ..< offset + n].map { String($0) }
    }
}
