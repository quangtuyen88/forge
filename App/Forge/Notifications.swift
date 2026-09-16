import UserNotifications

enum Notifications {
  static func requestAuthorization() async {
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
  }

  static func scheduleDailyReminder(hour: Int, minute: Int) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Time to train")
    content.body = String(localized: "Open Regulift for today's session.")
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    add("forge.reminder", content, UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
  }

  static func cancelReminder() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["forge.reminder"])
  }

  static func notifyDeload(daysPerWeek: Int) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Deload week")
    content.body = String(localized: "Half the sets, RPE ≤ 6 for \(daysPerWeek) sessions. Then a fresh block.")
    add("forge.deload", content, UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
  }

  static func celebratePR(_ name: String) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "New PR")
    content.body = String(localized: "\(name). Log it, own it.")
    add("forge.pr", content, UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
  }

  static func scheduleReengagement(days: Int = 3) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Your next session is ready")
    content.body = String(localized: "Three days off. The plan waited.")
    add("forge.back", content, UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(days * 86400), repeats: false))
  }

  static func cancelReengagement() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["forge.back"])
  }

  private static func add(_ id: String, _ content: UNMutableNotificationContent, _ trigger: UNNotificationTrigger) {
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
  }
}
