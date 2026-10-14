import AppKit
import Foundation

public struct RunningApplicationIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let localizedName: String?
    public let launchDate: Date?
    public let processIdentifier: Int32?

    public init(
        bundleIdentifier: String,
        localizedName: String? = nil,
        launchDate: Date?,
        processIdentifier: Int32? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.launchDate = launchDate
        self.processIdentifier = processIdentifier
    }
}

public struct RunningApplicationOrder: Sendable {
    public private(set) var bundleIdentifiers: [String]
    private var processIdentifiersByBundle: [String: Set<Int32>]

    public init(applications: [RunningApplicationIdentity]) {
        bundleIdentifiers = Self.orderedBundleIdentifiers(from: applications)
        processIdentifiersByBundle = Self.processIdentifiers(from: applications)
    }

    private static func orderedBundleIdentifiers(
        from applications: [RunningApplicationIdentity]
    ) -> [String] {
        var grouped: [String: (firstIndex: Int, launchDate: Date?)] = [:]
        for (index, application) in applications.enumerated() {
            if let existing = grouped[application.bundleIdentifier] {
                let dates = [existing.launchDate, application.launchDate].compactMap { $0 }
                grouped[application.bundleIdentifier] = (
                    firstIndex: existing.firstIndex,
                    launchDate: dates.min()
                )
            } else {
                grouped[application.bundleIdentifier] = (
                    firstIndex: index,
                    launchDate: application.launchDate
                )
            }
        }

        return grouped.sorted { left, right in
            switch (left.value.launchDate, right.value.launchDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.value.firstIndex < right.value.firstIndex
            }
        }.map(\.key)
    }

    private static func processIdentifiers(
        from applications: [RunningApplicationIdentity]
    ) -> [String: Set<Int32>] {
        var result: [String: Set<Int32>] = [:]
        for application in applications {
            guard let processIdentifier = application.processIdentifier else { continue }
            result[application.bundleIdentifier, default: []].insert(processIdentifier)
        }
        return result
    }

    public mutating func bundleIdentifier(
        at index: Int,
        among applications: [RunningApplicationIdentity],
        frontmostBundleIdentifier: String?
    ) -> String? {
        guard index >= 0 else { return nil }
        reconcile(with: applications)
        guard bundleIdentifiers.indices.contains(index) else { return nil }
        let bundleIdentifier = bundleIdentifiers[index]
        return bundleIdentifier == frontmostBundleIdentifier ? nil : bundleIdentifier
    }

    public mutating func applications(
        among applications: [RunningApplicationIdentity]
    ) -> [RunningApplicationIdentity] {
        reconcile(with: applications)
        let applicationsByBundle = Dictionary(
            applications.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, second in
                first.localizedName == nil ? second : first
            }
        )
        return bundleIdentifiers.compactMap { applicationsByBundle[$0] }
    }

    private mutating func reconcile(with applications: [RunningApplicationIdentity]) {
        let currentBundleIdentifiers = Self.orderedBundleIdentifiers(from: applications)
        let currentSet = Set(currentBundleIdentifiers)
        let currentProcessIdentifiers = Self.processIdentifiers(from: applications)
        let replacedBundles = Set(bundleIdentifiers.filter { bundleIdentifier in
            guard let previous = processIdentifiersByBundle[bundleIdentifier],
                  !previous.isEmpty,
                  let current = currentProcessIdentifiers[bundleIdentifier],
                  !current.isEmpty
            else {
                return false
            }
            return previous.isDisjoint(with: current)
        })

        bundleIdentifiers.removeAll {
            !currentSet.contains($0) || replacedBundles.contains($0)
        }
        let orderedSet = Set(bundleIdentifiers)
        let newlyRunning = currentBundleIdentifiers.filter {
            !orderedSet.contains($0)
        }
        bundleIdentifiers = newlyRunning + bundleIdentifiers
        processIdentifiersByBundle = currentProcessIdentifiers
    }
}

public protocol RunningApplicationSelecting: AnyObject {
    func bundleIdentifier(at index: Int) -> String?
}

public final class NSWorkspaceRunningApplicationSelector: RunningApplicationSelecting {
    private let workspace: NSWorkspace
    private var order: RunningApplicationOrder

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        order = RunningApplicationOrder(
            applications: Self.regularApplications(in: workspace)
        )
    }

    public func bundleIdentifier(at index: Int) -> String? {
        order.bundleIdentifier(
            at: index,
            among: Self.regularApplications(in: workspace),
            frontmostBundleIdentifier: workspace.frontmostApplication?.bundleIdentifier
        )
    }

    public func applications() -> [RunningApplicationIdentity] {
        let applications = Self.regularApplications(in: workspace)
        return order.applications(among: applications)
    }

    private static func regularApplications(
        in workspace: NSWorkspace
    ) -> [RunningApplicationIdentity] {
        workspace.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular,
                  let bundleIdentifier = application.bundleIdentifier
            else {
                return nil
            }
            return RunningApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                localizedName: application.localizedName,
                launchDate: application.launchDate,
                processIdentifier: application.processIdentifier
            )
        }
    }
}
