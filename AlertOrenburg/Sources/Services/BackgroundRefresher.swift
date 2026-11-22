import Foundation
import BackgroundTasks
import UIKit

/// Фоновое обновление раз в ~15+ минут (iOS решает сам, когда дать время).
final class BackgroundRefresher {

    static let shared = BackgroundRefresher()
    static let taskIdentifier = "ru.alert.orenburg.refresh"

    private init() {}

    private var isRegistered = false

    func register() {
        guard !isRegistered else { return }
        isRegistered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Симулятор и отключённый Background App Refresh дают ошибку — это нормально.
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()

        let work = Task { @MainActor in
            await AlertCenter.shared.refresh()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
