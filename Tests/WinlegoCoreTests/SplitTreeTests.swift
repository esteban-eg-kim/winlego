import CoreGraphics
import Foundation
import Testing
@testable import WinlegoCore

@Suite struct SplitTreeTests {
    @Test func zonesComeInReadingOrderWithDefaultNames() {
        let grid = Presets.grid.zones
        #expect(grid.map(\.name) == ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
        #expect(grid[1].rect == NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(grid[2].path == [1, 0])
        let custom = Layout(id: "c", name: "c", root: .split(axis: .horizontal, ratio: 0.5, first: .zone(name: nil), second: .zone(name: "B")))
        #expect(custom.zones.map(\.name) == ["Zone 1", "B"])
    }

    @Test func dividersDescribeEachSplit() {
        let d = Presets.leftStack.dividers
        #expect(d.count == 2)
        #expect(d[0].path == [] && d[0].axis == .horizontal && d[0].line == NormRect(x: 0.6, y: 0, width: 0, height: 1))
        #expect(d[1].path == [1] && d[1].axis == .vertical && d[1].region == NormRect(x: 0.6, y: 0, width: 0.4, height: 1))
        #expect(d[1].line.y == 0.5)
    }

    @Test func settingRatioClampsAndOnlyTouchesThatSplit() {
        let l = Presets.leftStack.settingRatio(0.95, at: []).settingRatio(0.3, at: [1])
        #expect(l.dividers[0].ratio == Layout.maxRatio)
        #expect(l.dividers[1].ratio == 0.3)
        #expect(Presets.leftStack.settingRatio(0.2, at: [0]) == Presets.leftStack, "a leaf has no ratio")
    }

    @Test func splitAndRemoveRoundTrip() {
        let one = Presets.fullScreen
        let two = one.splitting([], axis: .vertical)
        #expect(two.zones.count == 2 && two.zones[0].name == "Full" && two.zones[1].name == "Zone 2")
        let three = two.splitting([1], axis: .horizontal)
        #expect(three.zones.map(\.path) == [[0], [1, 0], [1, 1]])
        #expect(three.removing([1, 0]).zones.map(\.path) == [[0], [1]])
        #expect(three.removing([0]).zones.count == 2)
        #expect(one.removing([]) == one, "the last zone stays")
        #expect(two.renaming([1], to: "  Bottom ").zones[1].name == "Bottom")
        #expect(two.renaming([1], to: " ").zones[1].name == "Zone 2")
    }

    @Test func layoutsSurviveJSON() throws {
        let data = try JSONEncoder().encode(Presets.all)
        let back = try JSONDecoder().decode([Layout].self, from: data)
        #expect(back == Presets.all)
    }

    @Test func customLayoutsShadowPresetsInConfig() {
        var config = Config()
        let mine = Layout(id: "halves", name: "My halves", root: .split(axis: .horizontal, ratio: 0.3, first: .zone(name: nil), second: .zone(name: nil)))
        config.upsert(mine)
        #expect(config.layout(id: "halves") == mine)
        #expect(config.allLayouts.filter { $0.id == "halves" }.count == 1)
        #expect(config.allLayouts.first == mine)
        config.upsert(Layout(id: "halves", name: "again", root: mine.root))
        #expect(config.customLayouts.count == 1 && config.customLayouts[0].name == "again")
    }
}
