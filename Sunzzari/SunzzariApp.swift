import SwiftUI
import UserNotifications

extension Notification.Name {
    static let openWeeklyBestOf = Notification.Name("sunzzari.openWeeklyBestOf")
}

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
        // Shared HTTP cache sized for gallery thumbnails — AsyncImage piggybacks on URLCache.shared.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 500_000_000)
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
        // Serif tab-bar labels so UIKit chrome matches the SwiftUI .fontDesign(.serif) inheritance.
        let tabLabelDescriptor = UIFont.systemFont(ofSize: 10, weight: .medium).fontDescriptor.withDesign(.serif)
        if let td = tabLabelDescriptor {
            let font = UIFont(descriptor: td, size: 10)
            tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font]   = font
            tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes[.font] = font
            tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes[.font]    = font
            tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes[.font]  = font
            tabAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes[.font]   = font
            tabAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes[.font] = font
        }
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
            // Weekly Sunday 8pm prompt for batch Best Of capture
            await NotificationService.shared.scheduleWeeklyBestOfPrompt()
            // Clear any stale midnight trigger notifications left from previous builds
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let stale = pending.filter { $0.identifier.hasPrefix("sunzzari-midnight-") }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
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
        // Increment badge for remote pushes (local notifications set their own badge)
        let id = notification.request.identifier
        if !id.hasPrefix("sunzzari-boop-") && !id.hasPrefix("sunzzari-status-") {
            let current = UIApplication.shared.applicationIconBadgeNumber
            UNUserNotificationCenter.current().setBadgeCount(current + 1)
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["destination"] as? String == "weekly-bestof" {
            NotificationCenter.default.post(name: .openWeeklyBestOf, object: nil)
        }
        completionHandler()
    }
}
