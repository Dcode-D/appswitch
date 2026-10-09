import Testing
@testable import AppSwitchCore

@Suite("HotKeyRegistrarTests")
struct HotKeyRegistrarTests {
    @Test func dispatchesOnlyTheActionMatchingTheNativeID() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        var firstCount = 0
        var secondCount = 0

        try registrar.register(binding: binding("cmd+a")) { firstCount += 1 }
        try registrar.register(binding: binding("cmd+b")) { secondCount += 1 }
        let ids = api.registrations.map(\.id)

        #expect(ids.count == 2)
        #expect(ids[0] != ids[1])
        api.fire(id: ids[1])
        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    @Test func reportsTheCanonicalShortcutWhenNativeRegistrationFails() throws {
        let api = FakeCarbonHotKeyAPI()
        api.rejectedKeyCode = 11
        let registrar = try CarbonHotKeyRegistrar(api: api)

        do {
            try registrar.register(binding: binding("option+cmd+b")) {}
            Issue.record("Expected registration to fail")
        } catch let error as HotKeyRegistrationError {
            #expect(error == .registrationFailed(shortcut: "cmd+option+b", status: -9876))
        } catch {
            Issue.record("Expected HotKeyRegistrationError, got \(error)")
        }
    }

    @Test func failedRegistrationDoesNotRemoveSuccessfulBindings() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        var acceptedCount = 0
        try registrar.register(binding: binding("cmd+a")) { acceptedCount += 1 }
        api.rejectedKeyCode = 11

        #expect(throws: HotKeyRegistrationError.self) {
            try registrar.register(binding: binding("cmd+b")) {}
        }
        api.fire(id: api.registrations[0].id)

        #expect(acceptedCount == 1)
    }

    @Test func probeImmediatelyUnregistersSuccessfulTemporaryBinding() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        let hotKey = try ShortcutParser.parse("control+1")

        let result = registrar.probe(hotKey)

        if case .failure(let error) = result {
            Issue.record("Expected probe success, got \(error)")
        }
        #expect(api.registrations.count == 1)
        #expect(api.unregistered == [api.registrations[0].token])
    }

    @Test func unregisterAllReleasesEachSuccessfulBindingOnce() throws {
        let api = FakeCarbonHotKeyAPI()
        let registrar = try CarbonHotKeyRegistrar(api: api)
        try registrar.register(binding: binding("cmd+a")) {}
        try registrar.register(binding: binding("cmd+b")) {}

        registrar.unregisterAll()
        registrar.unregisterAll()

        #expect(api.unregistered == api.registrations.map(\.token))
    }

    private func binding(_ shortcut: String) throws -> AppBinding {
        AppBinding(
            hotKey: try ShortcutParser.parse(shortcut),
            bundleIdentifier: "com.example.App"
        )
    }
}

private final class FakeCarbonHotKeyAPI: CarbonHotKeyAPI {
    struct Registration {
        let keyCode: UInt32
        let modifiers: UInt32
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
        registrations.append(
            Registration(keyCode: keyCode, modifiers: modifiers, id: id, token: token)
        )
        return token
    }

    func unregister(_ token: CarbonHotKeyToken) {
        unregistered.append(token)
    }

    func fire(id: UInt32) {
        eventHandler?(id)
    }
}
