import ApplicationServices
import Foundation

public protocol AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool
}

public struct SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    public init() {}

    public func isTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
