import ApplicationServices
import Foundation

public struct AccessibilityWindowSnapshot {
    public let handle: AnyObject
    public let frame: CGRect?
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isNormal: Bool

    public init(
        handle: AnyObject,
        frame: CGRect?,
        isFocused: Bool,
        isMinimized: Bool,
        isNormal: Bool
    ) {
        self.handle = handle
        self.frame = frame
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isNormal = isNormal
    }
}

public protocol AccessibilityWindowAPI: AnyObject {
    func focusedWindow(processIdentifier: pid_t) throws -> AccessibilityWindowSnapshot?
    func windows(processIdentifier: pid_t) throws -> [AccessibilityWindowSnapshot]
    func setMinimized(_ minimized: Bool, window: AnyObject) throws
    func setFocused(_ focused: Bool, window: AnyObject) throws
    func raise(window: AnyObject) throws
    func frame(window: AnyObject) throws -> CGRect?
    func representsSameWindow(_ first: AnyObject, _ second: AnyObject) -> Bool
}

public extension AccessibilityWindowAPI {
    func representsSameWindow(_ first: AnyObject, _ second: AnyObject) -> Bool {
        first === second
    }
}

public enum WindowFocusError: Error, Equatable, CustomStringConvertible {
    case permissionDenied
    case accessibilityFailure(String)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required to focus application windows"
        case let .accessibilityFailure(reason):
            return "could not focus the application window: \(reason)"
        }
    }
}

public protocol WindowFocusing {
    func focusBestWindow(processIdentifier: pid_t) -> Result<CGRect?, WindowFocusError>
    func focusFirstWindow(processIdentifier: pid_t) -> Result<CGRect?, WindowFocusError>
    func focusNextWindow(
        processIdentifier: pid_t
    ) -> Result<WindowTraversalOutcome, WindowFocusError>
}

public enum WindowTraversalOutcome: Equatable, Sendable {
    case focused(CGRect?)
    case endOfWindows
    case noWindow
}

public extension WindowFocusing {
    func focusFirstWindow(processIdentifier: pid_t) -> Result<CGRect?, WindowFocusError> {
        focusBestWindow(processIdentifier: processIdentifier)
    }

    func focusNextWindow(
        processIdentifier: pid_t
    ) -> Result<WindowTraversalOutcome, WindowFocusError> {
        .success(.noWindow)
    }
}

public final class AXWindowFocuser: WindowFocusing {
    private let permissionChecker: AccessibilityPermissionChecking
    private let api: AccessibilityWindowAPI

    public init(
        permissionChecker: AccessibilityPermissionChecking = SystemAccessibilityPermissionChecker(),
        api: AccessibilityWindowAPI = NativeAccessibilityWindowAPI()
    ) {
        self.permissionChecker = permissionChecker
        self.api = api
    }

    public func focusBestWindow(
        processIdentifier: pid_t
    ) -> Result<CGRect?, WindowFocusError> {
        guard permissionChecker.isTrusted(prompt: false) else {
            return .failure(.permissionDenied)
        }

        do {
            var snapshots: [AccessibilityWindowSnapshot] = []
            if let focused = try api.focusedWindow(processIdentifier: processIdentifier) {
                snapshots.append(focused)
            }
            snapshots.append(contentsOf: try api.windows(processIdentifier: processIdentifier))

            let candidates = snapshots.enumerated().map { index, snapshot in
                WindowCandidate(
                    id: index,
                    frame: snapshot.frame,
                    isFocused: snapshot.isFocused,
                    isMinimized: snapshot.isMinimized,
                    isNormal: snapshot.isNormal
                )
            }

            guard let selected = WindowSelector.select(from: candidates) else {
                return .success(nil)
            }

            let window = snapshots[selected.id]
            if window.isMinimized {
                try api.setMinimized(false, window: window.handle)
            }
            try api.setFocused(true, window: window.handle)
            try api.raise(window: window.handle)
            return .success(try api.frame(window: window.handle))
        } catch {
            return .failure(.accessibilityFailure(error.localizedDescription))
        }
    }

    public func focusFirstWindow(
        processIdentifier: pid_t
    ) -> Result<CGRect?, WindowFocusError> {
        guard permissionChecker.isTrusted(prompt: false) else {
            return .failure(.permissionDenied)
        }

        do {
            guard let first = try api.windows(processIdentifier: processIdentifier)
                .first(where: \.isNormal)
            else {
                return .success(nil)
            }
            return .success(try focus(first))
        } catch {
            return .failure(.accessibilityFailure(error.localizedDescription))
        }
    }

    public func focusNextWindow(
        processIdentifier: pid_t
    ) -> Result<WindowTraversalOutcome, WindowFocusError> {
        guard permissionChecker.isTrusted(prompt: false) else {
            return .failure(.permissionDenied)
        }

        do {
            let focusedWindow = try api.focusedWindow(processIdentifier: processIdentifier)
            let windows = try api.windows(processIdentifier: processIdentifier)
                .filter(\.isNormal)
            guard !windows.isEmpty else {
                return .success(.noWindow)
            }

            let next: AccessibilityWindowSnapshot
            if let focusedIndex = windows.firstIndex(where: { window in
                window.isFocused
                    || focusedWindow.map {
                        api.representsSameWindow(window.handle, $0.handle)
                    } == true
            }) {
                guard windows.indices.contains(focusedIndex + 1) else {
                    return .success(.endOfWindows)
                }
                next = windows[focusedIndex + 1]
            } else {
                next = windows[0]
            }
            return .success(.focused(try focus(next)))
        } catch {
            return .failure(.accessibilityFailure(error.localizedDescription))
        }
    }

    private func focus(_ window: AccessibilityWindowSnapshot) throws -> CGRect? {
        if window.isMinimized {
            try api.setMinimized(false, window: window.handle)
        }
        try api.setFocused(true, window: window.handle)
        try api.raise(window: window.handle)
        return try api.frame(window: window.handle)
    }
}

public enum AccessibilityAPIError: Error, LocalizedError {
    case operationFailed(name: String, code: AXError)
    case invalidWindowHandle

    public var errorDescription: String? {
        switch self {
        case let .operationFailed(name, code):
            return "\(name) failed with Accessibility error \(code.rawValue)"
        case .invalidWindowHandle:
            return "the Accessibility window handle is invalid"
        }
    }
}

public final class NativeAccessibilityWindowAPI: AccessibilityWindowAPI {
    public init() {}

    public func focusedWindow(
        processIdentifier: pid_t
    ) throws -> AccessibilityWindowSnapshot? {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let value = try optionalAttribute(kAXFocusedWindowAttribute, from: application),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return try snapshot(for: unsafeBitCast(value, to: AXUIElement.self))
    }

    public func windows(processIdentifier: pid_t) throws -> [AccessibilityWindowSnapshot] {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let value = try optionalAttribute(kAXWindowsAttribute, from: application),
              let values = value as? [AnyObject]
        else {
            return []
        }

        return try values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return try snapshot(for: unsafeBitCast(value, to: AXUIElement.self))
        }
    }

    public func setMinimized(_ minimized: Bool, window: AnyObject) throws {
        let value = minimized ? kCFBooleanTrue : kCFBooleanFalse
        try setAttribute(kAXMinimizedAttribute, value: value!, on: try element(from: window))
    }

    public func setFocused(_ focused: Bool, window: AnyObject) throws {
        let value = focused ? kCFBooleanTrue : kCFBooleanFalse
        try setAttribute(kAXFocusedAttribute, value: value!, on: try element(from: window))
    }

    public func raise(window: AnyObject) throws {
        let result = AXUIElementPerformAction(try element(from: window), kAXRaiseAction as CFString)
        try requireSuccess(result, operation: "raise window")
    }

    public func frame(window: AnyObject) throws -> CGRect? {
        try readFrame(from: element(from: window))
    }

    public func representsSameWindow(_ first: AnyObject, _ second: AnyObject) -> Bool {
        CFEqual(first, second)
    }

    private func snapshot(for window: AXUIElement) throws -> AccessibilityWindowSnapshot {
        let role = try optionalAttribute(kAXRoleAttribute, from: window) as? String
        let subrole = try optionalAttribute(kAXSubroleAttribute, from: window) as? String
        return AccessibilityWindowSnapshot(
            handle: window,
            frame: try readFrame(from: window),
            isFocused: try booleanAttribute(kAXFocusedAttribute, from: window),
            isMinimized: try booleanAttribute(kAXMinimizedAttribute, from: window),
            isNormal: role == kAXWindowRole && subrole == kAXStandardWindowSubrole
        )
    }

    private func readFrame(from window: AXUIElement) throws -> CGRect? {
        guard let positionValue = try optionalAttribute(kAXPositionAttribute, from: window),
              let sizeValue = try optionalAttribute(kAXSizeAttribute, from: window),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func booleanAttribute(_ attribute: String, from element: AXUIElement) throws -> Bool {
        (try optionalAttribute(attribute, from: element) as? Bool) ?? false
    }

    private func optionalAttribute(_ attribute: String, from element: AXUIElement) throws -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .noValue || result == .attributeUnsupported {
            return nil
        }
        try requireSuccess(result, operation: "read \(attribute)")
        return value
    }

    private func setAttribute(_ attribute: String, value: CFTypeRef, on element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        try requireSuccess(result, operation: "set \(attribute)")
    }

    private func element(from handle: AnyObject) throws -> AXUIElement {
        guard CFGetTypeID(handle) == AXUIElementGetTypeID() else {
            throw AccessibilityAPIError.invalidWindowHandle
        }
        return unsafeBitCast(handle, to: AXUIElement.self)
    }

    private func requireSuccess(_ result: AXError, operation: String) throws {
        guard result == .success else {
            throw AccessibilityAPIError.operationFailed(name: operation, code: result)
        }
    }
}
