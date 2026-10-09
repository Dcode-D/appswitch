import AppKit
import Foundation

public protocol RunningApplicationHandle: AnyObject {
    var processIdentifier: pid_t { get }
    var isRegular: Bool { get }
    func activateForSwitching() -> Bool
}

public protocol WorkspaceAPI: AnyObject {
    func runningApplication(bundleIdentifier: String) -> RunningApplicationHandle?
    func applicationURL(bundleIdentifier: String) -> URL?
    func openApplication(
        at url: URL,
        completion: @escaping (Result<RunningApplicationHandle, Error>) -> Void
    )
}

public enum WorkspaceAPIError: Error, LocalizedError {
    case launchReturnedNoApplication

    public var errorDescription: String? {
        "macOS did not return a running application"
    }
}

extension NSRunningApplication: RunningApplicationHandle {
    public var isRegular: Bool {
        activationPolicy == .regular
    }

    public func activateForSwitching() -> Bool {
        activate()
    }
}

public final class NSWorkspaceAPI: WorkspaceAPI {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func runningApplication(bundleIdentifier: String) -> RunningApplicationHandle? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: \.isRegular)
    }

    public func applicationURL(bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func openApplication(
        at url: URL,
        completion: @escaping (Result<RunningApplicationHandle, Error>) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        workspace.openApplication(at: url, configuration: configuration) { application, error in
            if let error {
                completion(.failure(error))
            } else if let application {
                completion(.success(application))
            } else {
                completion(.failure(WorkspaceAPIError.launchReturnedNoApplication))
            }
        }
    }
}
