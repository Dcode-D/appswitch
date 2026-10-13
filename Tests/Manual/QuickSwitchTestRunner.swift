import Foundation

// shortcut: macro-free fallback covers quick switching while Swift Testing macros are unavailable.
@main
enum QuickSwitchTestRunner {
    static func main() throws {
        try testConfiguration()
        try testPrintedExampleHasTenSlots()
        try testRunningApplicationOrder()
        try testRuntimeDispatch()
        print("PASS: quick switch configuration, ordering, and dispatch")
    }

    private static func testPrintedExampleHasTenSlots() throws {
        let configuration = try ConfigurationLoader.load(
            data: Data(ExampleConfiguration.json.utf8)
        )
        try require(
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
            ],
            "printed example did not expose ten quick-switch slots"
        )
    }

    private static func testConfiguration() throws {
        let configuration = try ConfigurationLoader.load(data: Data("""
        {
          "quickSwitch": {"prefix":"control+option","keys":["1","f2"]},
          "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
        }
        """.utf8))
        try require(
            configuration.quickSwitchHotKeys.map(\.canonical) == [
                "control+option+1",
                "control+option+f2",
            ],
            "quick switch shortcuts were not parsed"
        )

        do {
            _ = try ConfigurationLoader.load(data: Data("""
            {
              "quickSwitch": {"prefix":"cmd","keys":["1"]},
              "bindings":[{"shortcut":"cmd+1","bundleID":"com.example.App"}]
            }
            """.utf8))
            throw TestFailure("duplicate quick switch shortcut was accepted")
        } catch ConfigurationError.duplicateShortcut("cmd+1") {
        }

        do {
            _ = try ConfigurationLoader.load(data: Data("""
            {
              "quickSwitch": {"prefix":"cmd","keys":["not-a-key"]},
              "bindings":[{"shortcut":"a","bundleID":"com.example.App"}]
            }
            """.utf8))
            throw TestFailure("invalid quick switch key was accepted")
        } catch let ConfigurationError.invalidQuickSwitchShortcut(index, reason) {
            try require(index == 0, "invalid quick switch key reported the wrong index")
            try require(
                reason == "unsupported shortcut token 'not-a-key'",
                "invalid quick switch key reported the wrong reason"
            )
        }
    }

    private static func testRunningApplicationOrder() throws {
        let applications = [
            application("com.example.Three", launchedAt: 30),
            application("com.example.One", launchedAt: 10),
            application("com.example.Two", launchedAt: 20),
        ]
        var order = RunningApplicationOrder(applications: applications)
        try require(
            order.bundleIdentifier(
                at: 0,
                among: applications,
                frontmostBundleIdentifier: nil
            ) == "com.example.Three",
            "first slot did not select the newest running application"
        )
        try require(
            order.bundleIdentifier(
                at: 2,
                among: applications,
                frontmostBundleIdentifier: nil
            ) == "com.example.One",
            "later slots did not follow reverse launch order"
        )
        try require(
            order.bundleIdentifier(
                at: 0,
                among: applications,
                frontmostBundleIdentifier: "com.example.Three"
            ) == nil,
            "the active application's stable slot was not a no-op"
        )

        let existingApplications = [
            application("com.example.Known", launchedAt: 10),
            application("com.example.Unknown", launchedAt: nil),
        ]
        var lifecycleOrder = RunningApplicationOrder(applications: existingApplications)
        let withNewApplication = existingApplications + [
            application("com.example.New", launchedAt: 20),
        ]
        _ = lifecycleOrder.bundleIdentifier(
            at: 0,
            among: withNewApplication,
            frontmostBundleIdentifier: nil
        )
        try require(
            lifecycleOrder.bundleIdentifiers == [
                "com.example.New",
                "com.example.Known",
                "com.example.Unknown",
            ],
            "a newly seen application did not join the front"
        )

        var multiProcessOrder = RunningApplicationOrder(applications: [
            application("com.example.A", launchedAt: 10, processIdentifier: 1),
            application("com.example.B", launchedAt: 20, processIdentifier: 2),
            application("com.example.A", launchedAt: 30, processIdentifier: 3),
        ])
        try require(
            multiProcessOrder.bundleIdentifier(
                at: 0,
                among: [
                    application("com.example.B", launchedAt: 20, processIdentifier: 2),
                    application("com.example.A", launchedAt: 30, processIdentifier: 3),
                ],
                frontmostBundleIdentifier: nil
            ) == "com.example.B",
            "a bundle moved while another regular process was still running"
        )
        _ = multiProcessOrder.bundleIdentifier(
            at: 0,
            among: [application("com.example.B", launchedAt: 20, processIdentifier: 2)],
            frontmostBundleIdentifier: nil
        )
        try require(
            multiProcessOrder.bundleIdentifiers == ["com.example.B"],
            "a bundle remained after its last regular process exited"
        )

        var snapshotOrder = RunningApplicationOrder(applications: [
            application("com.example.A", launchedAt: 10, processIdentifier: 1),
            application("com.example.B", launchedAt: 20, processIdentifier: 2),
        ])
        _ = snapshotOrder.bundleIdentifier(
            at: 0,
            among: [
                application("com.example.Newer", launchedAt: 40, processIdentifier: 4),
                application("com.example.A", launchedAt: 30, processIdentifier: 3),
                application("com.example.B", launchedAt: 20, processIdentifier: 2),
                application("com.example.Older", launchedAt: 35, processIdentifier: 5),
            ],
            frontmostBundleIdentifier: nil
        )
        try require(
            snapshotOrder.bundleIdentifiers == [
                "com.example.Newer",
                "com.example.Older",
                "com.example.A",
                "com.example.B",
            ],
            "restarted and newly launched apps did not join in reverse launch order"
        )
    }

    private static func application(
        _ bundleIdentifier: String,
        launchedAt timestamp: TimeInterval?,
        processIdentifier: Int32? = nil
    ) -> RunningApplicationIdentity {
        RunningApplicationIdentity(
            bundleIdentifier: bundleIdentifier,
            launchDate: timestamp.map(Date.init(timeIntervalSince1970:)),
            processIdentifier: processIdentifier
        )
    }

    private static func testRuntimeDispatch() throws {
        let registrar = FakeRegistrar()
        let coordinator = FakeCoordinator()
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: FakePermissionChecker(),
            quickSwitchSelector: FakeSelector(
                bundleIdentifiers: (1...10).map { "com.example.App\($0)" }
            ),
            log: { _ in }
        )
        try runtime.start(
            configuration: AppConfiguration(
                moveCursor: false,
                bindings: [],
                quickSwitchHotKeys: try keys.map {
                    try ShortcutParser.parse("cmd+\($0)")
                }
            )
        )

        registrar.trigger(shortcut: "cmd+1")
        registrar.trigger(shortcut: "cmd+0")
        try require(
            coordinator.bindings.map(\.bundleIdentifier) == [
                "com.example.App1",
                "com.example.App10",
            ],
            "quick switch did not dispatch the first and tenth applications"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }
}

private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private final class FakeRegistrar: HotKeyRegistering {
    private var actions: [String: () -> Void] = [:]
    func register(binding: AppBinding, action: @escaping () -> Void) throws {
        actions[binding.hotKey.canonical] = action
    }
    func probe(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError> { .success(()) }
    func unregisterAll() { actions.removeAll() }
    func trigger(shortcut: String) { actions[shortcut]?() }
}

private final class FakeCoordinator: SwitchCoordinating {
    private(set) var bindings: [AppBinding] = []
    func handle(_ binding: AppBinding) { bindings.append(binding) }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool { true }
}

private final class FakeSelector: RunningApplicationSelecting {
    let bundleIdentifiers: [String]
    init(bundleIdentifiers: [String]) { self.bundleIdentifiers = bundleIdentifiers }
    func bundleIdentifier(at index: Int) -> String? {
        bundleIdentifiers.indices.contains(index) ? bundleIdentifiers[index] : nil
    }
}
