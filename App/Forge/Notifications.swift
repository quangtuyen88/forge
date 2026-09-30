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
    removeReminders(matching: { $0.hasPrefix("forge.reminder.") })
    add("forge.reminder", content, UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
  }

  static func notifyWeekReview(week: Int, headline: String) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Week \(week) review is ready", bundle: L10n.bundle)
    content.body = headline
    add("forge.week", content, UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
  }

  static func cancelReminder() {
    removeReminders(matching: { $0 == "forge.reminder" || $0.hasPrefix("forge.reminder.") })
  }

  /// Drops pending workout reminders whose identifier matches: the daily one and/or the training-day ones.
  private static func removeReminders(matching: @escaping (String) -> Bool) {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let ids = requests.map(\.identifier).filter(matching)
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
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

extension Notifications {
  /// One non-repeating reminder per upcoming training day, replacing the daily one.
  static func scheduleTrainingDayReminders(_ slots: [ReminderSlot]) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let stale = requests.map(\.identifier).filter {
        $0 == "forge.reminder" || $0.hasPrefix("forge.reminder.")
      }
      center.removePendingNotificationRequests(withIdentifiers: stale)
      for slot in slots {
        let content = UNMutableNotificationContent()
        content.title = ReminderSchedule.title(for: slot)
        content.body = ReminderSchedule.body(for: slot)
        let trigger = UNCalendarNotificationTrigger(
          dateMatching: Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: slot.date),
          repeats: false)
        center.add(
          UNNotificationRequest(
            identifier: "forge.reminder.\(Int(slot.date.timeIntervalSince1970))",
            content: content,
            trigger: trigger))
      }
    }
  }

  /// The earliest pending workout reminder, daily or training-day, for previews.
  static func nextReminder() async -> (title: String, body: String)? {
    let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
    func fireDate(_ request: UNNotificationRequest) -> Date {
      (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
    let reminders = requests.filter {
      $0.identifier == "forge.reminder" || $0.identifier.hasPrefix("forge.reminder.")
    }
    guard let earliest = reminders.min(by: { fireDate($0) < fireDate($1) }) else { return nil }
    return (earliest.content.title, earliest.content.body)
  }
}
