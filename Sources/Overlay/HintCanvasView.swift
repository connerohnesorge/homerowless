import AppKit
import Geometry
import Hints
import os

/// One layer-backed view per screen with a custom draw(_:). Not 400 subviews, not CATextLayers, not SwiftUI.
public final class HintCanvasView: NSView {
    public var model: RenderModel = .empty { didSet { if model != oldValue { needsDisplay = true } } }
    /// AX → this window's local coordinates. Set by the controller.
    public var converter = CoordinateConverter(primaryHeight: 0)
    public var screenNS = NSSpaceRect(.zero)
    public var hintStyle = HintAppearance() { didSet { rebuildStyle() } }
    private var raster: TextRasterCache
    private var bg = NSColor.yellow, border = NSColor.black, accent = NSColor.systemBlue
    private static let signposter = OSSignposter(subsystem: "com.cohnesor.homerowless", category: "overlay")

    public override init(frame: CGRect) {
        raster = TextRasterCache(font: NSFont(name: "Menlo-Bold", size: 11) ?? .boldSystemFont(ofSize: 11), fg: .black, typedFg: .gray)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        rebuildStyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { false }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func rebuildStyle() {
        let a = hintStyle
        raster = TextRasterCache(font: NSFont(name: a.fontName, size: a.fontSize) ?? .boldSystemFont(ofSize: a.fontSize),
                                 fg: NSColor(hex: a.foreground), typedFg: NSColor(hex: a.typedForeground))
        bg = NSColor(hex: a.background); border = NSColor(hex: a.borderColor); accent = NSColor(hex: a.accent)
        needsDisplay = true
    }

    private func local(_ r: AXRect) -> CGRect { converter.toWindowLocal(r, screenNS: screenNS) }

    public override func draw(_ dirty: NSRect) {
        let sp = Self.signposter.beginInterval("draw")
        defer { Self.signposter.endInterval("draw", sp) }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        switch model {
        case .empty, .notice: break
        case .markers(let frames):
            ctx.setFillColor(bg.withAlphaComponent(0.6).cgColor)
            for f in frames {
                let r = local(f); guard r.intersects(bounds) else { continue }
                ctx.fill(CGRect(x: r.minX, y: r.maxY - 6, width: 6, height: 6))
            }
        case .hints(let hints, let typed, let dim):
            drawHints(hints, typed: typed, dim: dim, ctx: ctx, anchorCenter: false)
        case .grid(let hints, let typed, let selected, let nudge):
            ctx.setStrokeColor(border.withAlphaComponent(0.25).cgColor); ctx.setLineWidth(0.5)
            for h in hints { let r = local(h.frame); if r.intersects(bounds) { ctx.stroke(r) } }
            if let s = selected {
                let r = local(s.frame)
                let p = CGPoint(x: r.midX + nudge.x, y: r.midY - nudge.y)
                ctx.setStrokeColor(accent.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
                ctx.fill(CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
            } else {
                drawHints(hints, typed: typed, dim: false, ctx: ctx, anchorCenter: true)
            }
        case .scroll(let area, let badge):
            let r = local(area).insetBy(dx: 1, dy: 1)
            ctx.setStrokeColor(accent.cgColor); ctx.setLineWidth(2)
            ctx.stroke(r)
            let e = raster.line(label: badge, typed: 0, state: 1)
            let br = CGRect(x: r.minX + 6, y: r.maxY - 6 - (e.ascent + e.descent + 6), width: e.width + 12, height: e.ascent + e.descent + 6)
            ctx.setFillColor(accent.cgColor)
            ctx.fill(br)
            ctx.textPosition = CGPoint(x: br.minX + 6, y: br.minY + 3 + e.descent)
            CTLineDraw(e.line, ctx)
        }
    }

    private func drawHints(_ hints: [Hint], typed: String, dim: Bool, ctx: CGContext, anchorCenter: Bool) {
        let padX: CGFloat = 4, padY: CGFloat = 2
        for h in hints {
            let matches = h.label.hasPrefix(typed)
            if !matches && !dim { continue }
            let r = local(h.frame)
            guard r.intersects(bounds.insetBy(dx: -40, dy: -40)) else { continue }
            let e = raster.line(label: h.label, typed: matches ? typed.count : 0)
            let w = e.width + padX * 2, hh = e.ascent + e.descent + padY * 2
            var x = anchorCenter ? r.midX - w / 2 : r.minX - 2
            var y = anchorCenter ? r.midY - hh / 2 : r.maxY - hh / 2 - 2
            x = min(max(x, 0), bounds.width - w); y = min(max(y, 0), bounds.height - hh)
            let box = CGRect(x: x, y: y, width: w, height: hh)
            let path = CGPath(roundedRect: box, cornerWidth: hintStyle.cornerRadius, cornerHeight: hintStyle.cornerRadius, transform: nil)
            ctx.setFillColor((matches ? bg : bg.withAlphaComponent(0.3)).cgColor)
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(border.cgColor); ctx.setLineWidth(0.5)
            ctx.addPath(path); ctx.strokePath()
            ctx.textPosition = CGPoint(x: x + padX, y: y + padY + e.descent)
            CTLineDraw(e.line, ctx)
        }
    }
}

extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA"
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let hasA = s.count == 8
        let r = CGFloat((v >> (hasA ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasA ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasA ? 8 : 0)) & 0xFF) / 255
        let a = hasA ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
