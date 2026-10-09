import Foundation

// shortcut: macro-free fallback covers Task 3 only; remove after Command Line Tools can run Swift Testing.
@main
enum Task3TestRunner {
    private static var failures = 0

    static func main() {
        run("activates a running app without launching", testRunningApp)
        run("launches and activates a stopped app", testStoppedApp)
        run("reports an unknown bundle identifier", testMissingApp)
        run("reports a launch failure", testLaunchFailure)
        run("reports an activation failure", testActivationFailure)
        run("coalesces repeated presses while launching", testLaunchCoalescing)

        if failures == 0 {
            print("PASS: 6 Task 3 tests")
        } else {
            fputs("FAIL: \(failures) Task 3 test(s)\n", stderr)
            exit(1)
        }
    }

    private static func testRunningApp() throws {
        let app = FakeRunningApplication(processIdentifier: 101)
        let workspace = FakeWorkspaceAPI(runningApplication: app)
        let activator = ApplicationActivator(workspace: workspace)
        var result: Result<pid_t, ApplicationActivationError>?

        let accepted = activator.activate(bundleIdentifier: "com.example.App") { result = $0 }

        try require(accepted, "request was not accepted")
        try require(workspace.openCount == 0, "running app was launched again")
        try require(app.activationCount == 1, "running app was not activated once")
        let activatedProcessID = try processID(from: result)
        try require(activatedProcessID == 101, "wrong process ID")
    }

    private static func testStoppedApp() throws {
        let launchedApp = FakeRunningApplication(processIdentifier: 202)
        let workspace = FakeWorkspaceAPI(
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let activator = ApplicationActivator(workspace: workspace)
        var result: Result<pid_t, ApplicationActivationError>?

        let accepted = activator.activate(bundleIdentifier: "com.example.App") { result = $0 }
        try require(accepted, "request was not accepted")
        try require(workspace.openCount == 1, "stopped app was not launched once")
        try require(result == nil, "activation completed before launch")

        workspace.completeLaunch(.success(launchedApp))
        try require(launchedApp.activationCount == 1, "launched app was not activated")
        let activatedProcessID = try processID(from: result)
        try require(activatedProcessID == 202, "wrong launched process ID")
    }

    private static func testMissingApp() throws {
        let workspace = FakeWorkspaceAPI()
        let activator = ApplicationActivator(workspace: workspace)
        var result: Result<pid_t, ApplicationActivationError>?

        _ = activator.activate(bundleIdentifier: "com.missing.App") { result = $0 }

        try require(
            error(from: result) == .applicationNotFound(bundleIdentifier: "com.missing.App"),
            "missing app error was not returned"
        )
        try require(workspace.openCount == 0, "missing app attempted to launch")
    }

    private static func testLaunchFailure() throws {
        let workspace = FakeWorkspaceAPI(
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let activator = ApplicationActivator(workspace: workspace)
        var result: Result<pid_t, ApplicationActivationError>?

        _ = activator.activate(bundleIdentifier: "com.example.App") { result = $0 }
        workspace.completeLaunch(.failure(FakeError.launchFailed))

        try require(
            error(from: result) == .launchFailed(
                bundleIdentifier: "com.example.App",
                reason: "launch failed"
            ),
            "launch error was not returned"
        )
    }

    private static func testActivationFailure() throws {
        let app = FakeRunningApplication(processIdentifier: 303, activationSucceeds: false)
        let workspace = FakeWorkspaceAPI(runningApplication: app)
        let activator = ApplicationActivator(workspace: workspace)
        var result: Result<pid_t, ApplicationActivationError>?

        _ = activator.activate(bundleIdentifier: "com.example.App") { result = $0 }

        try require(
            error(from: result) == .activationFailed(bundleIdentifier: "com.example.App"),
            "activation error was not returned"
        )
    }

    private static func testLaunchCoalescing() throws {
        let app = FakeRunningApplication(processIdentifier: 404)
        let workspace = FakeWorkspaceAPI(
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let activator = ApplicationActivator(workspace: workspace)
        var firstResult: Result<pid_t, ApplicationActivationError>?
        var secondCompletionCalled = false

        let firstAccepted = activator.activate(bundleIdentifier: "com.example.App") {
            firstResult = $0
        }
        let secondAccepted = activator.activate(bundleIdentifier: "com.example.App") { _ in
            secondCompletionCalled = true
        }
        workspace.completeLaunch(.success(app))

        try require(firstAccepted, "first request was not accepted")
        try require(secondAccepted == false, "repeated request was not coalesced")
        try require(workspace.openCount == 1, "app launched more than once")
        try require(app.activationCount == 1, "app activated more than once")
        try require(secondCompletionCalled == false, "coalesced completion was called")
        let activatedProcessID = try processID(from: firstResult)
        try require(activatedProcessID == 404, "first request did not complete")
    }

    private static func processID(
        from result: Result<pid_t, ApplicationActivationError>?
    ) throws -> pid_t {
        guard let result else { throw TestFailure("completion was not called") }
        switch result {
        case let .success(processIdentifier):
            return processIdentifier
        case let .failure(error):
            throw TestFailure("unexpected failure: \(error)")
        }
    }

    private static func error(
        from result: Result<pid_t, ApplicationActivationError>?
    ) -> ApplicationActivationError? {
        guard case let .failure(error)? = result else { return nil }
        return error
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

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) throws {
        guard condition() else { throw TestFailure(message()) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private enum FakeError: Error, LocalizedError {
    case launchFailed

    var errorDescription: String? { "launch failed" }
}

private final class FakeRunningApplication: RunningApplicationHandle {
    let processIdentifier: pid_t
    let isRegular = true
    private let activationSucceeds: Bool
    private(set) var activationCount = 0

    init(processIdentifier: pid_t, activationSucceeds: Bool = true) {
        self.processIdentifier = processIdentifier
        self.activationSucceeds = activationSucceeds
    }

    func activateForSwitching() -> Bool {
        activationCount += 1
        return activationSucceeds
    }
}

private final class FakeWorkspaceAPI: WorkspaceAPI {
    var runningApplication: RunningApplicationHandle?
    var applicationURL: URL?
    private var launchCompletion: ((Result<RunningApplicationHandle, Error>) -> Void)?
    private(set) var openCount = 0

    init(runningApplication: RunningApplicationHandle? = nil, applicationURL: URL? = nil) {
        self.runningApplication = runningApplication
        self.applicationURL = applicationURL
    }

    func runningApplication(bundleIdentifier: String) -> RunningApplicationHandle? {
        runningApplication
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        applicationURL
    }

    func openApplication(
        at url: URL,
        completion: @escaping (Result<RunningApplicationHandle, Error>) -> Void
    ) {
        openCount += 1
        launchCompletion = completion
    }

    func completeLaunch(_ result: Result<RunningApplicationHandle, Error>) {
        let completion = launchCompletion
        launchCompletion = nil
        completion?(result)
    }
}
