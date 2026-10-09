import AppKit
import CoreGraphics
import Foundation

public struct ScreenGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    public static func current() -> [ScreenGeometry] {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            ScreenGeometry(
                frame: screen.frame.accessibilityCoordinates(primaryTop: primaryTop),
                visibleFrame: screen.visibleFrame.accessibilityCoordinates(primaryTop: primaryTop)
            )
        }
    }
}

public enum CursorGeometry {
    public static func target(windowFrame: CGRect, screens: [ScreenGeometry]) -> CGPoint? {
        let windowFrame = windowFrame.standardized
        guard !windowFrame.isEmpty,
              let screen = screens.max(by: {
                  intersectionArea(windowFrame, $0.frame) < intersectionArea(windowFrame, $1.frame)
              }),
              intersectionArea(windowFrame, screen.frame) > 0,
              !screen.visibleFrame.isEmpty
        else {
            return nil
        }

        return CGPoint(
            x: min(max(windowFrame.midX, screen.visibleFrame.minX), screen.visibleFrame.maxX),
            y: min(max(windowFrame.midY, screen.visibleFrame.minY), screen.visibleFrame.maxY)
        )
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

public protocol CursorMoving {
    func move(to point: CGPoint) throws
}

public enum CursorMovementError: Error, Equatable, CustomStringConvertible {
    case warpFailed(CGError)

    public var description: String {
        switch self {
        case let .warpFailed(error):
            return "could not move the cursor (Core Graphics error \(error.rawValue))"
        }
    }
}

public struct QuartzCursorMover: CursorMoving {
    public init() {}

    public func move(to point: CGPoint) throws {
        let result = CGWarpMouseCursorPosition(point)
        guard result == .success else {
            throw CursorMovementError.warpFailed(result)
        }
    }
}

private extension CGRect {
    func accessibilityCoordinates(primaryTop: CGFloat) -> CGRect {
        CGRect(x: minX, y: primaryTop - maxY, width: width, height: height)
    }
}
