import AppKit
import Foundation

public protocol ActiveApplicationManaging: AnyObject {
    func frontmostProcessIdentifier(bundleIdentifier: String) -> pid_t?
    func hide(processIdentifier: pid_t) -> Bool
}

public final class NSWorkspaceActiveApplicationManager: ActiveApplicationManaging {
    public init() {}

    public func frontmostProcessIdentifier(bundleIdentifier: String) -> pid_t? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == bundleIdentifier
        else {
            return nil
        }
        return application.processIdentifier
    }

    public func hide(processIdentifier: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: processIdentifier)?.hide() ?? false
    }
}
