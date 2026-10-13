import Testing
@testable import AppSwitchCore

@Suite("AppRuntimeTests")
struct AppRuntimeTests {
    @Test func quickSwitchHotKeyDispatchesToTheSelectedRunningApplication() throws {
        let hotKey = try ShortcutParser.parse("cmd+1")
        let registrar = RuntimeFakeRegistrar()
        let coordinator = RuntimeFakeCoordinator()
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: RuntimeFakePermissionChecker(),
            quickSwitchSelector: RuntimeFakeSelector(bundleIdentifiers: ["com.example.Recent"]),
            log: { _ in }
        )
        let configuration = AppConfiguration(
            moveCursor: false,
            bindings: [],
            quickSwitchHotKeys: [hotKey]
        )

        try runtime.start(configuration: configuration)
        registrar.trigger(shortcut: "cmd+1")

        #expect(coordinator.bindings.map(\.bundleIdentifier) == ["com.example.Recent"])
    }

    @Test func commandZeroDispatchesToTheTenthRunningApplication() throws {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let registrar = RuntimeFakeRegistrar()
        let coordinator = RuntimeFakeCoordinator()
        let runtime = AppRuntime(
            hotKeyRegistrar: registrar,
            coordinator: coordinator,
            permissionChecker: RuntimeFakePermissionChecker(),
            quickSwitchSelector: RuntimeFakeSelector(
                bundleIdentifiers: (1...10).map { "com.example.App\($0)" }
            ),
            log: { _ in }
        )
        let configuration = AppConfiguration(
            moveCursor: false,
            bindings: [],
            quickSwitchHotKeys: try keys.map { try ShortcutParser.parse("cmd+\($0)") }
        )

        try runtime.start(configuration: configuration)
        registrar.trigger(shortcut: "cmd+0")

        #expect(coordinator.bindings.map(\.bundleIdentifier) == ["com.example.App10"])
    }
}

private final class RuntimeFakeRegistrar: HotKeyRegistering {
    private var actions: [String: () -> Void] = [:]

    func register(binding: AppBinding, action: @escaping () -> Void) throws {
        actions[binding.hotKey.canonical] = action
    }

    func probe(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError> { .success(()) }
    func unregisterAll() { actions.removeAll() }
    func trigger(shortcut: String) { actions[shortcut]?() }
}

private final class RuntimeFakeCoordinator: SwitchCoordinating {
    private(set) var bindings: [AppBinding] = []
    func handle(_ binding: AppBinding) { bindings.append(binding) }
}

private final class RuntimeFakePermissionChecker: AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool { true }
}

private final class RuntimeFakeSelector: RunningApplicationSelecting {
    let bundleIdentifiers: [String]
    init(bundleIdentifiers: [String]) { self.bundleIdentifiers = bundleIdentifiers }
    func bundleIdentifier(at index: Int) -> String? {
        bundleIdentifiers.indices.contains(index) ? bundleIdentifiers[index] : nil
    }
}
