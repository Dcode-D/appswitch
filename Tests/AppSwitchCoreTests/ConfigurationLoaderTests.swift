import Foundation
import Testing
@testable import AppSwitchCore

@Suite("ConfigurationLoaderTests")
struct ConfigurationLoaderTests {
    @Test func loadsTheDocumentedConfiguration() throws {
        let configuration = try ConfigurationLoader.load(data: data("""
        {
          "moveCursor": true,
          "bindings": [
            {"shortcut": "option+cmd+1", "bundleID": "com.apple.Safari"}
          ]
        }
        """))

        #expect(configuration.moveCursor)
        #expect(configuration.bindings.count == 1)
        #expect(configuration.bindings[0].hotKey.canonical == "cmd+option+1")
        #expect(configuration.bindings[0].bundleIdentifier == "com.apple.Safari")
    }

    @Test func defaultsLegacyBaseKeyShortcutsToCommandShift() throws {
        let configuration = try ConfigurationLoader.load(data: data("""
        {"bindings":[{"shortcut":"a","bundleID":"com.example.App"}]}
        """))

        #expect(configuration.bindings[0].hotKey.canonical == "cmd+shift+a")
    }

    @Test func defaultsMoveCursorToFalse() throws {
        let configuration = try ConfigurationLoader.load(data: data("""
        {"bindings":[{"shortcut":"a","bundleID":"com.example.App"}]}
        """))

        #expect(configuration.moveCursor == false)
    }

    @Test func loadsQuickSwitchShortcutsFromConfiguredPrefixAndKeys() throws {
        let configuration = try ConfigurationLoader.load(data: data("""
        {
          "quickSwitch": {"prefix":"control+option","keys":["1","f2"]},
          "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
        }
        """))

        #expect(configuration.quickSwitchHotKeys.map(\.canonical) == [
            "control+option+1",
            "control+option+f2",
        ])
    }

    @Test func rejectsQuickSwitchShortcutThatDuplicatesAConfiguredBinding() {
        expectError(.duplicateShortcut("cmd+1"), for: """
        {
          "quickSwitch": {"prefix":"cmd","keys":["1"]},
          "bindings":[{"shortcut":"cmd+1","bundleID":"com.example.App"}]
        }
        """)
    }

    @Test func rejectsUnknownQuickSwitchField() {
        expectError(.unknownQuickSwitchField("extra"), for: """
        {
          "quickSwitch": {"prefix":"cmd","keys":["1"],"extra":true},
          "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
        }
        """)
    }

    @Test func rejectsQuickSwitchWithoutKeys() {
        expectError(.emptyQuickSwitchKeys, for: """
        {
          "quickSwitch": {"prefix":"cmd","keys":[]},
          "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
        }
        """)
    }

    @Test func identifiesAnInvalidQuickSwitchKey() {
        expectError(.invalidQuickSwitchShortcut(index: 0, reason: "unsupported shortcut token 'not-a-key'"), for: """
        {
          "quickSwitch": {"prefix":"cmd","keys":["not-a-key"]},
          "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
        }
        """)
    }

    @Test func rejectsUnknownTopLevelField() {
        expectError(.unknownTopLevelField("extra"), for: """
        {"bindings":[{"shortcut":"a","bundleID":"com.example.App"}],"extra":1}
        """)
    }

    @Test func rejectsUnknownBindingField() {
        expectError(.unknownBindingField(index: 0, field: "name"), for: """
        {"bindings":[{"shortcut":"a","bundleID":"com.example.App","name":"App"}]}
        """)
    }

    @Test func rejectsEmptyBindings() {
        expectError(.emptyBindings, for: #"{"bindings":[]}"#)
    }

    @Test func rejectsEmptyBundleIdentifier() {
        expectError(.emptyBundleIdentifier(index: 0), for: """
        {"bindings":[{"shortcut":"a","bundleID":"  "}]}
        """)
    }

    @Test func rejectsDuplicateCanonicalShortcut() {
        expectError(.duplicateShortcut("cmd+shift+f1"), for: """
        {
          "bindings": [
            {"shortcut":"f1","bundleID":"com.example.One"},
            {"shortcut":"SHIFT+CMD+F1","bundleID":"com.example.Two"}
          ]
        }
        """)
    }

    @Test func rejectsMalformedJSONWithoutReturningPartialConfiguration() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationLoader.load(data: data("""
            {"bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
            """))
        }
    }

    @Test func reportsFileReadFailure() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationLoader.load(
                from: URL(fileURLWithPath: "/path/that/does/not/exist/config.json")
            )
        }
    }

    @Test func loadsTheInstalledExampleConfiguration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = try ConfigurationLoader.load(
            from: repositoryRoot.appendingPathComponent("Resources/config.example.json")
        )

        #expect(configuration.bindings.count == 9)
        #expect(configuration.quickSwitchHotKeys.map(\.canonical) == [
            "cmd+1",
            "cmd+2",
            "cmd+3",
            "cmd+4",
            "cmd+5",
            "cmd+6",
            "cmd+7",
            "cmd+8",
            "cmd+9",
            "cmd+0",
        ])
        #expect(configuration.bindings.first?.bundleIdentifier == "com.apple.Terminal")
        #expect(configuration.bindings.last?.bundleIdentifier == "com.postmanlabs.mac")
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func expectError(_ expected: ConfigurationError, for json: String) {
        do {
            _ = try ConfigurationLoader.load(data: data(json))
            Issue.record("Expected \(expected), but loading succeeded")
        } catch let error as ConfigurationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected ConfigurationError, got \(error)")
        }
    }
}
