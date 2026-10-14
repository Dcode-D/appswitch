import Foundation

public enum QuickSwitchList {
    public static func lines(
        hotKeys: [HotKey],
        applications: [RunningApplicationIdentity]
    ) -> [String] {
        guard !hotKeys.isEmpty else {
            return ["Quick switch is not configured."]
        }

        return hotKeys.enumerated().map { index, hotKey in
            guard applications.indices.contains(index) else {
                return "\(hotKey.canonical)\t—"
            }

            let application = applications[index]
            let name = application.localizedName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty, name != application.bundleIdentifier else {
                return "\(hotKey.canonical)\t\(application.bundleIdentifier)"
            }
            return "\(hotKey.canonical)\t\(name)\t\(application.bundleIdentifier)"
        }
    }
}
