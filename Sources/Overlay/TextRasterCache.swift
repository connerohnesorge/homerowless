import AppKit
import CoreText

/// CTLine + bounds per (label, typedPrefixLength, state). At most alphabet² distinct labels, so per-frame shaping is zero.
final class TextRasterCache {
    struct Key: Hashable { let label: String; let typed: Int; let state: Int }
    struct Entry { let line: CTLine; let width: CGFloat; let ascent: CGFloat; let descent: CGFloat }
    private var cache: [Key: Entry] = [:]
    var font: NSFont
    var fg: NSColor
    var typedFg: NSColor

    init(font: NSFont, fg: NSColor, typedFg: NSColor) { self.font = font; self.fg = fg; self.typedFg = typedFg }
    func invalidate() { cache.removeAll() }

    func line(label: String, typed: Int, state: Int = 0) -> Entry {
        let k = Key(label: label, typed: typed, state: state)
        if let e = cache[k] { return e }
        let s = NSMutableAttributedString(string: label, attributes: [.font: font, .foregroundColor: fg])
        if typed > 0 { s.addAttribute(.foregroundColor, value: typedFg, range: NSRange(location: 0, length: min(typed, label.count))) }
        let line = CTLineCreateWithAttributedString(s)
        var a: CGFloat = 0, d: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(line, &a, &d, nil))
        let e = Entry(line: line, width: w, ascent: a, descent: d)
        cache[k] = e
        return e
    }
}
