import Foundation

// shortcut: macro-free fallback validates the installed example when Swift Testing macros are unavailable.
@main
enum Task7TestRunner {
    static func main() throws {
        let configuration = try ConfigurationLoader.load(
            from: URL(fileURLWithPath: "Resources/config.example.json")
        )
        let expected = [
            "cmd+shift+t": "com.apple.Terminal",
            "cmd+shift+c": "com.openai.codex",
            "cmd+shift+h": "com.google.Chrome",
            "cmd+shift+i": "com.apple.ScreenContinuity",
            "cmd+shift+o": "dev.kdrag0n.MacVirt",
            "cmd+shift+d": "com.tinyapp.TablePlus",
            "cmd+shift+m": "com.microsoft.teams2",
            "cmd+shift+v": "com.microsoft.VSCode",
            "cmd+shift+p": "com.postmanlabs.mac",
        ]
        let actual = Dictionary(
            uniqueKeysWithValues: configuration.bindings.map {
                ($0.hotKey.canonical, $0.bundleIdentifier)
            }
        )

        guard configuration.moveCursor == false,
              actual == expected,
              configuration.quickSwitchHotKeys.map(\.canonical) == [
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
              ]
        else {
            fputs("FAIL: installed example does not match the requested mappings\n", stderr)
            exit(1)
        }
        print("PASS: Task 7 installed example has all 9 requested mappings")
    }
}
