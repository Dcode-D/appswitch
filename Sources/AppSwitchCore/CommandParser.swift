import Foundation

public enum Command: Equatable, Sendable {
    case run
    case check
    case printExample
}

public enum CommandParseError: Error, Equatable, CustomStringConvertible {
    case invalidArguments([String])

    public var exitCode: Int32 { 2 }

    public var description: String {
        "usage: appswitch [run|check|print-example]"
    }
}

public enum CommandParser {
    public static func parse(arguments: [String]) throws -> Command {
        switch arguments {
        case []:
            return .run
        case ["run"]:
            return .run
        case ["check"]:
            return .check
        case ["print-example"]:
            return .printExample
        default:
            throw CommandParseError.invalidArguments(arguments)
        }
    }
}

public enum ExampleConfiguration {
    public static let json = """
    {
      "moveCursor": false,
      "bindings": [
        {
          "shortcut": "cmd+option+1",
          "bundleID": "com.apple.Safari"
        },
        {
          "shortcut": "cmd+option+2",
          "bundleID": "com.microsoft.VSCode"
        }
      ]
    }
    """
}
