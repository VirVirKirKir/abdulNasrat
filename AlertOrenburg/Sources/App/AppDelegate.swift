import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.configure()
        BackgroundRefresher.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if AlertCenter.shared.settings.backgroundRefresh {
            BackgroundRefresher.shared.schedule()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in
            await AlertCenter.shared.refreshPermissionStatus()
        }
    }
}
