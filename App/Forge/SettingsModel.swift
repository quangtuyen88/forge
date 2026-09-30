import ForgeCore
import Foundation

struct PlanOption: Identifiable, Equatable {
  let id: String
  let title: String
  let detail: String
  let weeklySets: Int
  let isCurrent: Bool
}

/// The plan-choice sheets: option lists and split/goal wording, all derived from `Program.week`.
enum PlanPreview {
  static func weeklySets(_ days: [PlannedDay]) -> Int {
    days.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets } }
  }

  static func liftsPerDay(_ days: [PlannedDay]) -> Int {
    days.map(\.exercises.count).max() ?? 0
  }

  static func dayOptions(input: ProfileInput, week: Int) -> [PlanOption] {
    let currentLifts = liftsPerDay(Program.week(week, profile: input))
    return (2...6).map { days in
      var copy = input
      copy.daysPerWeek = days
      let plan = Program.week(week, profile: copy)
      var detail = splitDescription(days: days, style: input.split)
      let lifts = liftsPerDay(plan)
      if lifts > 0, lifts != currentLifts {
        detail += " · " + String(localized: "\(lifts) lifts a day", bundle: L10n.bundle)
      }
      return PlanOption(
        id: "\(days)",
        title: String(localized: "\(days) days", bundle: L10n.bundle),
        detail: detail,
        weeklySets: weeklySets(plan),
        isCurrent: days == input.daysPerWeek)
    }
  }

  static func minuteOptions(input: ProfileInput, week: Int) -> [PlanOption] {
    SessionLength.allCases.map { length in
      var copy = input
      copy.sessionLength = length
      let plan = Program.week(week, profile: copy)
      let counts = plan.map(\.exercises.count)
      let most = counts.max() ?? 0
      let detail = counts.allSatisfy { $0 == counts.first }
        ? String(localized: "\(most) lifts a session", bundle: L10n.bundle)
        : String(localized: "Up to \(most) lifts a session", bundle: L10n.bundle)
      return PlanOption(
        id: "\(length.rawValue)",
        title: String(localized: "\(length.rawValue) min", bundle: L10n.bundle),
        detail: detail,
        weeklySets: weeklySets(plan),
        isCurrent: length == input.sessionLength)
    }
  }

  static func goalOptions(input: ProfileInput, week: Int) -> [PlanOption] {
    Goal.allCases.map { goal in
      var copy = input
      copy.goal = goal
      let plan = Program.week(week, profile: copy)
      let detail = plan.flatMap(\.exercises).first { $0.exercise.isCompound }.map { compound in
        let range = "\(compound.repRange.lowerBound)–\(compound.repRange.upperBound)"
        return String(localized: "Compound lifts \(range) reps", bundle: L10n.bundle)
      } ?? goalTitle(goal)
      return PlanOption(
        id: goal.rawValue,
        title: goalTitle(goal),
        detail: detail,
        weeklySets: weeklySets(plan),
        isCurrent: goal == input.goal)
    }
  }

  static func splitDescription(days: Int, style: SplitStyle) -> String {
    let names = Program.split(daysPerWeek: days, style: style).map(localizedDayName)
    if names.count >= 4, names.count % 2 == 0 {
      let half = names.count / 2
      if names[..<half].elementsEqual(names[half...]) {
        return String(localized: "\(list(Array(names[..<half]))), twice", bundle: L10n.bundle)
      }
    }
    var unique: [String] = []
    for name in names where !unique.contains(name) { unique.append(name) }
    return list(unique)
  }

  private static func list(_ names: [String]) -> String {
    let formatter = ListFormatter()
    formatter.locale = L10n.locale
    return formatter.string(from: names) ?? names.joined(separator: ", ")
  }

  static func splitName(_ style: SplitStyle, days: Int) -> String {
    switch style {
    case .fullBody, .upperLower, .pushPullLegs, .pushPull, .arnold:
      return style.name
    case .auto:
      if days <= 3 { return SplitStyle.fullBody.name }
      if days == 4 { return SplitStyle.upperLower.name }
      if days >= 6 { return SplitStyle.pushPullLegs.name }
      return SplitStyle.auto.name
    }
  }

  static func planDetailsValue(experience: Experience, split: SplitStyle, days: Int) -> String {
    "\(experience.name) · \(splitName(split, days: days))"
  }

  static func goalPhrase(_ goal: Goal) -> String {
    switch goal {
    case .hypertrophy: return String(localized: "build muscle", bundle: L10n.bundle)
    case .strength: return String(localized: "move more weight", bundle: L10n.bundle)
    case .both: return String(localized: "build size and strength", bundle: L10n.bundle)
    }
  }

  static func goalTitle(_ goal: Goal) -> String {
    switch goal {
    case .hypertrophy: return String(localized: "Build muscle", bundle: L10n.bundle)
    case .strength: return String(localized: "Move more weight", bundle: L10n.bundle)
    case .both: return String(localized: "Size and strength", bundle: L10n.bundle)
    }
  }

  static func deltaText(_ delta: Int) -> String {
    if delta > 0 { return "+\(delta)" }
    if delta < 0 { return "\u{2212}\(abs(delta))" }
    return ""
  }
}

/// Barbell plate arithmetic for the Plates page.
enum PlateMath {
  static func catalogue(usesLb: Bool) -> [Double] {
    usesLb ? [45, 35, 25, 10, 5, 2.5, 1.25] : [25, 20, 15, 10, 5, 2.5, 1.25, 0.5]
  }

  static func barChoices(usesLb: Bool, current: Double) -> [Double] {
    var choices = usesLb ? [45.0, 35.0, 25.0] : [20.0, 15.0, 10.0]
    if !choices.contains(current) {
      choices.append(current)
      choices.sort(by: >)
    }
    return choices
  }

  static func smallestJump(owned: [Double]) -> Double? {
    guard let lightest = owned.filter({ $0 > 0 }).min() else { return nil }
    return 2 * lightest
  }

  static func missingFinerPlate(owned: [Double], usesLb: Bool) -> Double? {
    guard let lightest = owned.filter({ $0 > 0 }).min() else { return nil }
    return catalogue(usesLb: usesLb).filter { $0 < lightest }.min()
  }

  static func sizeRank(_ weight: Double, usesLb: Bool) -> Int {
    let sizes = catalogue(usesLb: usesLb)
    if let exact = sizes.firstIndex(of: weight) { return exact }
    var nearest = 0
    for index in sizes.indices where abs(sizes[index] - weight) < abs(sizes[nearest] - weight) {
      nearest = index
    }
    return nearest
  }
}

extension ExerciseSwap {
  /// The line under the new lift's name: what it replaces, or that it was dropped or added, and on which day.
  var detail: String {
    switch (fromName, toName) {
    case let (from?, _?): return String(localized: "Instead of \(from) · \(dayName)", bundle: L10n.bundle)
    case (_?, nil): return String(localized: "Dropped · \(dayName)", bundle: L10n.bundle)
    case (nil, _?): return String(localized: "Added · \(dayName)", bundle: L10n.bundle)
    default: return dayName
    }
  }
}

struct BarbellExample: Equatable {
  let liftName: String
  let load: Double
  let usesLb: Bool
  let perSide: [Double]
  let isToday: Bool
}

/// Concrete examples on the Plates page, built from the lifter's own plan and history.
enum SettingsExamples {
  @MainActor
  static func barbellExample(profile: UserProfile, sessions: [WorkoutSession]) -> BarbellExample? {
    let today = RoutineAdaptationService.currentDay(profile: profile, sessions: sessions)
    let days = Program.week(profile.currentWeek(sessions: sessions), profile: profile.profileInput)
    let fallback = days.isEmpty ? nil : days[profile.nextDayIndex % days.count]
    guard let day = today ?? fallback,
      let planned = day.exercises.first(where: { $0.exercise.equipment == .barbell })
    else { return nil }
    let id = planned.exercise.id
    let kg = suggestedStartKg(
      for: planned, last: lastSets(id, in: sessions, profile: profile), profile: profile)
    let usesLb = profile.isLb(for: id)
    let bar = usesLb ? profile.barLb : profile.barKg
    let owned = usesLb ? profile.platesLb : profile.platesKg
    guard let jump = PlateMath.smallestJump(owned: owned) else { return nil }
    var load = profile.display(kg: kg, for: id)
    load = bar + ((load - bar) / jump).rounded() * jump
    guard load > bar,
      let perSide = Plates.perSide(target: load, bar: bar, available: owned),
      !perSide.isEmpty
    else { return nil }
    return BarbellExample(
      liftName: planned.exercise.localizedName, load: load, usesLb: usesLb, perSide: perSide,
      isToday: today != nil && profile.weekPlan != nil)
  }
}

struct ReminderSlot: Equatable, Sendable {
  let date: Date
  let sessionName: String?
  let lifts: Int
  let minutes: Int
  let firstLiftName: String?
}

/// Training-day reminder times: this week's plan days first, then the weekday pattern they define.
enum ReminderSchedule {
  static func slots(
    plan: WeekPlan?, hour: Int, minute: Int, now: Date, calendar: Calendar,
    horizonDays: Int = 14, limit: Int = 20
  ) -> [ReminderSlot]? {
    guard let plan, !plan.days.isEmpty else { return nil }
    let startOfToday = calendar.startOfDay(for: now)
    guard let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: startOfToday),
      let planEnd = calendar.date(byAdding: .day, value: 7, to: plan.weekStart)
    else { return nil }
    var weekdays: Set<Int> = []
    var byDay: [Date: ReminderSlot] = [:]
    for day in plan.days where day.state != .skipped {
      guard let effective = day.state == .moved ? day.movedToDate : day.date else { continue }
      weekdays.insert(calendar.component(.weekday, from: effective))
      if day.state == .completed { continue }
      let key = calendar.startOfDay(for: effective)
      if let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: effective),
        at > now, at < horizonEnd, byDay[key] == nil
      {
        byDay[key] = ReminderSlot(
          date: at,
          sessionName: localizedDayName(day.sessionName),
          lifts: day.exerciseIDs.count,
          minutes: day.timeBudgetMinutes,
          firstLiftName: day.exerciseIDs.first.flatMap { ExerciseDB.find($0)?.localizedName })
      }
    }
    var cursor = max(startOfToday, planEnd)
    while cursor < horizonEnd {
      if weekdays.contains(calendar.component(.weekday, from: cursor)), byDay[cursor] == nil,
        let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: cursor),
        at > now
      {
        byDay[cursor] = ReminderSlot(
          date: at, sessionName: nil, lifts: 0, minutes: 0, firstLiftName: nil)
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return byDay.values.sorted { $0.date < $1.date }.prefix(limit).map { $0 }
  }

  static func title(for slot: ReminderSlot) -> String {
    if let name = slot.sessionName {
      return String(localized: "\(name) today", bundle: L10n.bundle)
    }
    return String(localized: "Time to train", bundle: L10n.bundle)
  }

  static func body(for slot: ReminderSlot) -> String {
    if slot.lifts > 0, slot.minutes > 0, let first = slot.firstLiftName {
      return String(
        localized: "\(slot.lifts) lifts, about \(slot.minutes) min. \(first) first.",
        bundle: L10n.bundle)
    }
    if slot.lifts > 0, slot.minutes > 0 {
      return String(localized: "\(slot.lifts) lifts, about \(slot.minutes) min.", bundle: L10n.bundle)
    }
    return String(localized: "Open Regulift for today's session.", bundle: L10n.bundle)
  }
}

enum ReminderScheduler {
  static let trainingDaysKey = "reminderTrainingDaysOnly"

  /// Re-posts the workout reminder for the profile's settings: training days only when chosen and a week plan exists, else daily.
  @MainActor
  static func reschedule(profile: UserProfile, body: String? = nil, now: Date = .now) {
    guard let hour = profile.reminderHour else {
      Notifications.cancelReminder()
      return
    }
    if UserDefaults.standard.bool(forKey: trainingDaysKey),
      let slots = ReminderSchedule.slots(
        plan: profile.weekPlan, hour: hour, minute: profile.reminderMinute, now: now,
        calendar: .current)
    {
      Notifications.scheduleTrainingDayReminders(slots)
    } else {
      Notifications.scheduleDailyReminder(hour: hour, minute: profile.reminderMinute, body: body)
    }
  }
}

/// Value formatting shared by the Settings rows and sub-pages.
enum SettingsFormat {
  static func mmss(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  static func languageName(_ code: String) -> String {
    switch code {
    case "ja": return "日本語"
    case "ko": return "한국어"
    case "vi": return "Tiếng Việt"
    default: return "English"
    }
  }

  static func gymName(equipment: [String]) -> String {
    GymPreset.matching(Set(equipment.compactMap(Equipment.init(rawValue:))))?.name
      ?? String(localized: "Custom", bundle: L10n.bundle)
  }

  // ponytail: "now" literal matches only en; revisit when translated catalogs ship
  static func relativeSync(_ date: Date?) -> String {
    guard let date else { return String(localized: "never", bundle: L10n.bundle) }
    let relative = date.formatted(.relative(presentation: .named).locale(L10n.locale))
    return relative == "now" ? String(localized: "just now", bundle: L10n.bundle) : relative
  }

  /// The long subscription line; the Test Store branch reads Store.usesTestStore, so this stays on the main actor.
  @MainActor
  static func subscriptionStatus(_ status: SubStatus) -> String {
    switch status {
    case .trial(let ends):
      return String(
        localized: "Trial · ends \(ends.formatted(.dateTime.day().month().locale(L10n.locale)))",
        bundle: L10n.bundle)
    case .active(let renews):
      if Store.usesTestStore, let renews {
        return
          "Active · Test Store · expires \(renews.formatted(.dateTime.day().month().hour().minute().locale(L10n.locale)))"
      }
      return renews.map {
        String(
          localized: "Active · renews \($0.formatted(.dateTime.day().month().locale(L10n.locale)))",
          bundle: L10n.bundle)
      } ?? String(localized: "Active", bundle: L10n.bundle)
    case .grace: return String(localized: "Grace period · update payment", bundle: L10n.bundle)
    case .expired: return String(localized: "Expired", bundle: L10n.bundle)
    case .none: return String(localized: "Not subscribed", bundle: L10n.bundle)
    }
  }

  static func subscriptionShort(_ status: SubStatus) -> String {
    switch status {
    case .active, .grace: return String(localized: "Pro", bundle: L10n.bundle)
    case .trial: return String(localized: "Trial", bundle: L10n.bundle)
    case .expired, .none: return String(localized: "Free", bundle: L10n.bundle)
    }
  }

  static func time(hour: Int, minute: Int) -> String {
    guard
      let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
    else { return "" }
    return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))
  }
}
