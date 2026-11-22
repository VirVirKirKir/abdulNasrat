import Foundation
import UserNotifications
import UIKit
import SwiftUI

/// Постановка локальных уведомлений (работают без сервера и без платного аккаунта).
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private var isConfigured = false

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let categories: Set<UNNotificationCategory> = Set(AlertKind.allCases.map { kind in
            let open = UNNotificationAction(identifier: "open", title: "Открыть", options: [.foreground])
            return UNNotificationCategory(
                identifier: kind.rawValue,
                actions: [open],
                intentIdentifiers: [],
                options: []
            )
        })
        center.setNotificationCategories(categories)
    }

    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func deliver(_ event: AlertEvent, soundEnabled: Bool, timeSensitive: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = event.kind.notificationTitle
        content.body = event.kind.notificationBody
        content.categoryIdentifier = event.kind.rawValue
        content.threadIdentifier = "orenburg-alerts"
        content.userInfo = ["eventID": event.id, "kind": event.kind.rawValue]
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        content.relevanceScore = timeSensitive ? 1.0 : 0.5

        if soundEnabled {
            content.sound = sound(for: event.kind)
        }

        if let attachment = artworkAttachment(for: event.kind) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// iOS принимает для звука уведомления только caf/aiff/wav (не mp3).
    /// Сборка конвертирует sirens.mp3 в sirens.caf, поэтому проверяем несколько вариантов.
    private func sound(for kind: AlertKind) -> UNNotificationSound {
        guard kind.soundFileName != nil else { return .default }
        for ext in ["caf", "aiff", "wav"] {
            if Bundle.main.url(forResource: "sirens", withExtension: ext) != nil {
                return UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirens.\(ext)"))
            }
        }
        return .default
    }

    /// Картинка с дроном/ракетой для уведомления.
    private func artworkAttachment(for kind: AlertKind) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(
            content: NotificationArtwork(kind: kind)
                .frame(width: 720, height: 360)
        )
        renderer.scale = 2

        guard
            let image = renderer.uiImage,
            let data = image.pngData()
        else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alert-artwork-\(kind.rawValue).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        return try? UNNotificationAttachment(
            identifier: "artwork-\(kind.rawValue)",
            url: url,
            options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
