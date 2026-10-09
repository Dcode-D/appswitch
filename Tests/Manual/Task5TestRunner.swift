import Foundation

// shortcut: macro-free fallback covers Task 5 only; remove after Command Line Tools can run Swift Testing.
@main
enum Task5TestRunner {
    private static var failures = 0

    static func main() {
        run("targets a window on the primary display", testPrimaryDisplay)
        run("targets a window on a negative-origin display", testNegativeOriginDisplay)
        run("chooses the display with the largest intersection", testSpanningWindow)
        run("rejects a window outside every display", testOutsideDisplays)
        run("clamps the target into the visible frame", testVisibleFrameClamp)
        run("focuses without moving when cursor movement is disabled", testMovementDisabled)
        run("moves after activation and focus", testOrderedMove)
        run("quietly skips a window without a frame", testMissingFrame)
        run("quietly skips a frame outside all displays", testInvalidTarget)
        run("logs activation and Accessibility failures", testFlowFailures)
        run("does not log permission denial per press", testPermissionDenied)
        run("cursor failure does not stop later switching", testCursorFailureRecovery)
        run("active app advances without reactivation", testActiveAppAdvances)
        run("last window hides the active app", testLastWindowHidesApp)
        run("failed app hiding is logged", testHideFailure)

        if failures == 0 {
            print("PASS: 15 Task 5 tests")
        } else {
            fputs("FAIL: \(failures) Task 5 test(s)\n", stderr)
            exit(1)
        }
    }

    private static let primary = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 40, width: 1000, height: 720)
    )
    private static let secondary = ScreenGeometry(
        frame: CGRect(x: -800, y: 0, width: 800, height: 600),
        visibleFrame: CGRect(x: -800, y: 0, width: 800, height: 560)
    )

    private static func testPrimaryDisplay() throws {
        let target = CursorGeometry.target(
            windowFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
            screens: [primary, secondary]
        )
        try require(target == CGPoint(x: 300, y: 250), "wrong primary-display target: \(String(describing: target))")
    }

    private static func testNegativeOriginDisplay() throws {
        let target = CursorGeometry.target(
            windowFrame: CGRect(x: -700, y: 100, width: 400, height: 200),
            screens: [primary, secondary]
        )
        try require(target == CGPoint(x: -500, y: 200), "wrong secondary-display target")
    }

    private static func testSpanningWindow() throws {
        let target = CursorGeometry.target(
            windowFrame: CGRect(x: -600, y: 100, width: 900, height: 300),
            screens: [primary, secondary]
        )
        try require(target == CGPoint(x: -150, y: 250), "largest intersecting display was not chosen")
    }

    private static func testOutsideDisplays() throws {
        let target = CursorGeometry.target(
            windowFrame: CGRect(x: 2000, y: 2000, width: 100, height: 100),
            screens: [primary, secondary]
        )
        try require(target == nil, "off-screen window produced a cursor target")
    }

    private static func testVisibleFrameClamp() throws {
        let target = CursorGeometry.target(
            windowFrame: CGRect(x: 300, y: 0, width: 200, height: 40),
            screens: [primary]
        )
        try require(target == CGPoint(x: 400, y: 40), "target was not clamped below reserved UI")
    }

    private static func testMovementDisabled() throws {
        let activator = FakeActivator(result: .success(42))
        let focuser = FakeFocuser(result: .success(CGRect(x: 100, y: 100, width: 200, height: 200)))
        let cursor = FakeCursorMover()
        let coordinator = coordinator(moveCursor: false, activator: activator, focuser: focuser, cursor: cursor)

        coordinator.handle(binding)

        try require(activator.bundleIdentifiers == [binding.bundleIdentifier], "application was not activated")
        try require(focuser.processIdentifiers == [42], "activated PID was not focused")
        try require(cursor.points.isEmpty, "cursor moved while disabled")
    }

    private static func testOrderedMove() throws {
        let events = EventRecorder()
        let activator = FakeActivator(result: .success(51), events: events)
        let focuser = FakeFocuser(
            result: .success(CGRect(x: 100, y: 100, width: 200, height: 200)),
            events: events
        )
        let cursor = FakeCursorMover(events: events)
        let coordinator = self.coordinator(
            moveCursor: true,
            activator: activator,
            focuser: focuser,
            cursor: cursor
        )

        coordinator.handle(binding)

        try require(events.values == ["activate", "focus", "move"], "switching order was \(events.values)")
        try require(cursor.points == [CGPoint(x: 200, y: 200)], "cursor received the wrong point")
    }

    private static func testMissingFrame() throws {
        var logs: [String] = []
        let cursor = FakeCursorMover()
        coordinator(
            moveCursor: true,
            activator: FakeActivator(result: .success(60)),
            focuser: FakeFocuser(result: .success(nil)),
            cursor: cursor,
            log: { logs.append($0) }
        ).handle(binding)

        try require(cursor.points.isEmpty, "cursor moved without a window frame")
        try require(logs.isEmpty, "windowless success was logged as a failure")
    }

    private static func testInvalidTarget() throws {
        let cursor = FakeCursorMover()
        let coordinator = SwitchCoordinator(
            moveCursor: true,
            activator: FakeActivator(result: .success(61)),
            windowFocuser: FakeFocuser(result: .success(CGRect(x: 5000, y: 5000, width: 100, height: 100))),
            cursorMover: cursor,
            screens: { [primary] },
            log: { _ in }
        )

        coordinator.handle(binding)

        try require(cursor.points.isEmpty, "cursor moved for an off-screen frame")
    }

    private static func testFlowFailures() throws {
        var activationLogs: [String] = []
        coordinator(
            moveCursor: true,
            activator: FakeActivator(result: .failure(.activationFailed(bundleIdentifier: binding.bundleIdentifier))),
            focuser: FakeFocuser(result: .success(nil)),
            cursor: FakeCursorMover(),
            log: { activationLogs.append($0) }
        ).handle(binding)

        var focusLogs: [String] = []
        coordinator(
            moveCursor: true,
            activator: FakeActivator(result: .success(70)),
            focuser: FakeFocuser(result: .failure(.accessibilityFailure("boom"))),
            cursor: FakeCursorMover(),
            log: { focusLogs.append($0) }
        ).handle(binding)

        try require(activationLogs.count == 1 && activationLogs[0].contains("activate"), "activation failure was not logged")
        try require(focusLogs.count == 1 && focusLogs[0].contains("focus"), "focus failure was not logged")
    }

    private static func testPermissionDenied() throws {
        var logs: [String] = []
        coordinator(
            moveCursor: true,
            activator: FakeActivator(result: .success(80)),
            focuser: FakeFocuser(result: .failure(.permissionDenied)),
            cursor: FakeCursorMover(),
            log: { logs.append($0) }
        ).handle(binding)

        try require(logs.isEmpty, "permission denial was logged for each press")
    }

    private static func testCursorFailureRecovery() throws {
        var logs: [String] = []
        let cursor = FakeCursorMover(failuresRemaining: 1)
        let coordinator = self.coordinator(
            moveCursor: true,
            activator: FakeActivator(result: .success(90)),
            focuser: FakeFocuser(result: .success(CGRect(x: 100, y: 100, width: 200, height: 200))),
            cursor: cursor,
            log: { logs.append($0) }
        )

        coordinator.handle(binding)
        coordinator.handle(binding)

        try require(cursor.points.count == 2, "later shortcut handling stopped after cursor failure")
        try require(logs.count == 1 && logs[0].contains("cursor"), "cursor failure was not logged once")
    }

    private static func testActiveAppAdvances() throws {
        let events = EventRecorder()
        let activator = FakeActivator(result: .success(1), events: events)
        let focuser = FakeFocuser(
            result: .success(nil),
            cycleResult: .success(.focused(CGRect(x: 100, y: 100, width: 200, height: 200))),
            events: events
        )
        let cursor = FakeCursorMover(events: events)
        let applications = FakeActiveApplicationManager(processIdentifier: 101, events: events)
        let coordinator = SwitchCoordinator(
            moveCursor: true,
            activator: activator,
            windowFocuser: focuser,
            cursorMover: cursor,
            activeApplicationManager: applications,
            screens: { [primary] },
            log: { _ in }
        )

        coordinator.handle(binding)

        try require(activator.bundleIdentifiers.isEmpty, "active app was activated again")
        try require(focuser.cycleProcessIdentifiers == [101], "active app did not advance its window")
        try require(events.values == ["cycle", "move"], "active cycle order was \(events.values)")
    }

    private static func testLastWindowHidesApp() throws {
        let applications = FakeActiveApplicationManager(processIdentifier: 102)
        let coordinator = SwitchCoordinator(
            moveCursor: false,
            activator: FakeActivator(result: .success(1)),
            windowFocuser: FakeFocuser(
                result: .success(nil),
                cycleResult: .success(.endOfWindows)
            ),
            cursorMover: FakeCursorMover(),
            activeApplicationManager: applications,
            screens: { [primary] },
            log: { _ in }
        )

        coordinator.handle(binding)

        try require(applications.hiddenProcessIdentifiers == [102], "last window did not hide the app")
    }

    private static func testHideFailure() throws {
        var logs: [String] = []
        let applications = FakeActiveApplicationManager(processIdentifier: 103, hideSucceeds: false)
        let coordinator = SwitchCoordinator(
            moveCursor: false,
            activator: FakeActivator(result: .success(1)),
            windowFocuser: FakeFocuser(
                result: .success(nil),
                cycleResult: .success(.endOfWindows)
            ),
            cursorMover: FakeCursorMover(),
            activeApplicationManager: applications,
            screens: { [primary] },
            log: { logs.append($0) }
        )

        coordinator.handle(binding)

        try require(logs.count == 1 && logs[0].contains("hide"), "hide failure was not logged")
    }

    private static var binding: AppBinding {
        AppBinding(
            hotKey: HotKey(keyCode: 18, modifiers: 256, canonical: "cmd+1"),
            bundleIdentifier: "com.example.App"
        )
    }

    private static func coordinator(
        moveCursor: Bool,
        activator: ApplicationActivating,
        focuser: WindowFocusing,
        cursor: CursorMoving,
        log: @escaping (String) -> Void = { _ in }
    ) -> SwitchCoordinator {
        SwitchCoordinator(
            moveCursor: moveCursor,
            activator: activator,
            windowFocuser: focuser,
            cursorMover: cursor,
            screens: { [primary, secondary] },
            log: log
        )
    }

    private static func run(_ name: String, _ test: () throws -> Void) {
        do {
            try test()
            print("PASS: \(name)")
        } catch {
            failures += 1
            fputs("FAIL: \(name): \(error)\n", stderr)
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) throws {
        guard condition() else { throw TestFailure(message()) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private final class EventRecorder {
    var values: [String] = []
}

private final class FakeActivator: ApplicationActivating {
    let result: Result<pid_t, ApplicationActivationError>
    let events: EventRecorder?
    private(set) var bundleIdentifiers: [String] = []

    init(result: Result<pid_t, ApplicationActivationError>, events: EventRecorder? = nil) {
        self.result = result
        self.events = events
    }

    func activate(
        bundleIdentifier: String,
        completion: @escaping (Result<pid_t, ApplicationActivationError>) -> Void
    ) -> Bool {
        bundleIdentifiers.append(bundleIdentifier)
        events?.values.append("activate")
        completion(result)
        return true
    }
}

private final class FakeFocuser: WindowFocusing {
    let result: Result<CGRect?, WindowFocusError>
    let cycleResult: Result<WindowTraversalOutcome, WindowFocusError>
    let events: EventRecorder?
    private(set) var processIdentifiers: [pid_t] = []
    private(set) var cycleProcessIdentifiers: [pid_t] = []

    init(
        result: Result<CGRect?, WindowFocusError>,
        cycleResult: Result<WindowTraversalOutcome, WindowFocusError> = .success(.noWindow),
        events: EventRecorder? = nil
    ) {
        self.result = result
        self.cycleResult = cycleResult
        self.events = events
    }

    func focusBestWindow(processIdentifier: pid_t) -> Result<CGRect?, WindowFocusError> {
        processIdentifiers.append(processIdentifier)
        events?.values.append("focus")
        return result
    }

    func focusNextWindow(
        processIdentifier: pid_t
    ) -> Result<WindowTraversalOutcome, WindowFocusError> {
        cycleProcessIdentifiers.append(processIdentifier)
        events?.values.append("cycle")
        return cycleResult
    }
}

private final class FakeActiveApplicationManager: ActiveApplicationManaging {
    let processIdentifier: pid_t?
    let hideSucceeds: Bool
    let events: EventRecorder?
    private(set) var hiddenProcessIdentifiers: [pid_t] = []

    init(
        processIdentifier: pid_t?,
        hideSucceeds: Bool = true,
        events: EventRecorder? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.hideSucceeds = hideSucceeds
        self.events = events
    }

    func frontmostProcessIdentifier(bundleIdentifier: String) -> pid_t? {
        processIdentifier
    }

    func hide(processIdentifier: pid_t) -> Bool {
        hiddenProcessIdentifiers.append(processIdentifier)
        events?.values.append("hide")
        return hideSucceeds
    }
}

private enum FakeCursorError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "cursor failed" }
}

private final class FakeCursorMover: CursorMoving {
    let events: EventRecorder?
    var failuresRemaining: Int
    private(set) var points: [CGPoint] = []

    init(events: EventRecorder? = nil, failuresRemaining: Int = 0) {
        self.events = events
        self.failuresRemaining = failuresRemaining
    }

    func move(to point: CGPoint) throws {
        points.append(point)
        events?.values.append("move")
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw FakeCursorError.failed
        }
    }
}
