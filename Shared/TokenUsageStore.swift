import Foundation

final class TokenUsageStore {
    static let appGroupID = infoValue("TokenWidgetAppGroupIdentifier", fallback: "group.com.example.token-widget")
    static let widgetBundleID = infoValue("TokenWidgetWidgetBundleIdentifier", fallback: "com.example.TokenWidget.widget")

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSnapshot() -> TokenUsageSnapshot {
        if isWidgetProcess {
            return loadSnapshotFromAppGroupFile()
                ?? loadSnapshotFromMirror()
                ?? .empty
        }

        if let snapshot = loadSnapshotFromAppGroupFile() {
            return snapshot
        }

        if let data = userDefaults.data(forKey: "snapshot"),
           let snapshot = try? decoder.decode(TokenUsageSnapshot.self, from: data) {
            return snapshot
        }

        return loadSnapshotFromMirror() ?? .empty
    }

    func saveSnapshot(_ snapshot: TokenUsageSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: "snapshot")
        try? save(data: data, to: appGroupSnapshotURL)
        try? save(data: data, to: mirrorSnapshotURL)
    }

    func loadPreferences() -> TokenUsagePreferences {
        if isWidgetProcess {
            return loadPreferencesFromAppGroupFile() ?? .defaults
        }

        if let preferences = loadPreferencesFromAppGroupFile() {
            return preferences
        }

        guard let data = userDefaults.data(forKey: "preferences"),
              let preferences = try? decoder.decode(TokenUsagePreferences.self, from: data)
        else {
            return .defaults
        }

        return preferences
    }

    func savePreferences(_ preferences: TokenUsagePreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        userDefaults.set(data, forKey: "preferences")
        try? save(data: data, to: appGroupPreferencesURL)
        try? save(data: data, to: mirrorPreferencesURL)
    }

    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    private var isWidgetProcess: Bool {
        Bundle.main.bundleIdentifier == Self.widgetBundleID
    }

    private func loadSnapshotFromMirror() -> TokenUsageSnapshot? {
        guard let data = try? Data(contentsOf: mirrorSnapshotURL) else { return nil }
        return try? decoder.decode(TokenUsageSnapshot.self, from: data)
    }

    private func loadSnapshotFromAppGroupFile() -> TokenUsageSnapshot? {
        guard let data = try? Data(contentsOf: appGroupSnapshotURL) else { return nil }
        return try? decoder.decode(TokenUsageSnapshot.self, from: data)
    }

    private func loadPreferencesFromAppGroupFile() -> TokenUsagePreferences? {
        guard let data = try? Data(contentsOf: appGroupPreferencesURL) else { return nil }
        return try? decoder.decode(TokenUsagePreferences.self, from: data)
    }

    private var appGroupSnapshotURL: URL {
        appGroupDirectoryURL.appendingPathComponent("snapshot.json")
    }

    private var appGroupPreferencesURL: URL {
        appGroupDirectoryURL.appendingPathComponent("preferences.json")
    }

    private var appGroupDirectoryURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return url.appendingPathComponent("TokenWidget", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(Self.appGroupID)/TokenWidget", isDirectory: true)
    }

    private var mirrorSnapshotURL: URL {
        mirrorDirectoryURL.appendingPathComponent("snapshot.json")
    }

    private var mirrorPreferencesURL: URL {
        mirrorDirectoryURL.appendingPathComponent("preferences.json")
    }

    private var mirrorDirectoryURL: URL {
        if isWidgetProcess,
           let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupport.appendingPathComponent("TokenWidget", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(Self.widgetBundleID)/Data/Library/Application Support/TokenWidget", isDirectory: true)
    }

    private func save(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func infoValue(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(")
        else {
            return fallback
        }

        return value
    }
}
