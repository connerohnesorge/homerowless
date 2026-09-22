import Foundation
import Hints
import Overlay
import Input
import Modes
import Discovery
import Routing

/// ~/.config/homerowless/config.json. Every field optional with a default; the fully-populated file written on first run is the docs.
public struct Config: Codable, Sendable, Equatable {
    public var clickHotkey = "cmd+shift+f"
    public var scrollHotkey = "cmd+j"
    public var hintAlphabet = String(HintLabelGenerator.defaultAlphabet)
    public var excludedBundleIDs: [String] = []
    public var hintAppearance = HintAppearance()
    public var scroll = ScrollSynthesizer.Config()
    public var grid = GridConfig()
    public var perAppCompat = PerAppCompat()
    public var restoreCursorAfterClick = false
    public var launchAtLogin = false

    public struct GridConfig: Codable, Sendable, Equatable {
        public var cellWidth: Double = 60
        public var cellHeight: Double = 40
        public var forcedBundleIDs: [String] = []
        public init() {}
    }
    public struct PerAppCompat: Codable, Sendable, Equatable {
        /// Bundle IDs that get AXEnhancedUserInterface (last resort; sticky; breaks window managers).
        public var enhancedUserInterfaceBundleIDs: [String] = []
        public var chromiumSettleMilliseconds = 150
        public init() {}
    }
    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Config()
        clickHotkey = try c.decodeIfPresent(String.self, forKey: .clickHotkey) ?? def.clickHotkey
        scrollHotkey = try c.decodeIfPresent(String.self, forKey: .scrollHotkey) ?? def.scrollHotkey
        hintAlphabet = try c.decodeIfPresent(String.self, forKey: .hintAlphabet) ?? def.hintAlphabet
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? def.excludedBundleIDs
        hintAppearance = try c.decodeIfPresent(HintAppearance.self, forKey: .hintAppearance) ?? def.hintAppearance
        scroll = try c.decodeIfPresent(ScrollSynthesizer.Config.self, forKey: .scroll) ?? def.scroll
        grid = try c.decodeIfPresent(GridConfig.self, forKey: .grid) ?? def.grid
        perAppCompat = try c.decodeIfPresent(PerAppCompat.self, forKey: .perAppCompat) ?? def.perAppCompat
        restoreCursorAfterClick = try c.decodeIfPresent(Bool.self, forKey: .restoreCursorAfterClick) ?? def.restoreCursorAfterClick
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? def.launchAtLogin
    }

    public var coordinatorConfig: CoordinatorConfig {
        var c = CoordinatorConfig()
        let alpha = Array(hintAlphabet)
        c.alphabet = (try? HintLabelGenerator.validate(alpha)) != nil ? alpha : HintLabelGenerator.defaultAlphabet
        c.excludedBundleIDs = Set(excludedBundleIDs)
        c.dimNonMatching = hintAppearance.dimNonMatching
        c.restoreCursorAfterClick = restoreCursorAfterClick
        c.gridForcedBundleIDs = Set(grid.forcedBundleIDs)
        c.grid = GridElementSource(cellWidth: grid.cellWidth, cellHeight: grid.cellHeight)
        c.scroll = scroll
        c.compat.enhancedUIBundleIDs = Set(perAppCompat.enhancedUserInterfaceBundleIDs)
        c.compat.settleMilliseconds = perAppCompat.chromiumSettleMilliseconds
        return c
    }
}
