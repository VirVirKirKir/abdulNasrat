import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {

    private enum Keys {
        static let useTelegram = "useTelegram"
        static let channels = "telegramChannels"
        static let regionFilter = "telegramRegionFilter"
        static let useJSONFeed = "useJSONFeed"
        static let jsonFeedURL = "jsonFeedURL"
        static let soundEnabled = "soundEnabled"
        static let timeSensitive = "timeSensitive"
        static let backgroundRefresh = "backgroundRefresh"
        static let didAskForNotifications = "didAskForNotifications"
    }

    private let defaults = UserDefaults.standard

    @Published var useTelegram: Bool { didSet { defaults.set(useTelegram, forKey: Keys.useTelegram) } }
    @Published var channels: String { didSet { defaults.set(channels, forKey: Keys.channels) } }
    @Published var regionFilter: Bool { didSet { defaults.set(regionFilter, forKey: Keys.regionFilter) } }
    @Published var useJSONFeed: Bool { didSet { defaults.set(useJSONFeed, forKey: Keys.useJSONFeed) } }
    @Published var jsonFeedURL: String { didSet { defaults.set(jsonFeedURL, forKey: Keys.jsonFeedURL) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) } }
    @Published var timeSensitive: Bool { didSet { defaults.set(timeSensitive, forKey: Keys.timeSensitive) } }
    @Published var backgroundRefresh: Bool { didSet { defaults.set(backgroundRefresh, forKey: Keys.backgroundRefresh) } }
    @Published var didAskForNotifications: Bool { didSet { defaults.set(didAskForNotifications, forKey: Keys.didAskForNotifications) } }

    init() {
        let d = UserDefaults.standard
        useTelegram = d.object(forKey: Keys.useTelegram) as? Bool ?? true
        channels = d.string(forKey: Keys.channels) ?? "mchs_orenburg, orenburg_official"
        regionFilter = d.object(forKey: Keys.regionFilter) as? Bool ?? false
        useJSONFeed = d.object(forKey: Keys.useJSONFeed) as? Bool ?? false
        jsonFeedURL = d.string(forKey: Keys.jsonFeedURL) ?? ""
        soundEnabled = d.object(forKey: Keys.soundEnabled) as? Bool ?? true
        timeSensitive = d.object(forKey: Keys.timeSensitive) as? Bool ?? false
        backgroundRefresh = d.object(forKey: Keys.backgroundRefresh) as? Bool ?? true
        didAskForNotifications = d.object(forKey: Keys.didAskForNotifications) as? Bool ?? false
    }

    /// Список каналов из строки "a, b, c".
    var channelList: [String] {
        channels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasAnySource: Bool {
        (useTelegram && !channelList.isEmpty) || (useJSONFeed && !jsonFeedURL.isEmpty)
    }
}
