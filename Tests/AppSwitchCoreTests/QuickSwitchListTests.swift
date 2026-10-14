import Foundation
import Testing
@testable import AppSwitchCore

@Suite("QuickSwitchListTests")
struct QuickSwitchListTests {
    @Test func parsesListCommand() throws {
        #expect(try CommandParser.parse(arguments: ["list"]) == .list)
    }

    @Test func listsAssignedApplicationsAndEmptySlots() throws {
        let lines = QuickSwitchList.lines(
            hotKeys: [
                try ShortcutParser.parse("cmd+1"),
                try ShortcutParser.parse("cmd+2"),
            ],
            applications: [
                RunningApplicationIdentity(
                    bundleIdentifier: "com.apple.Safari",
                    localizedName: "Safari",
                    launchDate: Date(timeIntervalSince1970: 20)
                ),
            ]
        )

        #expect(lines == [
            "cmd+1\tSafari\tcom.apple.Safari",
            "cmd+2\t—",
        ])
    }

    @Test func explainsWhenQuickSwitchIsNotConfigured() {
        #expect(QuickSwitchList.lines(hotKeys: [], applications: []) == [
            "Quick switch is not configured.",
        ])
    }
}
