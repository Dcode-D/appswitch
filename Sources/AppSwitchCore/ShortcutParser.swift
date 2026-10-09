import Foundation
import Carbon.HIToolbox

public enum ShortcutParseError: Error, Equatable, CustomStringConvertible {
    case empty
    case duplicateModifier(String)
    case multipleBaseKeys
    case missingBaseKey
    case missingModifier
    case unsupportedToken(String)

    public var description: String {
        switch self {
        case .empty:
            return "shortcut is empty"
        case let .duplicateModifier(modifier):
            return "modifier '\(modifier)' appears more than once"
        case .multipleBaseKeys:
            return "shortcut must contain exactly one base key"
        case .missingBaseKey:
            return "shortcut is missing a base key"
        case .missingModifier:
            return "shortcut must contain at least one modifier"
        case let .unsupportedToken(token):
            return "unsupported shortcut token '\(token)'"
        }
    }
}

public enum ShortcutParser {
    private static let modifiers: [(name: String, mask: UInt32)] = [
        ("cmd", UInt32(cmdKey)),
        ("control", UInt32(controlKey)),
        ("option", UInt32(optionKey)),
        ("shift", UInt32(shiftKey)),
    ]

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3,
        "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
        "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
        "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "f13": 105, "f14": 107,
        "f15": 113, "f16": 106, "f17": 64, "f18": 79,
        "f19": 80, "f20": 90,
    ]

    public static func parse(_ value: String) throws -> HotKey {
        let tokens = value
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard !tokens.isEmpty, tokens.allSatisfy({ !$0.isEmpty }) else {
            throw ShortcutParseError.empty
        }

        var selectedModifiers: [String: UInt32] = [:]
        var baseKey: (name: String, code: UInt32)?

        for token in tokens {
            if let modifier = modifiers.first(where: { $0.name == token }) {
                guard selectedModifiers[token] == nil else {
                    throw ShortcutParseError.duplicateModifier(token)
                }
                selectedModifiers[token] = modifier.mask
            } else if let keyCode = keyCodes[token] {
                guard baseKey == nil else {
                    throw ShortcutParseError.multipleBaseKeys
                }
                baseKey = (token, keyCode)
            } else {
                throw ShortcutParseError.unsupportedToken(token)
            }
        }

        guard !selectedModifiers.isEmpty else {
            throw ShortcutParseError.missingModifier
        }
        guard let baseKey else {
            throw ShortcutParseError.missingBaseKey
        }

        let orderedModifiers = modifiers.filter { selectedModifiers[$0.name] != nil }
        let mask = orderedModifiers.reduce(UInt32(0)) { $0 | $1.mask }
        let canonical = (orderedModifiers.map(\.name) + [baseKey.name]).joined(separator: "+")

        return HotKey(keyCode: baseKey.code, modifiers: mask, canonical: canonical)
    }
}
