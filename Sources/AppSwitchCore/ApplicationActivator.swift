import Foundation

public enum ApplicationActivationError: Error, Equatable, CustomStringConvertible {
    case applicationNotFound(bundleIdentifier: String)
    case launchFailed(bundleIdentifier: String, reason: String)
    case activationFailed(bundleIdentifier: String)

    public var description: String {
        switch self {
        case let .applicationNotFound(bundleIdentifier):
            return "no application is installed for bundle identifier '\(bundleIdentifier)'"
        case let .launchFailed(bundleIdentifier, reason):
            return "could not launch '\(bundleIdentifier)': \(reason)"
        case let .activationFailed(bundleIdentifier):
            return "could not activate '\(bundleIdentifier)'"
        }
    }
}

public protocol ApplicationActivating: AnyObject {
    @discardableResult
    func activate(
        bundleIdentifier: String,
        completion: @escaping (Result<pid_t, ApplicationActivationError>) -> Void
    ) -> Bool
}

public final class ApplicationActivator: ApplicationActivating {
    private let workspace: WorkspaceAPI
    private var pendingBundleIdentifiers = Set<String>()

    public init(workspace: WorkspaceAPI = NSWorkspaceAPI()) {
        self.workspace = workspace
    }

    @discardableResult
    public func activate(
        bundleIdentifier: String,
        completion: @escaping (Result<pid_t, ApplicationActivationError>) -> Void
    ) -> Bool {
        guard !pendingBundleIdentifiers.contains(bundleIdentifier) else {
            return false
        }

        if let application = workspace.runningApplication(bundleIdentifier: bundleIdentifier) {
            completeActivation(application, bundleIdentifier: bundleIdentifier, completion: completion)
            return true
        }

        guard let url = workspace.applicationURL(bundleIdentifier: bundleIdentifier) else {
            completion(.failure(.applicationNotFound(bundleIdentifier: bundleIdentifier)))
            return true
        }

        pendingBundleIdentifiers.insert(bundleIdentifier)
        workspace.openApplication(at: url) { [weak self] result in
            guard let self else { return }
            self.pendingBundleIdentifiers.remove(bundleIdentifier)
            switch result {
            case let .success(application):
                self.completeActivation(
                    application,
                    bundleIdentifier: bundleIdentifier,
                    completion: completion
                )
            case let .failure(error):
                completion(
                    .failure(
                        .launchFailed(
                            bundleIdentifier: bundleIdentifier,
                            reason: error.localizedDescription
                        )
                    )
                )
            }
        }
        return true
    }

    private func completeActivation(
        _ application: RunningApplicationHandle,
        bundleIdentifier: String,
        completion: (Result<pid_t, ApplicationActivationError>) -> Void
    ) {
        guard application.isRegular, application.activateForSwitching() else {
            completion(.failure(.activationFailed(bundleIdentifier: bundleIdentifier)))
            return
        }
        completion(.success(application.processIdentifier))
    }
}
