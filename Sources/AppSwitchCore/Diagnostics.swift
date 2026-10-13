import Foundation

public struct DiagnosticReport: Equatable, Sendable {
    public let messages: [String]
    public let exitCode: Int32

    public init(messages: [String], exitCode: Int32) {
        self.messages = messages
        self.exitCode = exitCode
    }
}

public final class Diagnostics {
    private let permissionChecker: AccessibilityPermissionChecking
    private let workspace: WorkspaceAPI
    private let hotKeyRegistrar: HotKeyRegistering

    public init(
        permissionChecker: AccessibilityPermissionChecking,
        workspace: WorkspaceAPI,
        hotKeyRegistrar: HotKeyRegistering
    ) {
        self.permissionChecker = permissionChecker
        self.workspace = workspace
        self.hotKeyRegistrar = hotKeyRegistrar
    }

    public func check(configuration: AppConfiguration) -> DiagnosticReport {
        var messages: [String] = []
        var isReady = true

        if permissionChecker.isTrusted(prompt: true) {
            messages.append("Accessibility permission: ready")
        } else {
            messages.append("Accessibility permission: required; enable appswitch in System Settings > Privacy & Security > Accessibility")
            isReady = false
        }

        for binding in configuration.bindings {
            if workspace.applicationURL(bundleIdentifier: binding.bundleIdentifier) != nil
                || workspace.runningApplication(bundleIdentifier: binding.bundleIdentifier) != nil {
                messages.append("\(binding.bundleIdentifier): installed")
            } else {
                messages.append("\(binding.bundleIdentifier): application not found")
                isReady = false
            }

            switch hotKeyRegistrar.probe(binding.hotKey) {
            case .success:
                messages.append("\(binding.hotKey.canonical): available")
            case let .failure(error):
                messages.append("\(binding.hotKey.canonical): unavailable (\(error))")
                isReady = false
            }
        }

        for hotKey in configuration.quickSwitchHotKeys {
            switch hotKeyRegistrar.probe(hotKey) {
            case .success:
                messages.append("\(hotKey.canonical): available")
            case let .failure(error):
                messages.append("\(hotKey.canonical): unavailable (\(error))")
                isReady = false
            }
        }

        return DiagnosticReport(messages: messages, exitCode: isReady ? 0 : 3)
    }
}
