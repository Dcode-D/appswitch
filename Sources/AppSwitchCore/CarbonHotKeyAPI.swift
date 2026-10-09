import Carbon.HIToolbox
import Foundation

public struct CarbonHotKeyToken: Hashable, Sendable {
    public let id: UInt32

    public init(id: UInt32) {
        self.id = id
    }
}

public enum CarbonHotKeyAPIError: Error, Equatable {
    case status(OSStatus)
}

public protocol CarbonHotKeyAPI: AnyObject {
    func installEventHandler(_ handler: @escaping (UInt32) -> Void) throws
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws -> CarbonHotKeyToken
    func unregister(_ token: CarbonHotKeyToken)
}

final class NativeCarbonHotKeyAPI: CarbonHotKeyAPI {
    private static let signature: OSType = 0x4153_5748 // ASWH

    private var callback: ((UInt32) -> Void)?
    private var eventHandler: EventHandlerRef?
    private var registrations: [CarbonHotKeyToken: EventHotKeyRef] = [:]

    func installEventHandler(_ handler: @escaping (UInt32) -> Void) throws {
        callback = handler
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<NativeCarbonHotKeyAPI>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard readStatus == noErr else { return readStatus }
                owner.callback?(hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard status == noErr else { throw CarbonHotKeyAPIError.status(status) }
        eventHandler = installedHandler
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws -> CarbonHotKeyToken {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw CarbonHotKeyAPIError.status(status == noErr ? OSStatus(paramErr) : status)
        }

        let token = CarbonHotKeyToken(id: id)
        registrations[token] = reference
        return token
    }

    func unregister(_ token: CarbonHotKeyToken) {
        guard let reference = registrations.removeValue(forKey: token) else { return }
        UnregisterEventHotKey(reference)
    }

    deinit {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
