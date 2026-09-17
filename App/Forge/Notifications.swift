import UserNotifications

enum Notifications {
  static func requestAuthorization() async {
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
  }

  static func scheduleDailyReminder(hour: Int, minute: Int, body: String? = nil) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Time to train", bundle: L10n.bundle)
    content.body = body ?? String(localized: "Open Regulift for today's session.", bundle: L10n.bundle)
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    add("forge.reminder", content, UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
  }

  static func notifyWeekReview(week: Int, headline: String) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Week \(week) review is ready", bundle: L10n.bundle)
    content.body = headline
    add("forge.week", content, UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
  }

  static func cancelReminder() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["forge.reminder"])
  }

  static func notifyDeload(daysPerWeek: Int) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Deload week", bundle: L10n.bundle)
    content.body = String(localized: "Half the sets, RPE ≤ 6 for \(daysPerWeek) sessions. Then a fresh block.", bundle: L10n.bundle)
    add("forge.deload", content, UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
  }

  static func celebratePR(_ name: String) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "New PR", bundle: L10n.bundle)
    content.body = String(localized: "\(name). Log it, own it.", bundle: L10n.bundle)
    add("forge.pr", content, UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
  }

  static func scheduleReengagement(days: Int = 3) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Your next session is ready", bundle: L10n.bundle)
    content.body = String(localized: "Three days off. The plan waited.", bundle: L10n.bundle)
    add("forge.back", content, UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(days * 86400), repeats: false))
  }

  static func cancelReengagement() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["forge.back"])
  }

  private static func add(_ id: String, _ content: UNMutableNotificationContent, _ trigger: UNNotificationTrigger) {
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
  }
}
