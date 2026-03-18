import SwiftUI
import UserNotifications

@main
struct SunzzariApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Handle background location relaunch — restart significant change monitoring immediately
        if launchOptions?[UIApplication.LaunchOptionsKey.location] != nil {
            LocationService.shared.startSignificantLocationChanges()
        }
        // ── Global nav bar appearance (must run before any views are created) ──
        // Uses UINavigationBarAppearance so .toolbarBackground() in views cannot
        // override the serif font — this is the only reliable approach in iOS 15+.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0x1F/255, green: 0x29/255, blue: 0x37/255, alpha: 1) // sunSurface #1F2937
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        // New York serif via .withDesign(.serif) on the system large title font descriptor
        let serifDescriptor = UIFont.systemFont(ofSize: 34, weight: .bold).fontDescriptor.withDesign(.serif)
        var largeTitleAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        if let sd = serifDescriptor { largeTitleAttrs[.font] = UIFont(descriptor: sd, size: 34) }
        navAppearance.largeTitleTextAttributes = largeTitleAttrs
        UINavigationBar.appearance().standardAppearance   = navAppearance
        UINavigationBar.appearance().compactAppearance    = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        // ── Global tab bar appearance ──
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(red: 0x1F/255, green: 0x29/255, blue: 0x37/255, alpha: 1) // sunSurface
        UITabBar.appearance().standardAppearance    = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance  = tabAppearance

        UNUserNotificationCenter.current().delegate = self
        // Register for remote (APNs) push notifications
        UIApplication.shared.registerForRemoteNotifications()
        Task {
            await NotificationService.shared.requestPermission()
            // Run today's setup first (precise pick + 9am notification)
            await DailySetupService.shared.runDailySetup()
            // Safety-net: schedule 30-day fallback pool for days the app isn't opened
            let allEntries = (try? await NotionService.shared.fetchBestOf()) ?? []
            await NotificationService.shared.scheduleOnThisDay(allEntries: allEntries)
            // Schedule 12:01am midnight triggers for the next 30 nights
            await DailySetupService.shared.scheduleMidnightTriggers()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await StatusService.shared.storeDeviceToken(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Failed to register:", error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        if id.hasPrefix("sunzzari-midnight-") {
            // 12:01am trigger fired while app is in foreground — run daily setup for the new day
            Task { await DailySetupService.shared.runDailySetup(force: true) }
            completionHandler([]) // no banner for the midnight trigger
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
