import Foundation
import UIKit
import UserNotifications

/// Результат проверки одного источника — показывается в диагностике.
struct SourceReport: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var urlString: String
    var httpStatus: Int?
    var messageCount: Int
    var eventCount: Int
    var error: String?
    var checkedAt: Date = Date()
}

struct SourceResult: Sendable {
    var events: [AlertEvent]
    var report: SourceReport
}

/// Центральное состояние: история, проверка источников, доставка уведомлений.
@MainActor
final class AlertCenter: ObservableObject {

    static let shared = AlertCenter()

    let settings: AppSettings
    private let notifications = NotificationService.shared

    @Published private(set) var alerts: [AlertEvent] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var reports: [SourceReport] = []
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined

    private var seen: Set<String> = []
    private var hasBaseline = false
    private var storeURL: URL
    private let seenKey = "seenAlertIDs"
    private let baselineKey = "didBaselineAlerts"

    private init() {
        settings = AppSettings()

        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        storeURL = base.appendingPathComponent("alert-orenburg-history.json")

        seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        hasBaseline = UserDefaults.standard.bool(forKey: baselineKey)
        loadHistory()
    }

    // MARK: - Жизненный цикл

    func bootstrap() async {
        notifications.configure()
        await refreshPermissionStatus()

        if permission == .notDetermined && !settings.didAskForNotifications {
            settings.didAskForNotifications = true
            await requestPermission()
        }

        await refresh()
    }

    func refreshPermissionStatus() async {
        permission = await notifications.currentStatus()
    }

    func requestPermission() async {
        _ = await notifications.requestAuthorization()
        await refreshPermissionStatus()
    }

    // MARK: - Проверка источников

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var found: [AlertEvent] = []
        var newReports: [SourceReport] = []

        if settings.useTelegram && !settings.channelList.isEmpty {
            for channel in settings.channelList {
                let result = await TelegramSource.fetch(
                    channel: channel,
                    requireRegion: settings.regionFilter
                )
                found.append(contentsOf: result.events)
                newReports.append(result.report)
            }
        }

        if settings.useJSONFeed {
            let trimmed = settings.jsonFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.scheme != nil {
                let result = await JSONFeedSource.fetch(url: url)
                found.append(contentsOf: result.events)
                newReports.append(result.report)
            } else if !trimmed.isEmpty {
                newReports.append(SourceReport(
                    name: "JSON-лента",
                    urlString: trimmed,
                    httpStatus: nil,
                    messageCount: 0,
                    eventCount: 0,
                    error: "Некорректный URL"
                ))
            }
        }

        reports = newReports
        lastChecked = Date()
        lastError = newReports.compactMap(\.error).first

        let unique = deduplicated(found)
        merge(unique)
        await deliverNew(unique)
        await refreshPermissionStatus()
    }

    private func deduplicated(_ events: [AlertEvent]) -> [AlertEvent] {
        var byID: [String: AlertEvent] = [:]
        for event in events where byID[event.id] == nil {
            byID[event.id] = event
        }
        return Array(byID.values)
    }

    private func merge(_ events: [AlertEvent]) {
        guard !events.isEmpty else { return }
        var byID = Dictionary(
            alerts.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for event in events {
            byID[event.id] = event
        }
        alerts = byID.values
            .sorted { $0.date > $1.date }
            .prefix(300)
            .map { $0 }
        saveHistory()
    }

    private func deliverNew(_ events: [AlertEvent]) async {
        guard !events.isEmpty else { return }

        // Первая загрузка не должна «выстреливать» всей старой историей канала,
        // но если прямо сейчас действует угроза — предупредить нужно.
        if !hasBaseline {
            seen.formUnion(events.map(\.id))
            hasBaseline = true
            UserDefaults.standard.set(true, forKey: baselineKey)
            persistSeen()

            let recentDanger = events
                .filter { $0.kind.isDanger && Date().timeIntervalSince($0.date) < 30 * 60 }
                .sorted { $0.date < $1.date }
            for event in recentDanger {
                await notifications.deliver(
                    event,
                    soundEnabled: settings.soundEnabled,
                    timeSensitive: settings.timeSensitive
                )
            }
            return
        }

        let fresh = events
            .filter { !seen.contains($0.id) }
            .sorted { $0.date < $1.date }

        guard !fresh.isEmpty else { return }

        for event in fresh {
            seen.insert(event.id)
            let age = Date().timeIntervalSince(event.date)
            if age < 3 * 3600 {
                await notifications.deliver(
                    event,
                    soundEnabled: settings.soundEnabled,
                    timeSensitive: settings.timeSensitive
                )
            }
        }
        persistSeen()
    }

    // MARK: - Тест

    func sendTest(_ kind: AlertKind) async {
        if permission == .notDetermined {
            await requestPermission()
        }

        let event = AlertEvent(
            id: "test-\(kind.rawValue)-\(UUID().uuidString)",
            kind: kind,
            date: Date(),
            source: "Тест",
            rawText: nil,
            isTest: true
        )
        alerts.insert(event, at: 0)
        if alerts.count > 300 { alerts.removeLast(alerts.count - 300) }
        saveHistory()

        await notifications.deliver(
            event,
            soundEnabled: settings.soundEnabled,
            timeSensitive: settings.timeSensitive
        )
    }

    // MARK: - История

    func clearHistory() {
        alerts = []
        saveHistory()
    }

    private func loadHistory() {
        guard
            let data = try? Data(contentsOf: storeURL),
            let decoded = try? JSONDecoder().decode([AlertEvent].self, from: data)
        else { return }
        alerts = decoded.sorted { $0.date > $1.date }
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func persistSeen() {
        let list = Array(Array(seen).suffix(1500))
        UserDefaults.standard.set(list, forKey: seenKey)
    }

    // MARK: - Диагностика

    func soundFileAvailable() -> Bool {
        ["caf", "aiff", "wav"].contains {
            Bundle.main.url(forResource: "sirens", withExtension: $0) != nil
        }
    }
}
