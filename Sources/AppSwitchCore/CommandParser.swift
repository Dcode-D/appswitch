import Foundation

public enum Command: Equatable, Sendable {
    case run
    case check
    case list
    case printExample
}

public enum CommandParseError: Error, Equatable, CustomStringConvertible {
    case invalidArguments([String])

    public var exitCode: Int32 { 2 }

    public var description: String {
        "usage: appswitch [run|check|list|print-example]"
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
        case ["list"]:
            return .list
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
      "quickSwitch": {
        "prefix": "cmd",
        "keys": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
      },
      "bindings": [
        {
          "shortcut": "cmd+option+1",
          "bundleID": "com.apple.Safari"
        },
        {
          "shortcut": "control+shift+2",
          "bundleID": "com.microsoft.VSCode"
        }
      ]
    }
    """
}
