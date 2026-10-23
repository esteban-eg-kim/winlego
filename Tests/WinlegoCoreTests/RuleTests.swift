import Foundation
import Testing
@testable import WinlegoCore

@Suite struct RuleTests {
    let appWide = Rule(bundleID: "com.apple.Terminal", appName: "Terminal", displayID: nil, zone: 1)
    let titled = Rule(bundleID: "com.apple.Terminal", appName: "Terminal", titleContains: "logs", displayID: "D2", zone: 0)

    @Test func titleMatchBeatsAppWide() {
        let rules = [appWide, titled]
        #expect(Rules.match(rules, bundleID: "com.apple.Terminal", title: "tail -f LOGS")?.id == titled.id)
        #expect(Rules.match(rules, bundleID: "com.apple.Terminal", title: "zsh")?.id == appWide.id)
        #expect(Rules.match(rules, bundleID: "com.apple.Terminal", title: nil)?.id == appWide.id)
        #expect(Rules.match(rules, bundleID: "com.apple.Safari", title: "x") == nil)
    }

    @Test func titledRuleAloneDoesNotMatchOtherWindows() {
        #expect(Rules.match([titled], bundleID: "com.apple.Terminal", title: "zsh") == nil)
    }

    @Test func configDecodesWithMissingKeys() throws {
        let json = #"{"rules":[]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config == Config())
        #expect(config.layout(for: "unknown", portrait: true).id == "rows-2")
        #expect(config.layout(for: "unknown", portrait: false).id == "wide-left")
    }

    @Test func keyCombosNeedAModifierUnlessFunctionKey() throws {
        #expect(KeyCombo(keyCode: 123, modifiers: [.control, .option]).isUsable)
        #expect(!KeyCombo(keyCode: 0, modifiers: [.shift]).isUsable, "⇧A alone would break typing")
        #expect(KeyCombo(keyCode: 122, modifiers: []).isUsable, "F1 alone is fine")
        #expect(KeyCombo.none.isUsable && KeyCombo.none.isNone)
        let json = #"{"shortcuts":{"nextZone":{"keyCode":124,"modifiers":3}}}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.shortcuts["nextZone"] == KeyCombo(keyCode: 124, modifiers: [.control, .option]))
    }
}
