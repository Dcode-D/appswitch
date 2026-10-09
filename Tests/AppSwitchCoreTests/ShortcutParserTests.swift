import Testing
@testable import AppSwitchCore

@Suite("ShortcutParserTests")
struct ShortcutParserTests {
    @Test func normalizesCaseWhitespaceAndModifierOrder() throws {
        let shortcut = try ShortcutParser.parse(" Option + CMD + 1 ")

        #expect(shortcut.keyCode == 18)
        #expect(shortcut.modifiers == 2_304)
        #expect(shortcut.canonical == "cmd+option+1")
    }

    @Test func acceptsFunctionKeyWithControlAndShift() throws {
        let shortcut = try ShortcutParser.parse("control+shift+F12")

        #expect(shortcut.keyCode == 111)
        #expect(shortcut.modifiers == 4_608)
        #expect(shortcut.canonical == "control+shift+f12")
    }

    @Test func rejectsShortcutWithoutModifier() {
        #expect(throws: ShortcutParseError.self) {
            try ShortcutParser.parse("a")
        }
    }

    @Test func rejectsRepeatedModifier() {
        #expect(throws: ShortcutParseError.self) {
            try ShortcutParser.parse("cmd+cmd+a")
        }
    }

    @Test func rejectsUnknownModifier() {
        #expect(throws: ShortcutParseError.self) {
            try ShortcutParser.parse("hyper+a")
        }
    }

    @Test func rejectsMultipleBaseKeys() {
        #expect(throws: ShortcutParseError.self) {
            try ShortcutParser.parse("cmd+a+b")
        }
    }

    @Test func rejectsUnsupportedBaseKey() {
        #expect(throws: ShortcutParseError.self) {
            try ShortcutParser.parse("cmd+space")
        }
    }
}
