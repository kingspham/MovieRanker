import Foundation
import UserNotifications
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // UserDefaults keys
    private let kEnabledKey = "notif.enabled"
    private let kDailyTimeKey = "notif.daily.time"        // Date (hour/minute used)
    private let kWeeklyEnabledKey = "notif.weekly.enabled"
    private let kLastFriendActivityKey = "notif.lastFriendActivityAt" // Date

    private override init() { super.init() }

    // MARK: Setup / Permission

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let ok = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if ok { setEnabled(true) }
            return ok
        } catch { return false }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: kEnabledKey)
        if !on { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    }

    func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: kEnabledKey)
    }

    // MARK: Settings accessors

    func dailyTime() -> Date {
        if let d = UserDefaults.standard.object(forKey: kDailyTimeKey) as? Date { return d }
        // default 8pm local
        var comps = DateComponents()
        comps.hour = 20; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    func setDailyTime(_ d: Date) {
        UserDefaults.standard.set(d, forKey: kDailyTimeKey)
    }

    func weeklyEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: kWeeklyEnabledKey)
    }

    func setWeeklyEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: kWeeklyEnabledKey)
    }

    // MARK: Scheduling

    func rescheduleAll(modelContext: ModelContext) {
        guard isEnabled() else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduleDailyLogReminder()
        if weeklyEnabled() { scheduleWeeklyRecap() }
        scheduleCompareQueueIfNeeded(modelContext: modelContext)
    }

    /// Daily “log something you watched”
    func scheduleDailyLogReminder() {
        let triggerDate = Self.nextTrigger(at: dailyTime(), repeatEveryDay: true)
        let content = UNMutableNotificationContent()
        content.title = "Log a movie 🎬"
        content.body = "Watched anything today? Add it now."
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "daily.log",
            content: content,
            trigger: triggerDate
        )
        UNUserNotificationCenter.current().add(req)
    }

    /// Weekly recap (Sunday 7pm local)
    func scheduleWeeklyRecap() {
        var comps = DateComponents()
        comps.weekday = 1           // 1=Sunday in iOS calendar by default
        comps.hour = 19; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Weekly recap"
        content.body = "See your top movies and what friends watched this week."
        content.sound = .default

        let req = UNNotificationRequest(identifier: "weekly.recap", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Compare queue: if you have 3+ movies without a score, nudge once
    func scheduleCompareQueueIfNeeded(modelContext: ModelContext) {
        let unrated = Self.unratedMovieCount(modelContext: modelContext)
        guard unrated >= 3 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rank your movies ⭐️"
        content.body = "You have \(unrated) unrated movies—do a few quick head-to-heads."
        content.sound = .default

        // Fire once in ~2 hours
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
        let req = UNNotificationRequest(identifier: "compare.nudge", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Call after a sync when friend reviews increased; sends one immediate local notification.
    func notifyFriendActivityIfNew(newestAt: Date?) {
        guard isEnabled(), let newestAt else { return }
        let last = (UserDefaults.standard.object(forKey: kLastFriendActivityKey) as? Date) ?? .distantPast
        guard newestAt > last else { return }

        let content = UNMutableNotificationContent()
        content.title = "New friend reviews"
        content.body = "Your friends posted new reviews. Check them out!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: "friends.activity", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)

        UserDefaults.standard.set(newestAt, forKey: kLastFriendActivityKey)
    }

    // MARK: Helpers

    private static func nextTrigger(at base: Date, repeatEveryDay: Bool) -> UNCalendarNotificationTrigger {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: base)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeatEveryDay)
    }

    private static func unratedMovieCount(modelContext: ModelContext) -> Int {
        let movies: [Movie] = (try? modelContext.fetch(FetchDescriptor<Movie>())) ?? []
        let scores: [Score] = (try? modelContext.fetch(FetchDescriptor<Score>())) ?? []
        let withScore = Set(scores.map { $0.movieID })
        return movies.filter { !withScore.contains($0.id) }.count
    }

    // MARK: UNUserNotificationCenterDelegate

    // Show banner even when app is foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

