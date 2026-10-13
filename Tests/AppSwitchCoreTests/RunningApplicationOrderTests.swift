import Foundation
import Testing
@testable import AppSwitchCore

@Suite("RunningApplicationOrderTests")
struct RunningApplicationOrderTests {
    @Test func assignsSlotsFromNewestToOldestLaunch() {
        let applications = [
            application("com.example.Three", launchedAt: 30),
            application("com.example.One", launchedAt: 10),
            application("com.example.Two", launchedAt: 20),
        ]

        var order = RunningApplicationOrder(applications: applications)

        #expect(order.bundleIdentifier(
            at: 0,
            among: applications,
            frontmostBundleIdentifier: nil
        ) == "com.example.Three")
        #expect(order.bundleIdentifier(
            at: 2,
            among: applications,
            frontmostBundleIdentifier: nil
        ) == "com.example.One")
    }

    @Test func keepsTheFrontmostAppInItsSlotButMakesThatSlotANoOp() {
        let applications = [
            application("com.example.One", launchedAt: 10),
            application("com.example.Two", launchedAt: 20),
        ]

        var order = RunningApplicationOrder(applications: applications)

        #expect(order.bundleIdentifier(
            at: 0,
            among: applications,
            frontmostBundleIdentifier: "com.example.Two"
        ) == nil)
        #expect(order.bundleIdentifier(
            at: 1,
            among: applications,
            frontmostBundleIdentifier: "com.example.Two"
        ) == "com.example.One")
    }

    @Test func keepsAppsWithoutLaunchDatesInStableFallbackOrder() {
        let applications = [
            application("com.example.UnknownOne", launchedAt: nil),
            application("com.example.Known", launchedAt: 20),
            application("com.example.UnknownTwo", launchedAt: nil),
        ]

        let order = RunningApplicationOrder(applications: applications)

        #expect(order.bundleIdentifiers == [
            "com.example.Known",
            "com.example.UnknownOne",
            "com.example.UnknownTwo",
        ])
    }

    @Test func insertsNewAppsAtTheFront() {
        let initialApplications = [
            application("com.example.Known", launchedAt: 10),
            application("com.example.Unknown", launchedAt: nil),
        ]
        var order = RunningApplicationOrder(applications: initialApplications)
        let currentApplications = initialApplications + [
            application("com.example.New", launchedAt: 20),
        ]

        _ = order.bundleIdentifier(
            at: 0,
            among: currentApplications,
            frontmostBundleIdentifier: nil
        )

        #expect(order.bundleIdentifiers == [
            "com.example.New",
            "com.example.Known",
            "com.example.Unknown",
        ])
    }

    @Test func keepsABundleSlotUntilItsLastRegularProcessExits() {
        let initialApplications = [
            application("com.example.A", launchedAt: 10, processIdentifier: 1),
            application("com.example.B", launchedAt: 20, processIdentifier: 2),
            application("com.example.A", launchedAt: 30, processIdentifier: 3),
        ]
        var order = RunningApplicationOrder(applications: initialApplications)
        let afterOldestProcessExits = [
            application("com.example.B", launchedAt: 20, processIdentifier: 2),
            application("com.example.A", launchedAt: 30, processIdentifier: 3),
        ]

        #expect(order.bundleIdentifier(
            at: 0,
            among: afterOldestProcessExits,
            frontmostBundleIdentifier: nil
        ) == "com.example.B")
        #expect(order.bundleIdentifiers == ["com.example.B", "com.example.A"])

        #expect(order.bundleIdentifier(
            at: 0,
            among: [application("com.example.B", launchedAt: 20, processIdentifier: 2)],
            frontmostBundleIdentifier: nil
        ) == "com.example.B")
        #expect(order.bundleIdentifiers == ["com.example.B"])
    }

    @Test func ordersMultipleNewAppsByLaunchDateBeforePrependingThem() {
        let initialApplications = [
            application("com.example.Existing", launchedAt: 10, processIdentifier: 1),
        ]
        var order = RunningApplicationOrder(applications: initialApplications)
        let currentApplications = [
            application("com.example.Newer", launchedAt: 30, processIdentifier: 3),
            application("com.example.Existing", launchedAt: 10, processIdentifier: 1),
            application("com.example.Older", launchedAt: 20, processIdentifier: 2),
        ]

        _ = order.bundleIdentifier(
            at: 0,
            among: currentApplications,
            frontmostBundleIdentifier: nil
        )

        #expect(order.bundleIdentifiers == [
            "com.example.Newer",
            "com.example.Older",
            "com.example.Existing",
        ])
    }

    @Test func movesAnAppToTheEndWhenAllItsProcessesWereReplaced() {
        var order = RunningApplicationOrder(applications: [
            application("com.example.A", launchedAt: 10, processIdentifier: 1),
            application("com.example.B", launchedAt: 20, processIdentifier: 2),
        ])

        _ = order.bundleIdentifier(
            at: 0,
            among: [
                application("com.example.A", launchedAt: 30, processIdentifier: 3),
                application("com.example.B", launchedAt: 20, processIdentifier: 2),
            ],
            frontmostBundleIdentifier: nil
        )

        #expect(order.bundleIdentifiers == ["com.example.A", "com.example.B"])
    }

    private func application(
        _ bundleIdentifier: String,
        launchedAt timestamp: TimeInterval?,
        processIdentifier: Int32? = nil
    ) -> RunningApplicationIdentity {
        RunningApplicationIdentity(
            bundleIdentifier: bundleIdentifier,
            launchDate: timestamp.map(Date.init(timeIntervalSince1970:)),
            processIdentifier: processIdentifier
        )
    }
}
