import Foundation

// shortcut: macro-free fallback covers Task 6 only; remove after Command Line Tools can run Swift Testing.
@main
enum Task6TestRunner {
    private static var failures = 0

    static func main() {
        run("no command defaults to run", testDefaultCommand)
        run("parses every supported command", testSupportedCommands)
        run("rejects unknown commands", testUnknownCommand)
        run("rejects extra arguments", testExtraArguments)
        run("usage errors use exit code 2", testUsageExitCode)
        run("example output is a valid documented configuration", testExampleConfiguration)
        run("diagnostics report a ready configuration", testReadyDiagnostics)
        run("diagnostics request missing Accessibility permission", testMissingPermission)
        run("diagnostics report missing applications", testMissingApplication)
        run("diagnostics probe every hotkey", testHotKeyDiagnostics)
        run("diagnostics report simultaneous problems", testMultipleProblems)
        run("runtime registers actions for every valid binding", testRuntimeRegistration)
        run("runtime logs missing permission once without blocking activation", testRuntimePermission)
        run("runtime keeps valid bindings after a rejected binding", testRuntimeRegistrationFailure)
        run("runtime unregisters only once on termination", testRuntimeTermination)

        if failures == 0 {
            print("PASS: 15 Task 6 tests")
        } else {
            fputs("FAIL: \(failures) Task 6 test(s)\n", stderr)
            exit(1)
        }
    }

    private static func testDefaultCommand() throws {
        try require(try CommandParser.parse(arguments: []) == .run, "empty arguments did not default to run")
    }

    private static func testSupportedCommands() throws {
        try require(try CommandParser.parse(arguments: ["run"]) == .run, "run was not parsed")
        try require(try CommandParser.parse(arguments: ["check"]) == .check, "check was not parsed")
        try require(
            try CommandParser.parse(arguments: ["print-example"]) == .printExample,
            "print-example was not parsed"
        )
    }

    private static func testUnknownCommand() throws {
        try requireThrows({ _ = try CommandParser.parse(arguments: ["wat"]) }, "unknown command was accepted")
    }

    private static func testExtraArguments() throws {
        try requireThrows(
            { _ = try CommandParser.parse(arguments: ["run", "extra"]) },
            "extra arguments were accepted"
        )
    }

    private static func testUsageExitCode() throws {
        do {
            _ = try CommandParser.parse(arguments: ["wat"])
            throw TestFailure("unknown command was accepted")
        } catch let error as CommandParseError {
            try require(error.exitCode == 2, "usage error did not use exit code 2")
        }
    }

    private static func testExampleConfiguration() throws {
        let parsed = try ConfigurationLoader.load(data: Data(ExampleConfiguration.json.utf8))
        try require(parsed.moveCursor == false, "example should keep cursor movement disabled")
        try require(parsed.bindings.map(\.bundleIdentifier) == ["com.apple.Safari", "com.microsoft.VSCode"], "example applications drifted from the spec")
    }

    private static func testReadyDiagnostics() throws {
        let permission = FakePermissionChecker(trusted: true)
        let workspace = FakeWorkspace(installed: ["com.example.One", "com.example.Two"])
        let registrar = FakeRegistrar()
        let report = Diagnostics(
            permissionChecker: permission,
            workspace: workspace,
            hotKeyRegistrar: registrar
        ).check(configuration: configuration)

        try require(report.exitCode == 0, "ready environment returned \(report.exitCode)")
        try require(report.messages.first == "Accessibility permission: ready", "permission result was not first")
        try require(report.messages.count == 5, "ready report did not include each application and shortcut")
    }

    private static func testMissingPermission() throws {
        let permission = FakePermissionChecker(trusted: false)
        let report = Diagnostics(
            permissionChecker: permission,
            workspace: FakeWorkspace(installed: ["com.example.One", "com.example.Two"]),
            hotKeyRegistrar: FakeRegistrar()
        ).check(configuration: configuration)

        try require(report.exitCode == 3, "missing permission did not use exit code 3")
        try require(permission.prompts == [true], "diagnostics did not request the standard prompt")
        try require(report.messages[0].contains("required"), "missing permission was not actionable")
    }

    private static func testMissingApplication() throws {
        let report = Diagnostics(
            permissionChecker: FakePermissionChecker(trusted: true),
            workspace: FakeWorkspace(installed: ["com.example.One"]),
            hotKeyRegistrar: FakeRegistrar()
        ).check(configuration: configuration)

        try require(report.exitCode == 3, "missing app did not use exit code 3")
        try require(report.messages.contains(where: { $0.contains("com.example.Two") && $0.contains("not found") }), "missing app was not named")
    }

    private static func testHotKeyDiagnostics() throws {
        let registrar = FakeRegistrar(rejectedShortcuts: ["cmd+2"])
        let report = Diagnostics(
            permissionChecker: FakePermissionChecker(trusted: true),
            workspace: FakeWorkspace(installed: ["com.example.One", "com.example.Two"]),
            hotKeyRegistrar: registrar
        ).check(configuration: configuration)

        try require(registrar.probed == ["cmd+1", "cmd+2"], "not every shortcut was probed")
        try require(registrar.successfulProbeCleanupCount == 1, "accepted probe was not cleaned up")
        try require(report.exitCode == 3, "hotkey conflict did not use exit code 3")
        try require(report.messages.contains(where: { $0.contains("cmd+1") && $0.contains("available") }), "valid shortcut was hidden")
        try require(report.messages.contains(where: { $0.contains("cmd+2") && $0.contains("unavailable") }), "rejected shortcut was not reported")
    }

    private static func testMultipleProblems() throws {
        let registrar = FakeRegistrar(rejectedShortcuts: ["cmd+2"])
        let report = Diagnostics(
            permissionChecker: FakePermissionChecker(trusted: false),
            workspace: FakeWorkspace(installed: ["com.example.One"]),
            hotKeyRegistrar: registrar
        ).check(configuration: configuration)

        try require(report.exitCode == 3, "multiple environment problems used the wrong exit code")
        try require(report.messages.contains(where: { $0.contains("Accessibility") && $0.contains("required") }), "permission problem missing")
        try require(report.messages.contains(where: { $0.contains("com.example.Two") && $0.contains("not found") }), "application problem missing")
        try require(report.messages.contains(where: { $0.contains("cmd+2") && $0.contains("unavailable") }), "hotkey problem missing")
    }

    private static func testRuntimeRegistration() throws {
        let registrar = FakeRegistrar()
        let coordinator = FakeCoordinator()
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: FakePermissionChecker(trusted: true),
            log: { _ in }
        )

        try runtime.start(configuration: configuration)
        registrar.trigger(shortcut: "cmd+1")
        registrar.trigger(shortcut: "cmd+2")

        try require(registrar.registered == ["cmd+1", "cmd+2"], "runtime did not register every binding")
        try require(coordinator.bindings == configuration.bindings, "registered actions did not reach the coordinator")
    }

    private static func testRuntimePermission() throws {
        let registrar = FakeRegistrar()
        let coordinator = FakeCoordinator()
        let permission = FakePermissionChecker(trusted: false)
        var logs: [String] = []
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: permission,
            log: { logs.append($0) }
        )

        try runtime.start(configuration: configuration)
        registrar.trigger(shortcut: "cmd+1")

        try require(logs.count == 1 && logs[0].contains("Accessibility"), "permission was not logged exactly once")
        try require(permission.prompts == [true], "background startup did not request the system prompt")
        try require(coordinator.bindings.count == 1, "missing permission blocked application switching")
    }

    private static func testRuntimeRegistrationFailure() throws {
        let registrar = FakeRegistrar(rejectedShortcuts: ["cmd+1"])
        let coordinator = FakeCoordinator()
        var logs: [String] = []
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: FakePermissionChecker(trusted: true),
            log: { logs.append($0) }
        )

        try runtime.start(configuration: configuration)
        registrar.trigger(shortcut: "cmd+2")

        try require(logs.count == 1 && logs[0].contains("cmd+1"), "rejected binding was not logged")
        try require(coordinator.bindings.map(\.hotKey.canonical) == ["cmd+2"], "valid binding was not kept active")
    }

    private static func testRuntimeTermination() throws {
        let registrar = FakeRegistrar()
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: FakeCoordinator(),
            permissionChecker: FakePermissionChecker(trusted: true),
            log: { _ in }
        )
        try runtime.start(configuration: configuration)

        runtime.handleTermination()
        runtime.handleTermination()

        try require(registrar.unregisterAllCount == 1, "termination unregistered \(registrar.unregisterAllCount) times")
    }

    private static var configuration: AppConfiguration {
        AppConfiguration(
            moveCursor: false,
            bindings: [binding("cmd+1", bundleID: "com.example.One", keyCode: 18),
                       binding("cmd+2", bundleID: "com.example.Two", keyCode: 19)]
        )
    }

    private static func binding(_ shortcut: String, bundleID: String, keyCode: UInt32) -> AppBinding {
        AppBinding(
            hotKey: HotKey(keyCode: keyCode, modifiers: 256, canonical: shortcut),
            bundleIdentifier: bundleID
        )
    }

    private static func run(_ name: String, _ test: () throws -> Void) {
        do {
            try test()
            print("PASS: \(name)")
        } catch {
            failures += 1
            fputs("FAIL: \(name): \(error)\n", stderr)
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(message) }
    }

    private static func requireThrows(_ action: () throws -> Void, _ message: String) throws {
        do {
            try action()
            throw TestFailure(message)
        } catch is TestFailure {
            throw TestFailure(message)
        } catch {
            return
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking {
    let trusted: Bool
    private(set) var prompts: [Bool] = []

    init(trusted: Bool) { self.trusted = trusted }

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return trusted
    }
}

private final class FakeWorkspace: WorkspaceAPI {
    let installed: Set<String>
    init(installed: Set<String>) { self.installed = installed }

    func runningApplication(bundleIdentifier: String) -> RunningApplicationHandle? { nil }
    func applicationURL(bundleIdentifier: String) -> URL? {
        installed.contains(bundleIdentifier) ? URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app") : nil
    }
    func openApplication(at url: URL, completion: @escaping (Result<RunningApplicationHandle, Error>) -> Void) {}
}

private final class FakeRegistrar: HotKeyRegistering {
    let rejectedShortcuts: Set<String>
    private(set) var probed: [String] = []
    private(set) var successfulProbeCleanupCount = 0
    private(set) var registered: [String] = []
    private(set) var unregisterAllCount = 0
    private var actions: [String: () -> Void] = [:]

    init(rejectedShortcuts: Set<String> = []) { self.rejectedShortcuts = rejectedShortcuts }

    func register(binding: AppBinding, action: @escaping () -> Void) throws {
        if rejectedShortcuts.contains(binding.hotKey.canonical) {
            throw HotKeyRegistrationError.registrationFailed(shortcut: binding.hotKey.canonical, status: -1)
        }
        registered.append(binding.hotKey.canonical)
        actions[binding.hotKey.canonical] = action
    }

    func probe(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError> {
        probed.append(hotKey.canonical)
        if rejectedShortcuts.contains(hotKey.canonical) {
            return .failure(.registrationFailed(shortcut: hotKey.canonical, status: -1))
        }
        successfulProbeCleanupCount += 1
        return .success(())
    }

    func unregisterAll() {
        unregisterAllCount += 1
        actions.removeAll()
    }

    func trigger(shortcut: String) { actions[shortcut]?() }
}

private final class FakeCoordinator: SwitchCoordinating {
    private(set) var bindings: [AppBinding] = []
    func handle(_ binding: AppBinding) { bindings.append(binding) }
}
