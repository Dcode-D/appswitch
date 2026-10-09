import Foundation

public final class AppRuntime {
    private let hotKeyRegistrar: HotKeyRegistering
    private let coordinator: SwitchCoordinating
    private let permissionChecker: AccessibilityPermissionChecking
    private let log: (String) -> Void
    private var started = false
    private var terminated = false

    public init(
        hotKeyRegistrar: HotKeyRegistering,
        coordinator: SwitchCoordinating,
        permissionChecker: AccessibilityPermissionChecking,
        log: @escaping (String) -> Void
    ) {
        self.hotKeyRegistrar = hotKeyRegistrar
        self.coordinator = coordinator
        self.permissionChecker = permissionChecker
        self.log = log
    }

    public func start(configuration: AppConfiguration) throws {
        guard !started else { return }
        started = true

        if !permissionChecker.isTrusted(prompt: true) {
            log("Accessibility permission is not enabled; window cycling, hiding, focus, and cursor movement are disabled")
        }

        for binding in configuration.bindings {
            do {
                try hotKeyRegistrar.register(binding: binding) { [weak self] in
                    self?.coordinator.handle(binding)
                }
            } catch {
                log("could not register \(binding.hotKey.canonical): \(error)")
            }
        }
    }

    public func handleTermination() {
        guard !terminated else { return }
        terminated = true
        hotKeyRegistrar.unregisterAll()
    }
}
