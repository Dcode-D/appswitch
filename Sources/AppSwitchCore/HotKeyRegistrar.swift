import Foundation

public enum HotKeyRegistrationError: Error, Equatable, CustomStringConvertible {
    case handlerInstallationFailed(status: OSStatus)
    case registrationFailed(shortcut: String, status: OSStatus)

    public var description: String {
        switch self {
        case let .handlerInstallationFailed(status):
            return "could not install the hotkey event handler (status \(status))"
        case let .registrationFailed(shortcut, status):
            return "could not register shortcut '\(shortcut)' (status \(status))"
        }
    }
}

public protocol HotKeyRegistering: AnyObject {
    func register(binding: AppBinding, action: @escaping () -> Void) throws
    func probe(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError>
    func unregisterAll()
}

public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private let api: CarbonHotKeyAPI
    private var nextID: UInt32 = 1
    private var actions: [UInt32: () -> Void] = [:]
    private var tokens: [UInt32: CarbonHotKeyToken] = [:]
    private var registrationOrder: [UInt32] = []

    public convenience init() throws {
        try self.init(api: NativeCarbonHotKeyAPI())
    }

    init(api: CarbonHotKeyAPI) throws {
        self.api = api
        do {
            try api.installEventHandler { [weak self] id in
                self?.actions[id]?()
            }
        } catch {
            throw HotKeyRegistrationError.handlerInstallationFailed(status: Self.status(from: error))
        }
    }

    public func register(binding: AppBinding, action: @escaping () -> Void) throws {
        let id = takeNextID()
        do {
            let token = try api.register(
                keyCode: binding.hotKey.keyCode,
                modifiers: binding.hotKey.modifiers,
                id: id
            )
            actions[id] = action
            tokens[id] = token
            registrationOrder.append(id)
        } catch {
            throw HotKeyRegistrationError.registrationFailed(
                shortcut: binding.hotKey.canonical,
                status: Self.status(from: error)
            )
        }
    }

    public func probe(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError> {
        let id = takeNextID()
        do {
            let token = try api.register(
                keyCode: hotKey.keyCode,
                modifiers: hotKey.modifiers,
                id: id
            )
            api.unregister(token)
            return .success(())
        } catch {
            return .failure(
                .registrationFailed(shortcut: hotKey.canonical, status: Self.status(from: error))
            )
        }
    }

    public func unregisterAll() {
        for id in registrationOrder {
            if let token = tokens[id] {
                api.unregister(token)
            }
        }
        actions.removeAll()
        tokens.removeAll()
        registrationOrder.removeAll()
    }

    deinit {
        unregisterAll()
    }

    private func takeNextID() -> UInt32 {
        defer { nextID &+= 1 }
        return nextID
    }

    private static func status(from error: Error) -> OSStatus {
        if case let CarbonHotKeyAPIError.status(status) = error {
            return status
        }
        return OSStatus(paramErr)
    }
}
