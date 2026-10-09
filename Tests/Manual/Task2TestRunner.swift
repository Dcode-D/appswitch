import Foundation

// shortcut: macro-free fallback covers Task 2 only; remove after Command Line Tools can run Swift Testing.
@main
enum Task2TestRunner {
    private static var failures = 0

    static func main() {
        run("dispatches only the matching action", testDispatch)
        run("reports the rejected canonical shortcut", testRegistrationFailure)
        run("keeps successful bindings after a rejection", testPartialRegistration)
        run("probe unregisters its temporary binding", testProbeCleanup)
        run("unregisterAll releases each binding once", testUnregisterAll)

        if failures == 0 {
            print("PASS: 5 Task 2 tests")
        } else {
            fputs("FAIL: \(failures) Task 2 test(s)\n", stderr)
            exit(1)
        }
    }

    private static func testDispatch() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        var firstCount = 0
        var secondCount = 0
        try registrar.register(binding: try binding("cmd+a")) { firstCount += 1 }
        try registrar.register(binding: try binding("cmd+b")) { secondCount += 1 }

        try require(api.registrations.count == 2, "expected two registrations")
        try require(api.registrations[0].id != api.registrations[1].id, "IDs must be unique")
        api.fire(id: api.registrations[1].id)
        try require(firstCount == 0, "first action was called")
        try require(secondCount == 1, "second action was not called exactly once")
    }

    private static func testRegistrationFailure() throws {
        let api = FakeCarbonHotKeyAPI()
        api.rejectedKeyCode = 11
        let registrar = try CarbonHotKeyRegistrar(api: api)

        do {
            try registrar.register(binding: try binding("option+cmd+b")) {}
            throw TestFailure("registration unexpectedly succeeded")
        } catch let error as HotKeyRegistrationError {
            try require(
                error == .registrationFailed(shortcut: "cmd+option+b", status: -9876),
                "wrong registration error: \(error)"
            )
        }
    }

    private static func testPartialRegistration() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        var acceptedCount = 0
        try registrar.register(binding: try binding("cmd+a")) { acceptedCount += 1 }
        api.rejectedKeyCode = 11

        do {
            try registrar.register(binding: try binding("cmd+b")) {}
            throw TestFailure("rejected registration unexpectedly succeeded")
        } catch is HotKeyRegistrationError {}

        api.fire(id: api.registrations[0].id)
        try require(acceptedCount == 1, "successful binding stopped dispatching")
    }

    private static func testProbeCleanup() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        let result = registrar.probe(try ShortcutParser.parse("control+1"))

        if case .failure(let error) = result {
            throw TestFailure("probe failed: \(error)")
        }
        try require(api.registrations.count == 1, "probe did not register once")
        try require(
            api.unregistered == [api.registrations[0].token],
            "probe did not immediately unregister its token"
        )
    }

    private static func testUnregisterAll() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        try registrar.register(binding: try binding("cmd+a")) {}
        try registrar.register(binding: try binding("cmd+b")) {}

        registrar.unregisterAll()
        registrar.unregisterAll()

        try require(
            api.unregistered == api.registrations.map(\.token),
            "bindings were not each unregistered exactly once"
        )
    }

    private static func binding(_ shortcut: String) throws -> AppBinding {
        AppBinding(
            hotKey: try ShortcutParser.parse(shortcut),
            bundleIdentifier: "com.example.App"
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

private final class FakeCarbonHotKeyAPI: CarbonHotKeyAPI {
    struct Registration {
        let id: UInt32
        let token: CarbonHotKeyToken
    }

    var rejectedKeyCode: UInt32?
    private var eventHandler: ((UInt32) -> Void)?
    private(set) var registrations: [Registration] = []
    private(set) var unregistered: [CarbonHotKeyToken] = []

    func installEventHandler(_ handler: @escaping (UInt32) -> Void) throws {
        eventHandler = handler
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws -> CarbonHotKeyToken {
        if keyCode == rejectedKeyCode {
            throw CarbonHotKeyAPIError.status(-9876)
        }
        let token = CarbonHotKeyToken(id: id)
        registrations.append(Registration(id: id, token: token))
        return token
    }

    func unregister(_ token: CarbonHotKeyToken) {
        unregistered.append(token)
    }

    func fire(id: UInt32) {
        eventHandler?(id)
    }
}
