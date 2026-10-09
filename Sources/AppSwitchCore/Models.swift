import Foundation

public struct HotKey: Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let canonical: String

    public init(keyCode: UInt32, modifiers: UInt32, canonical: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.canonical = canonical
    }
}

public struct AppBinding: Hashable, Sendable {
    public let hotKey: HotKey
    public let bundleIdentifier: String

    public init(hotKey: HotKey, bundleIdentifier: String) {
        self.hotKey = hotKey
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct AppConfiguration: Equatable, Sendable {
    public let moveCursor: Bool
    public let bindings: [AppBinding]

    public init(moveCursor: Bool, bindings: [AppBinding]) {
        self.moveCursor = moveCursor
        self.bindings = bindings
    }
}
