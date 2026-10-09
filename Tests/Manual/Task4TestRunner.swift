import Foundation

// shortcut: macro-free fallback covers Task 4 only; remove after Command Line Tools can run Swift Testing.
@main
enum Task4TestRunner {
    private static var failures = 0

    static func main() {
        run("focused normal window wins", testFocusedNormalWindow)
        run("focused minimized window is selected", testFocusedMinimizedWindow)
        run("non-minimized normal window is the fallback", testNonMinimizedFallback)
        run("minimized normal window is the last fallback", testMinimizedFallback)
        run("dialogs and empty lists have no selection", testNoUsableWindow)
        run("permission denial avoids Accessibility calls", testPermissionDenied)
        run("restores focuses and raises the selected window", testFocusFlow)
        run("windowless app returns no frame", testWindowlessApp)
        run("missing frame returns success without a cursor target", testMissingFrame)
        run("Accessibility operation failure is reported", testAccessibilityFailure)
        run("first-window focus ignores the previously focused window", testFocusFirstWindow)
        run("window cycling advances to the next normal window", testCycleNextWindow)
        run("window cycling reports the last window", testCycleEnd)
        run("single focused window reports the end", testSingleWindowEnd)
        run("window cycling restores a minimized next window", testCycleMinimizedWindow)
        run("window cycling uses the application's focused-window reference", testFocusedWindowReference)

        if failures == 0 {
            print("PASS: 16 Task 4 tests")
        } else {
            fputs("FAIL: \(failures) Task 4 test(s)\n", stderr)
            exit(1)
        }
    }

    private static func testFocusedNormalWindow() throws {
        let windows = [
            candidate(1, focused: false, minimized: false, normal: true),
            candidate(2, focused: true, minimized: false, normal: true),
        ]

        try require(WindowSelector.select(from: windows)?.id == 2, "focused window was not selected")
    }

    private static func testFocusedMinimizedWindow() throws {
        let windows = [
            candidate(1, focused: false, minimized: false, normal: true),
            candidate(2, focused: true, minimized: true, normal: true),
        ]

        try require(WindowSelector.select(from: windows)?.id == 2, "focused minimized window was skipped")
    }

    private static func testNonMinimizedFallback() throws {
        let windows = [
            candidate(1, focused: true, minimized: false, normal: false),
            candidate(2, focused: false, minimized: true, normal: true),
            candidate(3, focused: false, minimized: false, normal: true),
        ]

        try require(WindowSelector.select(from: windows)?.id == 3, "wrong fallback window")
    }

    private static func testMinimizedFallback() throws {
        let windows = [
            candidate(1, focused: false, minimized: false, normal: false),
            candidate(2, focused: false, minimized: true, normal: true),
        ]

        try require(WindowSelector.select(from: windows)?.id == 2, "minimized fallback was not selected")
    }

    private static func testNoUsableWindow() throws {
        let dialogs = [candidate(1, focused: true, minimized: false, normal: false)]

        try require(WindowSelector.select(from: dialogs) == nil, "dialog was treated as a normal window")
        try require(WindowSelector.select(from: []) == nil, "empty window list produced a selection")
    }

    private static func testPermissionDenied() throws {
        let permission = FakePermissionChecker(isTrusted: false)
        let api = FakeAccessibilityWindowAPI()
        let focuser = AXWindowFocuser(permissionChecker: permission, api: api)

        let result = focuser.focusBestWindow(processIdentifier: 100)

        try require(failure(from: result) == .permissionDenied, "wrong permission error")
        try require(api.queryCount == 0, "Accessibility API was queried without permission")
    }

    private static func testFocusFlow() throws {
        let handle = FakeWindowHandle(id: 7)
        let initialFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let finalFrame = CGRect(x: 120, y: 220, width: 800, height: 600)
        let snapshot = AccessibilityWindowSnapshot(
            handle: handle,
            frame: initialFrame,
            isFocused: true,
            isMinimized: true,
            isNormal: true
        )
        let api = FakeAccessibilityWindowAPI(focusedWindow: snapshot, finalFrame: finalFrame)
        let focuser = AXWindowFocuser(
            permissionChecker: FakePermissionChecker(isTrusted: true),
            api: api
        )

        let result = focuser.focusBestWindow(processIdentifier: 200)

        try require(successFrame(from: result) == finalFrame, "final frame was not returned")
        try require(
            api.operations == [.restore(7), .focus(7), .raise(7), .readFrame(7)],
            "window operations ran in the wrong order: \(api.operations)"
        )
    }

    private static func testWindowlessApp() throws {
        let api = FakeAccessibilityWindowAPI()
        let focuser = AXWindowFocuser(
            permissionChecker: FakePermissionChecker(isTrusted: true),
            api: api
        )

        let result = focuser.focusBestWindow(processIdentifier: 300)

        try require(isSuccessfulNil(result), "windowless app did not return success(nil)")
        try require(api.operations.isEmpty, "windowless app performed window actions")
    }

    private static func testMissingFrame() throws {
        let handle = FakeWindowHandle(id: 8)
        let snapshot = AccessibilityWindowSnapshot(
            handle: handle,
            frame: nil,
            isFocused: false,
            isMinimized: false,
            isNormal: true
        )
        let api = FakeAccessibilityWindowAPI(windows: [snapshot], finalFrame: nil)
        let focuser = AXWindowFocuser(
            permissionChecker: FakePermissionChecker(isTrusted: true),
            api: api
        )

        let result = focuser.focusBestWindow(processIdentifier: 400)

        try require(isSuccessfulNil(result), "missing frame was treated as a failure")
        try require(
            api.operations == [.focus(8), .raise(8), .readFrame(8)],
            "window was not focused before reading its missing frame"
        )
    }

    private static func testAccessibilityFailure() throws {
        let handle = FakeWindowHandle(id: 9)
        let snapshot = AccessibilityWindowSnapshot(
            handle: handle,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            isFocused: false,
            isMinimized: false,
            isNormal: true
        )
        let api = FakeAccessibilityWindowAPI(windows: [snapshot])
        api.failureOperation = .focus(9)
        let focuser = AXWindowFocuser(
            permissionChecker: FakePermissionChecker(isTrusted: true),
            api: api
        )

        let result = focuser.focusBestWindow(processIdentifier: 500)

        try require(
            failure(from: result) == .accessibilityFailure("accessibility operation failed"),
            "Accessibility failure was not preserved"
        )
        try require(api.operations == [.focus(9)], "actions continued after failure")
    }

    private static func testFocusFirstWindow() throws {
        let first = snapshot(id: 11, focused: false)
        let second = snapshot(id: 12, focused: true)
        let api = FakeAccessibilityWindowAPI(windows: [first, second], finalFrame: first.frame)
        let focuser = makeFocuser(api: api)

        let result = focuser.focusFirstWindow(processIdentifier: 600)

        try require(successFrame(from: result) == first.frame, "first window frame was not returned")
        try require(
            api.operations == [.focus(11), .raise(11), .readFrame(11)],
            "first normal window was not focused"
        )
    }

    private static func testCycleNextWindow() throws {
        let first = snapshot(id: 21, focused: true)
        let second = snapshot(id: 22, focused: false)
        let api = FakeAccessibilityWindowAPI(windows: [first, second], finalFrame: second.frame)
        let focuser = makeFocuser(api: api)

        let result = focuser.focusNextWindow(processIdentifier: 700)

        try require(cycleFrame(from: result) == second.frame, "next window frame was not returned")
        try require(
            api.operations == [.focus(22), .raise(22), .readFrame(22)],
            "next normal window was not focused"
        )
    }

    private static func testCycleEnd() throws {
        let first = snapshot(id: 31, focused: false)
        let last = snapshot(id: 32, focused: true)
        let api = FakeAccessibilityWindowAPI(windows: [first, last])
        let focuser = makeFocuser(api: api)

        let result = focuser.focusNextWindow(processIdentifier: 800)

        try require(cycleOutcome(from: result) == .endOfWindows, "last window did not report the end")
        try require(api.operations.isEmpty, "a window was focused after reaching the end")
    }

    private static func testSingleWindowEnd() throws {
        let only = snapshot(id: 41, focused: true)
        let api = FakeAccessibilityWindowAPI(windows: [only])
        let focuser = makeFocuser(api: api)

        let result = focuser.focusNextWindow(processIdentifier: 900)

        try require(cycleOutcome(from: result) == .endOfWindows, "single window did not report the end")
    }

    private static func testCycleMinimizedWindow() throws {
        let first = snapshot(id: 51, focused: true)
        let minimized = snapshot(id: 52, focused: false, minimized: true)
        let api = FakeAccessibilityWindowAPI(windows: [first, minimized], finalFrame: minimized.frame)
        let focuser = makeFocuser(api: api)

        let result = focuser.focusNextWindow(processIdentifier: 1000)

        try require(cycleFrame(from: result) == minimized.frame, "minimized next window was not returned")
        try require(
            api.operations == [.restore(52), .focus(52), .raise(52), .readFrame(52)],
            "minimized next window was not restored before focus"
        )
    }

    private static func testFocusedWindowReference() throws {
        let first = snapshot(id: 61, focused: false)
        let last = snapshot(id: 62, focused: false)
        let api = FakeAccessibilityWindowAPI(focusedWindow: last, windows: [first, last])
        let focuser = makeFocuser(api: api)

        let result = focuser.focusNextWindow(processIdentifier: 1100)

        try require(
            cycleOutcome(from: result) == .endOfWindows,
            "focused-window reference was ignored when AXFocused flags were false"
        )
        try require(api.operations.isEmpty, "cycle restarted at the first window instead of ending")
    }

    private static func snapshot(
        id: Int,
        focused: Bool,
        minimized: Bool = false
    ) -> AccessibilityWindowSnapshot {
        AccessibilityWindowSnapshot(
            handle: FakeWindowHandle(id: id),
            frame: CGRect(x: id * 10, y: 20, width: 500, height: 400),
            isFocused: focused,
            isMinimized: minimized,
            isNormal: true
        )
    }

    private static func makeFocuser(api: AccessibilityWindowAPI) -> AXWindowFocuser {
        AXWindowFocuser(
            permissionChecker: FakePermissionChecker(isTrusted: true),
            api: api
        )
    }

    private static func cycleOutcome(
        from result: Result<WindowTraversalOutcome, WindowFocusError>
    ) -> WindowTraversalOutcome? {
        guard case let .success(outcome) = result else { return nil }
        return outcome
    }

    private static func cycleFrame(
        from result: Result<WindowTraversalOutcome, WindowFocusError>
    ) -> CGRect? {
        guard case let .success(.focused(frame)) = result else { return nil }
        return frame
    }

    private static func candidate(
        _ id: Int,
        focused: Bool,
        minimized: Bool,
        normal: Bool
    ) -> WindowCandidate {
        WindowCandidate(
            id: id,
            frame: CGRect(x: id * 10, y: 0, width: 100, height: 100),
            isFocused: focused,
            isMinimized: minimized,
            isNormal: normal
        )
    }

    private static func successFrame(
        from result: Result<CGRect?, WindowFocusError>
    ) -> CGRect? {
        guard case let .success(frame) = result else { return nil }
        return frame
    }

    private static func failure(
        from result: Result<CGRect?, WindowFocusError>
    ) -> WindowFocusError? {
        guard case let .failure(error) = result else { return nil }
        return error
    }

    private static func isSuccessfulNil(_ result: Result<CGRect?, WindowFocusError>) -> Bool {
        guard case .success(nil) = result else { return false }
        return true
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

    init(_ description: String) {
        self.description = description
    }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking {
    let trusted: Bool
    private(set) var prompts: [Bool] = []

    init(isTrusted: Bool) {
        trusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return trusted
    }
}

private final class FakeWindowHandle: NSObject {
    let id: Int

    init(id: Int) {
        self.id = id
    }
}

private enum FakeWindowOperation: Equatable, CustomStringConvertible {
    case restore(Int)
    case focus(Int)
    case raise(Int)
    case readFrame(Int)

    var description: String {
        switch self {
        case let .restore(id): "restore(\(id))"
        case let .focus(id): "focus(\(id))"
        case let .raise(id): "raise(\(id))"
        case let .readFrame(id): "readFrame(\(id))"
        }
    }
}

private enum FakeAccessibilityError: Error, LocalizedError {
    case operationFailed

    var errorDescription: String? { "accessibility operation failed" }
}

private final class FakeAccessibilityWindowAPI: AccessibilityWindowAPI {
    var focusedWindow: AccessibilityWindowSnapshot?
    var windows: [AccessibilityWindowSnapshot]
    var finalFrame: CGRect?
    var failureOperation: FakeWindowOperation?
    private(set) var queryCount = 0
    private(set) var operations: [FakeWindowOperation] = []

    init(
        focusedWindow: AccessibilityWindowSnapshot? = nil,
        windows: [AccessibilityWindowSnapshot] = [],
        finalFrame: CGRect? = nil
    ) {
        self.focusedWindow = focusedWindow
        self.windows = windows
        self.finalFrame = finalFrame
    }

    func focusedWindow(processIdentifier: pid_t) throws -> AccessibilityWindowSnapshot? {
        queryCount += 1
        return focusedWindow
    }

    func windows(processIdentifier: pid_t) throws -> [AccessibilityWindowSnapshot] {
        queryCount += 1
        return windows
    }

    func setMinimized(_ minimized: Bool, window: AnyObject) throws {
        if !minimized {
            try record(.restore(id(of: window)))
        }
    }

    func setFocused(_ focused: Bool, window: AnyObject) throws {
        if focused {
            try record(.focus(id(of: window)))
        }
    }

    func raise(window: AnyObject) throws {
        try record(.raise(id(of: window)))
    }

    func frame(window: AnyObject) throws -> CGRect? {
        try record(.readFrame(id(of: window)))
        return finalFrame
    }

    private func id(of window: AnyObject) -> Int {
        (window as! FakeWindowHandle).id
    }

    private func record(_ operation: FakeWindowOperation) throws {
        operations.append(operation)
        if operation == failureOperation {
            throw FakeAccessibilityError.operationFailed
        }
    }
}
