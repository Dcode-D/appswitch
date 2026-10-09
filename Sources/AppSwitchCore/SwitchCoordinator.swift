import Foundation

public protocol SwitchCoordinating: AnyObject {
    func handle(_ binding: AppBinding)
}

public final class SwitchCoordinator: SwitchCoordinating {
    private let moveCursor: Bool
    private let activator: ApplicationActivating
    private let windowFocuser: WindowFocusing
    private let cursorMover: CursorMoving
    private let activeApplicationManager: ActiveApplicationManaging
    private let screens: () -> [ScreenGeometry]
    private let log: (String) -> Void

    public init(
        moveCursor: Bool,
        activator: ApplicationActivating,
        windowFocuser: WindowFocusing,
        cursorMover: CursorMoving,
        activeApplicationManager: ActiveApplicationManaging = NSWorkspaceActiveApplicationManager(),
        screens: @escaping () -> [ScreenGeometry] = ScreenGeometry.current,
        log: @escaping (String) -> Void
    ) {
        self.moveCursor = moveCursor
        self.activator = activator
        self.windowFocuser = windowFocuser
        self.cursorMover = cursorMover
        self.activeApplicationManager = activeApplicationManager
        self.screens = screens
        self.log = log
    }

    public func handle(_ binding: AppBinding) {
        onMain { [weak self] in
            guard let self else { return }
            if let processIdentifier = self.activeApplicationManager
                .frontmostProcessIdentifier(bundleIdentifier: binding.bundleIdentifier) {
                self.advanceActiveApplication(binding: binding, processIdentifier: processIdentifier)
                return
            }
            _ = self.activator.activate(bundleIdentifier: binding.bundleIdentifier) {
                [weak self] result in
                self?.onMain {
                    self?.finishSwitch(binding: binding, activation: result)
                }
            }
        }
    }

    private func finishSwitch(
        binding: AppBinding,
        activation: Result<pid_t, ApplicationActivationError>
    ) {
        switch activation {
        case let .failure(error):
            log("could not activate \(binding.bundleIdentifier): \(error)")
        case let .success(processIdentifier):
            finishFocus(
                binding: binding,
                result: windowFocuser.focusFirstWindow(processIdentifier: processIdentifier)
            )
        }
    }

    private func advanceActiveApplication(binding: AppBinding, processIdentifier: pid_t) {
        switch windowFocuser.focusNextWindow(processIdentifier: processIdentifier) {
        case .failure(.permissionDenied):
            return
        case let .failure(error):
            log("could not cycle windows for \(binding.bundleIdentifier): \(error)")
        case .success(.noWindow):
            return
        case .success(.endOfWindows):
            if !activeApplicationManager.hide(processIdentifier: processIdentifier) {
                log("could not hide \(binding.bundleIdentifier)")
            }
        case let .success(.focused(frame)):
            moveCursorIfNeeded(binding: binding, frame: frame)
        }
    }

    private func finishFocus(
        binding: AppBinding,
        result: Result<CGRect?, WindowFocusError>
    ) {
        switch result {
        case .failure(.permissionDenied):
            return
        case let .failure(error):
            log("could not focus \(binding.bundleIdentifier): \(error)")
        case .success(nil):
            return
        case let .success(frame?):
            moveCursorIfNeeded(binding: binding, frame: frame)
        }
    }

    private func moveCursorIfNeeded(binding: AppBinding, frame: CGRect?) {
        guard moveCursor,
              let frame,
              let target = CursorGeometry.target(windowFrame: frame, screens: screens())
        else {
            return
        }
        do {
            try cursorMover.move(to: target)
        } catch {
            log("could not move cursor for \(binding.bundleIdentifier): \(error.localizedDescription)")
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
