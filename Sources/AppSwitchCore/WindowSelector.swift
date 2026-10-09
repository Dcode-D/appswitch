import Foundation

public struct WindowCandidate: Equatable, Sendable {
    public let id: Int
    public let frame: CGRect?
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isNormal: Bool

    public init(
        id: Int,
        frame: CGRect?,
        isFocused: Bool,
        isMinimized: Bool,
        isNormal: Bool
    ) {
        self.id = id
        self.frame = frame
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isNormal = isNormal
    }
}

public enum WindowSelector {
    public static func select(from windows: [WindowCandidate]) -> WindowCandidate? {
        windows.first(where: { $0.isFocused && $0.isNormal })
            ?? windows.first(where: { $0.isNormal && !$0.isMinimized })
            ?? windows.first(where: { $0.isNormal && $0.isMinimized })
    }
}
