import Foundation

public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
    case fileRead(String)
    case malformedJSON
    case rootMustBeObject
    case unknownTopLevelField(String)
    case unknownBindingField(index: Int, field: String)
    case unknownQuickSwitchField(String)
    case invalidDocument(String)
    case emptyBindings
    case emptyQuickSwitchKeys
    case emptyBundleIdentifier(index: Int)
    case invalidQuickSwitchShortcut(index: Int, reason: String)
    case invalidShortcut(index: Int, reason: String)
    case duplicateShortcut(String)

    public var description: String {
        switch self {
        case let .fileRead(path):
            return "could not read configuration at \(path)"
        case .malformedJSON:
            return "configuration is not valid JSON"
        case .rootMustBeObject:
            return "configuration root must be an object"
        case let .unknownTopLevelField(field):
            return "unknown configuration field '\(field)'"
        case let .unknownBindingField(index, field):
            return "binding \(index) has unknown field '\(field)'"
        case let .unknownQuickSwitchField(field):
            return "quickSwitch has unknown field '\(field)'"
        case let .invalidDocument(reason):
            return "invalid configuration: \(reason)"
        case .emptyBindings:
            return "configuration must contain at least one binding"
        case .emptyQuickSwitchKeys:
            return "quickSwitch must contain at least one key"
        case let .emptyBundleIdentifier(index):
            return "binding \(index) has an empty bundleID"
        case let .invalidQuickSwitchShortcut(index, reason):
            return "quickSwitch key \(index) makes an invalid shortcut: \(reason)"
        case let .invalidShortcut(index, reason):
            return "binding \(index) has an invalid shortcut: \(reason)"
        case let .duplicateShortcut(shortcut):
            return "shortcut '\(shortcut)' is configured more than once"
        }
    }
}

public enum ConfigurationLoader {
    private struct Document: Decodable {
        let moveCursor: Bool?
        let quickSwitch: QuickSwitch?
        let bindings: [Binding]
    }

    private struct QuickSwitch: Decodable {
        let prefix: String
        let keys: [String]
    }

    private struct Binding: Decodable {
        let shortcut: String
        let bundleID: String
    }

    private static let topLevelFields: Set<String> = ["moveCursor", "quickSwitch", "bindings"]
    private static let bindingFields: Set<String> = ["shortcut", "bundleID"]
    private static let quickSwitchFields: Set<String> = ["prefix", "keys"]

    public static func load(from url: URL) throws -> AppConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigurationError.fileRead(url.path)
        }
        return try load(data: data)
    }

    public static func load(data: Data) throws -> AppConfiguration {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigurationError.malformedJSON
        }

        guard let object = json as? [String: Any] else {
            throw ConfigurationError.rootMustBeObject
        }
        if let field = Set(object.keys).subtracting(topLevelFields).sorted().first {
            throw ConfigurationError.unknownTopLevelField(field)
        }

        if let bindings = object["bindings"] as? [Any] {
            for (index, value) in bindings.enumerated() {
                guard let binding = value as? [String: Any] else { continue }
                if let field = Set(binding.keys).subtracting(bindingFields).sorted().first {
                    throw ConfigurationError.unknownBindingField(index: index, field: field)
                }
            }
        }
        if let quickSwitch = object["quickSwitch"] as? [String: Any],
           let field = Set(quickSwitch.keys).subtracting(quickSwitchFields).sorted().first {
            throw ConfigurationError.unknownQuickSwitchField(field)
        }

        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ConfigurationError.invalidDocument(error.localizedDescription)
        }

        guard !document.bindings.isEmpty else {
            throw ConfigurationError.emptyBindings
        }

        var seenShortcuts = Set<String>()
        var quickSwitchHotKeys: [HotKey] = []
        if let quickSwitch = document.quickSwitch {
            guard !quickSwitch.keys.isEmpty else {
                throw ConfigurationError.emptyQuickSwitchKeys
            }
            quickSwitchHotKeys.reserveCapacity(quickSwitch.keys.count)
            for (index, key) in quickSwitch.keys.enumerated() {
                let hotKey: HotKey
                do {
                    hotKey = try ShortcutParser.parse("\(quickSwitch.prefix)+\(key)")
                } catch {
                    throw ConfigurationError.invalidQuickSwitchShortcut(
                        index: index,
                        reason: String(describing: error)
                    )
                }
                guard seenShortcuts.insert(hotKey.canonical).inserted else {
                    throw ConfigurationError.duplicateShortcut(hotKey.canonical)
                }
                quickSwitchHotKeys.append(hotKey)
            }
        }

        var bindings: [AppBinding] = []
        bindings.reserveCapacity(document.bindings.count)

        for (index, binding) in document.bindings.enumerated() {
            let bundleIdentifier = binding.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleIdentifier.isEmpty else {
                throw ConfigurationError.emptyBundleIdentifier(index: index)
            }

            let hotKey: HotKey
            do {
                let shortcut = binding.shortcut.contains("+")
                    ? binding.shortcut
                    : "cmd+shift+\(binding.shortcut)"
                hotKey = try ShortcutParser.parse(shortcut)
            } catch {
                throw ConfigurationError.invalidShortcut(index: index, reason: String(describing: error))
            }

            guard seenShortcuts.insert(hotKey.canonical).inserted else {
                throw ConfigurationError.duplicateShortcut(hotKey.canonical)
            }
            bindings.append(AppBinding(hotKey: hotKey, bundleIdentifier: bundleIdentifier))
        }

        return AppConfiguration(
            moveCursor: document.moveCursor ?? false,
            bindings: bindings,
            quickSwitchHotKeys: quickSwitchHotKeys
        )
    }
}
