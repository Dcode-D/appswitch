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
            {"shortcut": "cmd+option+1", "bundleID": "com.apple.Safari"}
          ]
        }
        """))

        #expect(configuration.moveCursor)
        #expect(configuration.bindings.count == 1)
        #expect(configuration.bindings[0].hotKey.canonical == "cmd+option+1")
        #expect(configuration.bindings[0].bundleIdentifier == "com.apple.Safari")
    }

    @Test func defaultsMoveCursorToFalse() throws {
        let configuration = try ConfigurationLoader.load(data: data("""
        {"bindings":[{"shortcut":"cmd+a","bundleID":"com.example.App"}]}
        """))

        #expect(configuration.moveCursor == false)
    }

    @Test func rejectsUnknownTopLevelField() {
        expectError(.unknownTopLevelField("extra"), for: """
        {"bindings":[{"shortcut":"cmd+a","bundleID":"com.example.App"}],"extra":1}
        """)
    }

    @Test func rejectsUnknownBindingField() {
        expectError(.unknownBindingField(index: 0, field: "name"), for: """
        {"bindings":[{"shortcut":"cmd+a","bundleID":"com.example.App","name":"App"}]}
        """)
    }

    @Test func rejectsEmptyBindings() {
        expectError(.emptyBindings, for: #"{"bindings":[]}"#)
    }

    @Test func rejectsEmptyBundleIdentifier() {
        expectError(.emptyBundleIdentifier(index: 0), for: """
        {"bindings":[{"shortcut":"cmd+a","bundleID":"  "}]}
        """)
    }

    @Test func rejectsDuplicateCanonicalShortcut() {
        expectError(.duplicateShortcut("cmd+option+1"), for: """
        {
          "bindings": [
            {"shortcut":"option+cmd+1","bundleID":"com.example.One"},
            {"shortcut":"CMD+OPTION+1","bundleID":"com.example.Two"}
          ]
        }
        """)
    }

    @Test func rejectsMalformedJSONWithoutReturningPartialConfiguration() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationLoader.load(data: data("""
            {"bindings":[{"shortcut":"cmd+a","bundleID":"com.example.App"}]
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
