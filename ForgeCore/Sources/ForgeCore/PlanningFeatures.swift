import Foundation

// MARK: - Week plan
//
// A `WeekPlan` is the proactive, dated projection of what the app intends the
// lifter to do this week. It is deliberately thin: it reuses `PlannedDay` /
// `PlannedExercise` (via `PlannedDay.id` and the exercise IDs), `ProfileInput`,
// `TrainingConstraints`, `GymProfileConfig` and `WeekStatusPolicy` rather than
// replacing them. Everything that decides *what happened* is derived — the only
// stored state is what the lifter or the app explicitly recorded.
//
// Evaluation is pure and deterministic: `now`, `calendar` and the enrollment
// date are all injected. Day boundaries go through `Calendar.startOfDay(for:)`
// so a plan authored in one time zone evaluates the same way in another.

/// How the week was authored. Mirrors the constraint signals that shaped it.
public enum WeekPlanMode: String, Codable, Equatable, Sendable, CaseIterable {
  case standard
  case travel
  case minimumEffective
  case reduced

  public var name: String {
    switch self {
    case .standard: return String(localized: "Standard", bundle: ForgeCoreResources.bundle)
    case .travel: return String(localized: "Travel", bundle: ForgeCoreResources.bundle)
    case .minimumEffective: return String(localized: "Minimum effective", bundle: ForgeCoreResources.bundle)
    case .reduced: return String(localized: "Reduced recovery", bundle: ForgeCoreResources.bundle)
    }
  }

  /// Travel and minimum-effective weeks are allowed to fall short without the
  /// shortfall being framed as failure.
  public var relaxesMissedSessions: Bool {
    self == .travel || self == .minimumEffective
  }
}

/// The lifecycle of one planned day.
///
/// `planned`, `completed`, `moved` and `skipped` are *recorded* — they are what
/// the app or the lifter wrote down. `remaining` and `missed` are *derived* by
/// `WeekPlanStatusPolicy` from the day's date, the enrollment date and the grace
/// window, and must never be written into storage by hand.
public enum WeekPlanDayState: String, Codable, Equatable, Sendable, CaseIterable {
  case planned
  case completed
  case remaining
  case missed
  case moved
  case skipped

  public var isDerived: Bool { self == .remaining || self == .missed }

  public var isSettled: Bool {
    self == .completed || self == .moved || self == .skipped
  }

  public var name: String {
    switch self {
    case .planned: return "Planned"
    case .completed: return "Completed"
    case .remaining: return "Remaining"
    case .missed: return "Missed"
    case .moved: return "Moved"
    case .skipped: return "Skipped"
    }
  }
}

/// Why a day ended up in the state the policy gave it.
public enum WeekPlanDayStatusReason: String, Codable, Equatable, Sendable, CaseIterable {
  /// The lifter trained the session.
  case completed
  /// The lifter explicitly skipped it.
  case skippedByUser
  /// The session was rescheduled to another day.
  case movedAway
  /// The day predates enrollment into the plan — never a failure.
  case beforeEnrollment
  /// The day has not started yet.
  case upcoming
  /// The day is today and the session is still owed.
  case dueToday
  /// The day is over but the grace window is still open.
  case withinGraceWindow
  /// The grace window closed with nothing recorded.
  case graceExpired

  public var name: String {
    switch self {
    case .completed: return "Completed"
    case .skippedByUser: return "Skipped"
    case .movedAway: return "Moved"
    case .beforeEnrollment: return "Before enrollment"
    case .upcoming: return "Upcoming"
    case .dueToday: return "Due today"
    case .withinGraceWindow: return "Still open"
    case .graceExpired: return "Grace window closed"
    }
  }
}

/// One dated slot in a week plan.
public struct WeekPlanDay: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  /// The calendar day this session is scheduled for.
  public var date: Date
  /// Identity of the planned session — `PlannedDay.id` when the plan came from
  /// `Program.week(_:profile:)`.
  public var plannedSessionID: String?
  public var sessionName: String
  public var exerciseIDs: [String]
  public var plannedSetCount: Int
  /// The confirmed routine application that owns this day's prescription. The full
  /// prescription is device-local; another device must review rather than regenerate it.
  public var routineApplicationID: String?
  public var gymProfileID: String?
  public var gymProfileName: String?
  public var timeBudgetMinutes: Int
  public var mode: WeekPlanMode
  public var state: WeekPlanDayState
  /// The recorded session that satisfied this day, when one exists.
  public var completedSessionID: String?
  /// Where the session went when it was moved.
  public var movedToDate: Date?
  /// Where the session came from when it was moved onto this day.
  public var movedFromDate: Date?
  /// Sessions that were moved *onto* this day, oldest first.
  public var receivedSessionIDs: [String]

  public init(
    id: String,
    date: Date,
    plannedSessionID: String? = nil,
    sessionName: String,
    exerciseIDs: [String] = [],
    plannedSetCount: Int = 0,
    routineApplicationID: String? = nil,
    gymProfileID: String? = nil,
    gymProfileName: String? = nil,
    timeBudgetMinutes: Int = 60,
    mode: WeekPlanMode = .standard,
    state: WeekPlanDayState = .planned,
    completedSessionID: String? = nil,
    movedToDate: Date? = nil,
    movedFromDate: Date? = nil,
    receivedSessionIDs: [String] = []
  ) {
    self.id = id
    self.date = date
    self.plannedSessionID = plannedSessionID
    self.sessionName = sessionName
    self.exerciseIDs = exerciseIDs
    self.plannedSetCount = plannedSetCount
    self.routineApplicationID = routineApplicationID
    self.gymProfileID = gymProfileID
    self.gymProfileName = gymProfileName
    self.timeBudgetMinutes = timeBudgetMinutes
    self.mode = mode
    self.state = state
    self.completedSessionID = completedSessionID
    self.movedToDate = movedToDate
    self.movedFromDate = movedFromDate
    self.receivedSessionIDs = receivedSessionIDs
  }
}

public struct WeekPlan: Codable, Equatable, Identifiable, Sendable {
  public static let currentSchemaVersion = 1

  /// How long after the end of a scheduled day a session may still be recorded
  /// without being counted as missed. Twelve hours means "the next morning".
  public static let defaultGraceWindow: TimeInterval = 12 * 60 * 60

  public var id: String
  /// New acceptance of even the same dated plan has a distinct identity.
  public var acceptanceID: String? = nil
  public var version: Int
  /// Local midnight of the first day of the plan.
  public var weekStart: Date
  /// The time zone the plan was authored in. Evaluation still takes an explicit
  /// calendar so callers can prove the result is zone-independent.
  public var timeZoneIdentifier: String
  /// The moment the lifter joined the plan. Days before this are never missed.
  public var enrollmentDate: Date
  public var graceWindow: TimeInterval
  public var mode: WeekPlanMode
  public var gymProfileID: String?
  public var days: [WeekPlanDay]

  public init(
    id: String,
    weekStart: Date,
    timeZoneIdentifier: String = TimeZone.current.identifier,
    enrollmentDate: Date,
    graceWindow: TimeInterval = WeekPlan.defaultGraceWindow,
    mode: WeekPlanMode = .standard,
    gymProfileID: String? = nil,
    days: [WeekPlanDay] = [],
    version: Int = WeekPlan.currentSchemaVersion
  ) {
    self.id = id
    self.version = version
    self.weekStart = weekStart
    self.timeZoneIdentifier = timeZoneIdentifier
    self.enrollmentDate = enrollmentDate
    self.graceWindow = max(0, graceWindow)
    self.mode = mode
    self.gymProfileID = gymProfileID
    self.days = days
  }

  /// The calendar the plan should be interpreted in, honouring its own zone.
  public func resolvedCalendar(_ base: Calendar = .current) -> Calendar {
    var calendar = base
    if let zone = TimeZone(identifier: timeZoneIdentifier) { calendar.timeZone = zone }
    return calendar
  }

  public func day(on date: Date, calendar base: Calendar = .current) -> WeekPlanDay? {
    let calendar = resolvedCalendar(base)
    return days.first { calendar.isDate($0.date, inSameDayAs: date) }
  }

  // MARK: recorded transitions

  /// Reschedules a session. The source day becomes `.moved` and the destination
  /// either absorbs the session or grows a new day carrying its identity.
  @discardableResult
  public mutating func move(
    dayID: String,
    to date: Date,
    calendar base: Calendar = .current
  ) -> Bool {
    let calendar = resolvedCalendar(base)
    guard let index = days.firstIndex(where: { $0.id == dayID }) else { return false }
    let source = days[index]
    let sourceStart = calendar.startOfDay(for: source.date)
    let destination = calendar.startOfDay(for: date)
    guard sourceStart != destination else { return false }

    days[index].state = .moved
    days[index].movedToDate = destination

    if let existing = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
      var received = days[existing].receivedSessionIDs
      received.append(source.plannedSessionID ?? source.id)
      days[existing].receivedSessionIDs = received
      if days[existing].state == .moved { days[existing].state = .planned }
    } else {
      let moved = WeekPlanDay(
        id: "\(source.id)@\(Int(destination.timeIntervalSince1970))",
        date: destination,
        plannedSessionID: source.plannedSessionID,
        sessionName: source.sessionName,
        exerciseIDs: source.exerciseIDs,
        plannedSetCount: source.plannedSetCount,
        routineApplicationID: source.routineApplicationID,
        gymProfileID: source.gymProfileID,
        gymProfileName: source.gymProfileName,
        timeBudgetMinutes: source.timeBudgetMinutes,
        mode: source.mode,
        state: .planned,
        movedFromDate: sourceStart)
      days.append(moved)
      days.sort { $0.date < $1.date }
    }
    return true
  }

  @discardableResult
  public mutating func complete(dayID: String, sessionID: String) -> Bool {
    guard let index = days.firstIndex(where: { $0.id == dayID }) else { return false }
    days[index].state = .completed
    days[index].completedSessionID = sessionID
    return true
  }

  @discardableResult
  public mutating func skip(dayID: String) -> Bool {
    guard let index = days.firstIndex(where: { $0.id == dayID }) else { return false }
    days[index].state = .skipped
    days[index].completedSessionID = nil
    return true
  }

  // MARK: evaluation

  public func evaluation(now: Date = .now, calendar base: Calendar = .current)
    -> WeekPlanEvaluation
  {
    WeekPlanStatusPolicy.evaluation(
      plan: self, now: now, calendar: resolvedCalendar(base))
  }

  public func validation(now: Date = .now, calendar base: Calendar = .current)
    -> WeekPlanValidation
  {
    WeekPlanValidationPolicy.validate(plan: self, now: now, calendar: resolvedCalendar(base))
  }

  /// Hand-off to the existing week-status policy so a week plan and the rest of
  /// the app describe the same week the same way. `daysLeft` counts the plan
  /// days that are still actionable.
  public func weekStatusPresentation(
    now: Date = .now,
    calendar base: Calendar = .current
  ) -> WeekStatusPresentation {
    let calendar = resolvedCalendar(base)
    let evaluation = evaluation(now: now, calendar: calendar)
    let daysLeft = evaluation.days.filter { $0.deadline > now && $0.state == .remaining }.count
    return WeekStatusPolicy.presentation(
      planned: evaluation.counts.scheduled,
      recorded: evaluation.counts.completed,
      daysLeft: daysLeft,
      enrollmentDate: enrollmentDate,
      now: now,
      calendar: calendar)
  }
}

public struct WeekPlanDayEvaluation: Equatable, Identifiable, Sendable {
  public var id: String { dayID }
  public let dayID: String
  public let date: Date
  public let state: WeekPlanDayState
  public let reason: WeekPlanDayStatusReason
  /// False for days that predate enrollment — they are excluded from the plan.
  public let isCountedInPlan: Bool
  public let plannedSessionID: String?
  /// The instant after which an unrecorded session becomes missed.
  public let deadline: Date

  public init(
    dayID: String,
    date: Date,
    state: WeekPlanDayState,
    reason: WeekPlanDayStatusReason,
    isCountedInPlan: Bool,
    plannedSessionID: String?,
    deadline: Date
  ) {
    self.dayID = dayID
    self.date = date
    self.state = state
    self.reason = reason
    self.isCountedInPlan = isCountedInPlan
    self.plannedSessionID = plannedSessionID
    self.deadline = deadline
  }
}

public struct WeekPlanCounts: Equatable, Sendable {
  public let planned: Int
  public let completed: Int
  public let remaining: Int
  public let missed: Int
  public let moved: Int
  public let skipped: Int
  /// Days that predate enrollment; reported so they are never silently folded
  /// into the denominator.
  public let beforeEnrollment: Int

  public init(
    planned: Int = 0,
    completed: Int = 0,
    remaining: Int = 0,
    missed: Int = 0,
    moved: Int = 0,
    skipped: Int = 0,
    beforeEnrollment: Int = 0
  ) {
    self.planned = planned
    self.completed = completed
    self.remaining = remaining
    self.missed = missed
    self.moved = moved
    self.skipped = skipped
    self.beforeEnrollment = beforeEnrollment
  }

  /// Everything that counts against the plan.
  public var scheduled: Int { planned + completed + remaining + missed + moved + skipped }
}

public struct WeekPlanEvaluation: Equatable, Sendable {
  public let weekStart: Date
  public let planID: String
  public let enrollmentDate: Date
  public let now: Date
  public let days: [WeekPlanDayEvaluation]
  public let counts: WeekPlanCounts
  /// Remaining days whose session is owed today.
  public let atRisk: Int

  public init(
    weekStart: Date,
    planID: String,
    enrollmentDate: Date,
    now: Date,
    days: [WeekPlanDayEvaluation],
    counts: WeekPlanCounts,
    atRisk: Int
  ) {
    self.weekStart = weekStart
    self.planID = planID
    self.enrollmentDate = enrollmentDate
    self.now = now
    self.days = days
    self.counts = counts
    self.atRisk = atRisk
  }

  public func day(_ dayID: String) -> WeekPlanDayEvaluation? {
    days.first { $0.dayID == dayID }
  }

  /// Completed share of the work that has actually come due. Nil until at least
  /// one session has either been completed or missed — no invented percentages.
  public var adherence: Double? {
    let settled = counts.completed + counts.missed
    guard settled > 0 else { return nil }
    return Double(counts.completed) / Double(settled)
  }
}

public enum WeekPlanStatusPolicy {
  /// Resolves every day of `plan` against `now`.
  public static func evaluation(
    plan: WeekPlan,
    now: Date,
    calendar: Calendar
  ) -> WeekPlanEvaluation {
    let enrollmentStart = calendar.startOfDay(for: plan.enrollmentDate)
    var evaluations: [WeekPlanDayEvaluation] = []
    evaluations.reserveCapacity(plan.days.count)

    for day in plan.days {
      let start = calendar.startOfDay(for: day.date)
      // DST-safe: advance by a calendar day, then add the grace duration.
      let endOfDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
      let deadline = endOfDay.addingTimeInterval(plan.graceWindow)
      let beforeEnrollment = start < enrollmentStart

      let (state, reason) = resolve(
        day: day,
        start: start,
        deadline: deadline,
        beforeEnrollment: beforeEnrollment,
        now: now,
        calendar: calendar)

      evaluations.append(
        WeekPlanDayEvaluation(
          dayID: day.id,
          date: day.date,
          state: state,
          reason: reason,
          isCountedInPlan: !beforeEnrollment,
          plannedSessionID: day.plannedSessionID,
          deadline: deadline))
    }

    var planned = 0
    var completed = 0
    var remaining = 0
    var missed = 0
    var moved = 0
    var skipped = 0
    var beforeEnrollment = 0
    var atRisk = 0

    for evaluation in evaluations {
      guard evaluation.isCountedInPlan else {
        beforeEnrollment += 1
        continue
      }
      switch evaluation.state {
      case .planned: planned += 1
      case .completed: completed += 1
      case .remaining:
        remaining += 1
        if evaluation.reason == .dueToday { atRisk += 1 }
      case .missed: missed += 1
      case .moved: moved += 1
      case .skipped: skipped += 1
      }
    }

    return WeekPlanEvaluation(
      weekStart: plan.weekStart,
      planID: plan.id,
      enrollmentDate: plan.enrollmentDate,
      now: now,
      days: evaluations,
      counts: WeekPlanCounts(
        planned: planned,
        completed: completed,
        remaining: remaining,
        missed: missed,
        moved: moved,
        skipped: skipped,
        beforeEnrollment: beforeEnrollment),
      atRisk: atRisk)
  }

  /// The single decision this policy exists to make: is a day still owed, or is
  /// it genuinely gone? A day is only ever *missed* once `now` is past its
  /// deadline, and never when it predates enrollment.
  public static func resolve(
    day: WeekPlanDay,
    start: Date,
    deadline: Date,
    beforeEnrollment: Bool,
    now: Date,
    calendar: Calendar
  ) -> (WeekPlanDayState, WeekPlanDayStatusReason) {
    switch day.state {
    case .completed:
      return (.completed, .completed)
    case .skipped:
      return beforeEnrollment ? (.skipped, .beforeEnrollment) : (.skipped, .skippedByUser)
    case .moved:
      return beforeEnrollment ? (.skipped, .beforeEnrollment) : (.moved, .movedAway)
    case .planned, .remaining, .missed:
      if beforeEnrollment { return (.skipped, .beforeEnrollment) }
      if now < start { return (.remaining, .upcoming) }
      if now < deadline {
        let sameDay = calendar.isDate(now, inSameDayAs: start)
        return (.remaining, sameDay ? .dueToday : .withinGraceWindow)
      }
      return (.missed, .graceExpired)
    }
  }
}

// MARK: - Week plan validation

public enum WeekPlanValidationSeverity: String, Equatable, Sendable, CaseIterable {
  case warning
  case error
}

public enum WeekPlanValidationCode: String, Equatable, Sendable, CaseIterable {
  case emptyPlan
  case duplicateDayDate
  case missedBeforeEnrollment
  case missedWhileStillRemaining
  case stalePlannedAfterGrace
  case missingPlannedSession
  case completedWithoutSession
  case movedWithoutDestination
  case missingGymProfile
  case nonPositiveTimeBudget
}

public struct WeekPlanValidationIssue: Equatable, Identifiable, Sendable {
  public let id: String
  public let code: WeekPlanValidationCode
  public let severity: WeekPlanValidationSeverity
  public let message: String
  public let dayID: String?

  public init(
    id: String,
    code: WeekPlanValidationCode,
    severity: WeekPlanValidationSeverity,
    message: String,
    dayID: String? = nil
  ) {
    self.id = id
    self.code = code
    self.severity = severity
    self.message = message
    self.dayID = dayID
  }
}

public struct WeekPlanValidation: Equatable, Sendable {
  public let issues: [WeekPlanValidationIssue]

  public init(issues: [WeekPlanValidationIssue] = []) {
    self.issues = issues
  }

  public var errors: [WeekPlanValidationIssue] { issues.filter { $0.severity == .error } }
  public var warnings: [WeekPlanValidationIssue] { issues.filter { $0.severity == .warning } }
  public var isValid: Bool { errors.isEmpty }
  public func contains(_ code: WeekPlanValidationCode) -> Bool { issues.contains { $0.code == code } }
}

public enum WeekPlanValidationPolicy {
  public static func validate(
    plan: WeekPlan,
    now: Date,
    calendar: Calendar
  ) -> WeekPlanValidation {
    var issues: [WeekPlanValidationIssue] = []

    if plan.days.isEmpty {
      issues.append(
        WeekPlanValidationIssue(
          id: "\(plan.id)#empty",
          code: .emptyPlan,
          severity: .error,
          message: "A week plan with no days cannot be evaluated"))
    }

    let enrollmentStart = calendar.startOfDay(for: plan.enrollmentDate)
    var seenDays: [Date: String] = [:]

    for day in plan.days {
      let start = calendar.startOfDay(for: day.date)
      let endOfDay =
        calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
      let deadline = endOfDay.addingTimeInterval(plan.graceWindow)
      let beforeEnrollment = start < enrollmentStart

      if let existing = seenDays[start] {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#duplicate",
            code: .duplicateDayDate,
            severity: .error,
            message: "Two plan days share \(start) (also \(existing))",
            dayID: day.id))
      } else {
        seenDays[start] = day.id
      }

      // The distinction this whole type exists for: a day that still has time
      // left (or a grace window) is remaining, not missed.
      if day.state == .missed {
        if beforeEnrollment {
          issues.append(
            WeekPlanValidationIssue(
              id: "\(day.id)#missed-before-enrollment",
              code: .missedBeforeEnrollment,
              severity: .error,
              message: "Day predates enrollment and can never be missed",
              dayID: day.id))
        } else if now < deadline {
          issues.append(
            WeekPlanValidationIssue(
              id: "\(day.id)#missed-while-remaining",
              code: .missedWhileStillRemaining,
              severity: .error,
              message: "Day is marked missed while its deadline (\(deadline)) is still in the future — it is remaining",
              dayID: day.id))
        }
      }

      if !day.state.isSettled && !beforeEnrollment && now >= deadline {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#stale-planned",
            code: .stalePlannedAfterGrace,
            severity: .warning,
            message: "Day is still recorded as \(day.state.rawValue) after its grace window closed; evaluation resolves it to missed",
            dayID: day.id))
      }

      if day.plannedSessionID == nil {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#missing-session",
            code: .missingPlannedSession,
            severity: .error,
            message: "Day has no planned session identity",
            dayID: day.id))
      }

      if day.state == .completed && day.completedSessionID == nil {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#completed-without-session",
            code: .completedWithoutSession,
            severity: .error,
            message: "Day is completed but records no session identity",
            dayID: day.id))
      }

      if day.state == .moved && day.movedToDate == nil {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#moved-without-destination",
            code: .movedWithoutDestination,
            severity: .error,
            message: "Day is moved but records no destination",
            dayID: day.id))
      }

      if day.gymProfileID == nil {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#missing-gym",
            code: .missingGymProfile,
            severity: .warning,
            message: "Day has no gym profile, so equipment is unknown",
            dayID: day.id))
      }

      if day.timeBudgetMinutes <= 0 {
        issues.append(
          WeekPlanValidationIssue(
            id: "\(day.id)#time-budget",
            code: .nonPositiveTimeBudget,
            severity: .error,
            message: "Day has a non-positive time budget",
            dayID: day.id))
      }
    }

    return WeekPlanValidation(issues: issues)
  }
}

// MARK: - Week plan builder

public enum WeekPlanBuilder {
  /// Builds a dated week plan from program output, reusing `Program`,
  /// `PlannedDay`, `ProfileInput`, `TrainingConstraints` and `GymProfileConfig`.
  ///
  /// Days are placed on consecutive calendar days starting at `startingOn`; the
  /// caller decides the weekday offset by choosing `startingOn`.
  public static func plan(
    startingOn start: Date,
    plannedDays: [PlannedDay],
    profile: ProfileInput,
    constraints: TrainingConstraints,
    mode: WeekPlanMode? = nil,
    enrollmentDate: Date? = nil,
    timeZoneIdentifier: String? = nil,
    graceWindow: TimeInterval = WeekPlan.defaultGraceWindow,
    calendar base: Calendar = .current
  ) -> WeekPlan {
    var calendar = base
    let zoneIdentifier = timeZoneIdentifier ?? base.timeZone.identifier
    if let zone = TimeZone(identifier: zoneIdentifier) { calendar.timeZone = zone }

    let weekStart = calendar.startOfDay(for: start)
    let resolvedMode = mode ?? self.mode(profile: profile, constraints: constraints)
    let budget = constraints.sessionBudgetMinutes ?? profile.sessionLength.rawValue

    let days: [WeekPlanDay] = plannedDays.enumerated().map { index, planned in
      let date =
        calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
      return makeDay(
        planned,
        on: date,
        budget: budget,
        mode: resolvedMode,
        constraints: constraints,
        calendar: calendar)
    }

    return WeekPlan(
      id: "week-\(Int(weekStart.timeIntervalSince1970))",
      weekStart: weekStart,
      timeZoneIdentifier: zoneIdentifier,
      enrollmentDate: enrollmentDate ?? start,
      graceWindow: graceWindow,
      mode: resolvedMode,
      gymProfileID: constraints.activeGymProfileID,
      days: days)
  }

  /// Convenience over `Program.week(_:profile:)`.
  public static func plan(
    programWeek week: Int,
    profile: ProfileInput,
    constraints: TrainingConstraints,
    startingOn start: Date,
    mode: WeekPlanMode? = nil,
    enrollmentDate: Date? = nil,
    calendar: Calendar = .current
  ) -> WeekPlan {
    plan(
      startingOn: start,
      plannedDays: Program.week(week, profile: profile),
      profile: profile,
      constraints: constraints,
      mode: mode,
      enrollmentDate: enrollmentDate,
      calendar: calendar)
  }

  /// Rebuilds only the part of an accepted week that has not happened yet; recorded, past and routine-owned days and the acceptance stay exactly as they are.
  public static func revise(
    _ plan: WeekPlan,
    program: [PlannedDay],
    nextDayIndex: Int,
    profile: ProfileInput,
    constraints: TrainingConstraints,
    from: Date,
    now: Date,
    calendar base: Calendar = .current
  ) -> WeekPlan {
    let calendar = plan.resolvedCalendar(base)
    let fromStart = calendar.startOfDay(for: from)
    let nowStart = calendar.startOfDay(for: now)
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: plan.weekStart) ?? plan.weekStart

    // A confirmed routine owns its day's prescription: it is reviewed, never regenerated.
    let isKept: (WeekPlanDay) -> Bool = {
      $0.state.isSettled || $0.routineApplicationID != nil
        || calendar.startOfDay(for: $0.date) < fromStart
    }
    let kept = plan.days.filter(isKept)
    let droppedDates = plan.days
      .filter { !isKept($0) }
      .map { calendar.startOfDay(for: $0.date) }
      .sorted()
      .filter { $0 < weekEnd }

    let completed = kept.filter { $0.state == .completed }.count
    let keptOpen =
      kept
      .filter { $0.state == .planned && calendar.startOfDay(for: $0.date) >= nowStart }
      .count
    let remaining = max(0, program.count - completed - keptOpen)

    let keptDates = Set(kept.map { calendar.startOfDay(for: $0.date) })
    var candidates = droppedDates
    var cursor =
      droppedDates.last.map { calendar.date(byAdding: .day, value: 1, to: $0)! } ?? fromStart
    while cursor < weekEnd {
      candidates.append(cursor)
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    let freeDates = candidates.filter { !keptDates.contains($0) }

    let resolvedMode = mode(profile: profile, constraints: constraints)
    let budget = constraints.sessionBudgetMinutes ?? profile.sessionLength.rawValue
    let keptIDs = Set(kept.map(\.id))
    var added: [WeekPlanDay] = []
    for i in 0..<remaining {
      guard i < freeDates.count else { break }
      let index = ((nextDayIndex + i) % program.count + program.count) % program.count
      let day = makeDay(
        program[index],
        on: freeDates[i],
        budget: budget,
        mode: resolvedMode,
        constraints: constraints,
        calendar: calendar)
      if !keptIDs.contains(day.id) { added.append(day) }
    }

    var revised = WeekPlan(
      id: plan.id,
      weekStart: plan.weekStart,
      timeZoneIdentifier: plan.timeZoneIdentifier,
      enrollmentDate: plan.enrollmentDate,
      graceWindow: plan.graceWindow,
      mode: resolvedMode,
      gymProfileID: constraints.activeGymProfileID,
      days: (kept + added).sorted { $0.date < $1.date },
      version: plan.version)
    revised.acceptanceID = plan.acceptanceID
    return revised
  }

  private static func makeDay(
    _ planned: PlannedDay,
    on date: Date,
    budget: Int,
    mode: WeekPlanMode,
    constraints: TrainingConstraints,
    calendar: Calendar
  ) -> WeekPlanDay {
    WeekPlanDay(
      id: "\(planned.id)@\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))",
      date: date,
      plannedSessionID: planned.id,
      sessionName: planned.name,
      exerciseIDs: planned.exercises.map(\.exercise.id),
      plannedSetCount: planned.exercises.reduce(0) { $0 + $1.sets },
      gymProfileID: constraints.activeGymProfileID,
      gymProfileName: constraints.activeGymProfile?.name,
      timeBudgetMinutes: budget,
      mode: mode)
  }

  public static func mode(
    profile: ProfileInput,
    constraints: TrainingConstraints
  ) -> WeekPlanMode {
    if constraints.travelMode { return .travel }
    if constraints.minimumEffectiveWorkout { return .minimumEffective }
    if profile.recoveryReduced { return .reduced }
    return .standard
  }
}

/// Advice to show when the lifter changes plan settings; it never blocks the change.
public enum PlanChangeAdvice: Equatable, Sendable {
  case early(sessions: Int)
  case repeated(changes: Int)

  public static let windowDays = 14

  /// `changesInWindow` counts plan-setting changes in the last `windowDays` days, this one included.
  public static func advice(blockSessions: Int, changesInWindow: Int) -> PlanChangeAdvice? {
    if changesInWindow >= 3 { return .repeated(changes: changesInWindow) }
    if (1...3).contains(blockSessions) { return .early(sessions: blockSessions) }
    return nil
  }
}

/// The four plan settings a lifter changes from Settings → Training or through the Coach.
public struct PlanSettings: Equatable, Sendable {
  public var goal: Goal
  public var split: SplitStyle
  public var daysPerWeek: Int
  public var sessionMinutes: Int

  public init(goal: Goal, split: SplitStyle, daysPerWeek: Int, sessionMinutes: Int) {
    self.goal = goal
    self.split = split
    self.daysPerWeek = daysPerWeek
    self.sessionMinutes = sessionMinutes
  }

  /// One English line per changed field; the Coach packet and the advice counter read these, so they are never localized.
  public static func changes(from old: PlanSettings, to new: PlanSettings) -> [String] {
    var lines: [String] = []
    if old.daysPerWeek != new.daysPerWeek {
      lines.append("days a week \(old.daysPerWeek) → \(new.daysPerWeek)")
    }
    if old.sessionMinutes != new.sessionMinutes {
      lines.append("session \(old.sessionMinutes) → \(new.sessionMinutes) min")
    }
    if old.goal != new.goal {
      lines.append("goal \(old.goal.englishLabel) → \(new.goal.englishLabel)")
    }
    if old.split != new.split {
      lines.append("split \(old.split.englishLabel) → \(new.split.englishLabel)")
    }
    return lines
  }
}

extension Goal {
  /// Locale-free label for plan-change lines; `name` is localized and must not be used there.
  var englishLabel: String {
    switch self {
    case .hypertrophy: return "Hypertrophy"
    case .strength: return "Strength"
    case .both: return "Both"
    }
  }
}

extension SplitStyle {
  /// Locale-free label for plan-change lines; `name` is localized and must not be used there.
  var englishLabel: String {
    switch self {
    case .auto: return "Auto"
    case .fullBody: return "Full body"
    case .upperLower: return "Upper/Lower"
    case .pushPullLegs: return "Push/Pull/Legs"
    case .pushPull: return "Push/Pull"
    case .arnold: return "Arnold"
    }
  }
}

/// A plan-settings change proposed by the Coach; untrusted values are checked here, never trimmed into a different proposal.
public struct PlanAdjustment: Equatable, Sendable {
  public let daysPerWeek: Int?
  public let sessionMinutes: Int?
  public let goal: Goal?
  public let split: SplitStyle?

  public static let supportedDays: ClosedRange<Int> = 2...6

  /// Nil when nothing is given or any given value is unsupported (days outside 2...6, minutes not a SessionLength, unknown goal or split raw value).
  public init?(daysPerWeek: Int?, sessionMinutes: Int?, goal: String?, split: String?) {
    guard daysPerWeek != nil || sessionMinutes != nil || goal != nil || split != nil else { return nil }
    if let daysPerWeek, !Self.supportedDays.contains(daysPerWeek) { return nil }
    if let sessionMinutes, SessionLength(rawValue: sessionMinutes) == nil { return nil }
    if let goal, Goal(rawValue: goal) == nil { return nil }
    if let split, SplitStyle(rawValue: split) == nil { return nil }
    self.daysPerWeek = daysPerWeek
    self.sessionMinutes = sessionMinutes
    self.goal = goal.flatMap(Goal.init(rawValue:))
    self.split = split.flatMap(SplitStyle.init(rawValue:))
  }

  private init(daysPerWeek: Int?, sessionMinutes: Int?, goal: Goal?, split: SplitStyle?) {
    self.daysPerWeek = daysPerWeek
    self.sessionMinutes = sessionMinutes
    self.goal = goal
    self.split = split
  }

  /// Only the fields that differ from `current`; nil when nothing would change.
  public func changing(_ current: PlanSettings) -> PlanAdjustment? {
    let days = daysPerWeek == current.daysPerWeek ? nil : daysPerWeek
    let minutes = sessionMinutes == current.sessionMinutes ? nil : sessionMinutes
    let newGoal = goal == current.goal ? nil : goal
    let newSplit = split == current.split ? nil : split
    guard days != nil || minutes != nil || newGoal != nil || newSplit != nil else { return nil }
    return PlanAdjustment(daysPerWeek: days, sessionMinutes: minutes, goal: newGoal, split: newSplit)
  }

  public func applied(to settings: PlanSettings) -> PlanSettings {
    PlanSettings(
      goal: goal ?? settings.goal,
      split: split ?? settings.split,
      daysPerWeek: daysPerWeek ?? settings.daysPerWeek,
      sessionMinutes: sessionMinutes ?? settings.sessionMinutes)
  }

  /// The program input with this adjustment: daysPerWeek, sessionLength, goal and split.
  public func applied(to input: ProfileInput) -> ProfileInput {
    var revised = input
    if let daysPerWeek { revised.daysPerWeek = daysPerWeek }
    if let sessionMinutes { revised.sessionLength = SessionLength(rawValue: sessionMinutes)! }
    if let goal { revised.goal = goal }
    if let split { revised.split = split }
    return revised
  }

  /// Locale-free identity for previews and recommendation ids, e.g. ["adjustPlan", "days:3", "minutes:45", "goal:-", "split:-"].
  public var digestComponents: [String] {
    [
      "adjustPlan",
      "days:\(daysPerWeek.map(String.init) ?? "-")",
      "minutes:\(sessionMinutes.map(String.init) ?? "-")",
      "goal:\(goal?.rawValue ?? "-")",
      "split:\(split?.rawValue ?? "-")",
    ]
  }
}

// MARK: - Goals

public enum GoalStatus: String, Codable, Equatable, Sendable, CaseIterable {
  case notStarted
  case onTrack
  case atRisk
  case achieved
  case expired
  case abandoned

  public var name: String {
    switch self {
    case .notStarted: return "Not started"
    case .onTrack: return "On track"
    case .atRisk: return "At risk"
    case .achieved: return "Achieved"
    case .expired: return "Expired"
    case .abandoned: return "Abandoned"
    }
  }
}

public enum GoalUnit: String, Codable, Equatable, Sendable, CaseIterable {
  case kilograms
  case pounds
  case repetitions
  case sessions
  case percent
  case weeks
  case count

  public var name: String {
    switch self {
    case .kilograms: return "kg"
    case .pounds: return "lb"
    case .repetitions: return "reps"
    case .sessions: return "sessions"
    case .percent: return "%"
    case .weeks: return "weeks"
    case .count: return "count"
    }
  }
}

public enum GoalComparator: String, Codable, Equatable, Sendable, CaseIterable {
  case atLeast
  case atMost

  public func isSatisfied(_ value: Double, _ threshold: Double) -> Bool {
    switch self {
    case .atLeast: return value >= threshold
    case .atMost: return value <= threshold
    }
  }
}

public enum GoalTargetKind: String, Codable, Equatable, Sendable, CaseIterable {
  case benchmark
  case skill
  case adherence
}

public enum BenchmarkMetric: String, Codable, Equatable, Sendable, CaseIterable {
  case estimatedOneRepMax
  case topSetLoad
  case reps
  case volume
}

public enum AdherenceMetric: String, Codable, Equatable, Sendable, CaseIterable {
  case completedSessions
  case sessionsPerWeek
  case completionRate
}

/// A measurable performance target on one exercise.
public struct BenchmarkTarget: Codable, Equatable, Sendable {
  public var exerciseID: String
  public var metric: BenchmarkMetric
  public var baseline: Double
  public var target: Double
  public var unit: GoalUnit
  public var comparator: GoalComparator

  public init(
    exerciseID: String,
    metric: BenchmarkMetric = .estimatedOneRepMax,
    baseline: Double,
    target: Double,
    unit: GoalUnit = .kilograms,
    comparator: GoalComparator = .atLeast
  ) {
    self.exerciseID = exerciseID
    self.metric = metric
    self.baseline = baseline
    self.target = target
    self.unit = unit
    self.comparator = comparator
  }
}

/// A capability target: it needs repeated, attributable proof, not one number.
public struct SkillTarget: Codable, Equatable, Sendable {
  public var skillID: String
  public var skillName: String
  public var baseline: Double
  public var target: Double
  public var unit: GoalUnit
  /// When set, only evidence of this kind counts (e.g. a coach sign-off).
  public var requiredEvidenceKind: GoalEvidenceKind?

  public init(
    skillID: String,
    skillName: String,
    baseline: Double = 0,
    target: Double,
    unit: GoalUnit = .repetitions,
    requiredEvidenceKind: GoalEvidenceKind? = nil
  ) {
    self.skillID = skillID
    self.skillName = skillName
    self.baseline = baseline
    self.target = target
    self.unit = unit
    self.requiredEvidenceKind = requiredEvidenceKind
  }
}

/// A consistency target. Counts sessions; never claims success from one record.
public struct AdherenceTarget: Codable, Equatable, Sendable {
  public var metric: AdherenceMetric
  public var baseline: Double
  public var target: Double
  public var unit: GoalUnit
  public var windowWeeks: Int

  public init(
    metric: AdherenceMetric = .completedSessions,
    baseline: Double = 0,
    target: Double,
    unit: GoalUnit = .sessions,
    windowWeeks: Int = 4
  ) {
    self.metric = metric
    self.baseline = baseline
    self.target = target
    self.unit = unit
    self.windowWeeks = max(1, windowWeeks)
  }
}

/// Typed so a skill goal and a load goal cannot be compared or coerced.
public enum GoalTarget: Codable, Equatable, Sendable {
  case benchmark(BenchmarkTarget)
  case skill(SkillTarget)
  case adherence(AdherenceTarget)

  public var kind: GoalTargetKind {
    switch self {
    case .benchmark: return .benchmark
    case .skill: return .skill
    case .adherence: return .adherence
    }
  }

  public var baseline: Double {
    switch self {
    case .benchmark(let t): return t.baseline
    case .skill(let t): return t.baseline
    case .adherence(let t): return t.baseline
    }
  }

  public var target: Double {
    switch self {
    case .benchmark(let t): return t.target
    case .skill(let t): return t.target
    case .adherence(let t): return t.target
    }
  }

  public var unit: GoalUnit {
    switch self {
    case .benchmark(let t): return t.unit
    case .skill(let t): return t.unit
    case .adherence(let t): return t.unit
    }
  }

  /// Skill and adherence targets are counted from zero toward a target; only a
  /// benchmark can meaningfully be "at most".
  public var comparator: GoalComparator {
    switch self {
    case .benchmark(let t): return t.comparator
    case .skill, .adherence: return .atLeast
    }
  }
}

public enum GoalEvidenceKind: String, Codable, Equatable, Sendable, CaseIterable {
  /// Produced by the app from a recorded session.
  case measured
  /// Typed or spoken by the lifter, unverified.
  case manual
  case coachSignOff
  case video
  case imported
}

public struct GoalEvidence: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var goalID: String
  public var kind: GoalEvidenceKind
  /// The exercise the evidence is about, when it is about one.
  public var exerciseID: String?
  /// Never trust this blindly — an unverified record cannot satisfy a goal.
  public var verified: Bool
  public var value: Double?
  public var occurredAt: Date
  public var note: String?

  public init(
    id: String = UUID().uuidString,
    goalID: String,
    kind: GoalEvidenceKind = .measured,
    exerciseID: String? = nil,
    verified: Bool = true,
    value: Double? = nil,
    occurredAt: Date,
    note: String? = nil
  ) {
    self.id = id
    self.goalID = goalID
    self.kind = kind
    self.exerciseID = exerciseID
    self.verified = verified
    self.value = value
    self.occurredAt = occurredAt
    self.note = note
  }
}

public enum GoalEvidencePolicy {
  /// How much verified evidence a target needs before it may be judged at all.
  public static func minimumVerifiedEvidence(for kind: GoalTargetKind) -> Int {
    switch kind {
    case .benchmark: return 1
    case .skill: return 2
    case .adherence: return 1
    }
  }

  /// Whether an evidence record can count toward a target: it must be verified,
  /// already happened, and belong to the same exercise or evidence kind.
  public static func counts(_ evidence: GoalEvidence, toward target: GoalTarget) -> Bool {
    guard evidence.verified else { return false }
    switch target {
    case .benchmark(let benchmark):
      return evidence.exerciseID == benchmark.exerciseID
    case .skill(let skill):
      guard let required = skill.requiredEvidenceKind else { return true }
      return evidence.kind == required
    case .adherence:
      return true
    }
  }
}

public struct GoalMilestone: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let fraction: Double
  public let value: Double
  public let label: String

  public init(id: String, fraction: Double, value: Double, label: String) {
    self.id = id
    self.fraction = fraction
    self.value = value
    self.label = label
  }
}

/// Versioned goal record. `version` is the schema version; records decoded
/// without one are migrated from the flat legacy shape (see `init(from:)`).
public struct GoalRecord: Codable, Equatable, Identifiable, Sendable {
  public static let currentSchemaVersion = 1
  /// Fractional rungs of the baseline → target climb.
  public static let defaultMilestoneFractions: [Double] = [0.25, 0.5, 0.75, 1.0]

  public var id: String
  public var version: Int
  /// The training goal this record serves — the existing `Goal` enum, not a copy.
  public var goal: Goal
  public var title: String
  public var target: GoalTarget
  public var deadline: Date?
  public var createdAt: Date
  public var status: GoalStatus
  /// Evidence count as last persisted. Recomputed and checked by validation.
  public var evidenceCount: Int
  public var note: String?

  public init(
    id: String = UUID().uuidString,
    goal: Goal,
    title: String,
    target: GoalTarget,
    deadline: Date? = nil,
    createdAt: Date = .now,
    status: GoalStatus = .notStarted,
    evidenceCount: Int = 0,
    note: String? = nil,
    version: Int = GoalRecord.currentSchemaVersion
  ) {
    self.id = id
    self.version = version
    self.goal = goal
    self.title = title
    self.target = target
    self.deadline = deadline
    self.createdAt = createdAt
    self.status = status
    self.evidenceCount = evidenceCount
    self.note = note
  }

  // Derived from the typed target so unit/baseline/target can never drift apart.
  public var kind: GoalTargetKind { target.kind }
  public var unit: GoalUnit { target.unit }
  public var baseline: Double { target.baseline }
  public var targetValue: Double { target.target }
  public var comparator: GoalComparator { target.comparator }
  public var minimumVerifiedEvidence: Int {
    GoalEvidencePolicy.minimumVerifiedEvidence(for: target.kind)
  }

  private enum CodingKeys: String, CodingKey {
    case id, version, goal, title, target, deadline, createdAt, status, evidenceCount, note
    // Legacy (schema < 1) flat shape.
    case targetValue, exerciseID, unit
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // A record without a version predates versioning; treat it as version 0.
    _ = try container.decodeIfPresent(Int.self, forKey: .version)

    let goal = try container.decode(Goal.self, forKey: .goal)
    let title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    self.version = Self.currentSchemaVersion
    self.goal = goal
    self.title = title
    self.id =
      try container.decodeIfPresent(String.self, forKey: .id)
      ?? "legacy-\(goal.rawValue)-\(title)"
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    self.deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
    self.status = try container.decodeIfPresent(GoalStatus.self, forKey: .status) ?? .notStarted
    self.note = try container.decodeIfPresent(String.self, forKey: .note)

    if let target = try container.decodeIfPresent(GoalTarget.self, forKey: .target) {
      self.target = target
    } else if let legacyTarget = try container.decodeIfPresent(Double.self, forKey: .targetValue) {
      // Legacy records carry no baseline and no metric; record that honestly
      // rather than inventing one.
      let unit = try container.decodeIfPresent(GoalUnit.self, forKey: .unit) ?? .kilograms
      self.target = .benchmark(
        BenchmarkTarget(
          exerciseID: try container.decodeIfPresent(String.self, forKey: .exerciseID) ?? "",
          metric: .estimatedOneRepMax,
          baseline: 0,
          target: legacyTarget,
          unit: unit,
          comparator: .atLeast))
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .target,
        in: container,
        debugDescription: "GoalRecord requires a typed target or a legacy targetValue")
    }

    self.evidenceCount = try container.decodeIfPresent(Int.self, forKey: .evidenceCount) ?? 0
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.currentSchemaVersion, forKey: .version)
    try container.encode(id, forKey: .id)
    try container.encode(goal, forKey: .goal)
    try container.encode(title, forKey: .title)
    try container.encode(target, forKey: .target)
    try container.encodeIfPresent(deadline, forKey: .deadline)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(status, forKey: .status)
    try container.encode(evidenceCount, forKey: .evidenceCount)
    try container.encodeIfPresent(note, forKey: .note)
  }
}

public struct GoalProgress: Equatable, Sendable {
  public let goalID: String
  public let status: GoalStatus
  /// Nil when evidence is missing or insufficient — never a stand-in number.
  public let current: Double?
  public let baseline: Double
  public let target: Double
  public let unit: GoalUnit
  public let fraction: Double?
  public let milestones: [GoalMilestone]
  public let reachedMilestoneIDs: [String]
  public let nextMilestone: GoalMilestone?
  public let evidenceCount: Int
  public let verifiedEvidenceCount: Int
  /// True once `minimumVerifiedEvidence` is met.
  public let isConclusive: Bool
  public let reason: String?

  public init(
    goalID: String,
    status: GoalStatus,
    current: Double?,
    baseline: Double,
    target: Double,
    unit: GoalUnit,
    fraction: Double?,
    milestones: [GoalMilestone],
    reachedMilestoneIDs: [String],
    nextMilestone: GoalMilestone?,
    evidenceCount: Int,
    verifiedEvidenceCount: Int,
    isConclusive: Bool,
    reason: String?
  ) {
    self.goalID = goalID
    self.status = status
    self.current = current
    self.baseline = baseline
    self.target = target
    self.unit = unit
    self.fraction = fraction
    self.milestones = milestones
    self.reachedMilestoneIDs = reachedMilestoneIDs
    self.nextMilestone = nextMilestone
    self.evidenceCount = evidenceCount
    self.verifiedEvidenceCount = verifiedEvidenceCount
    self.isConclusive = isConclusive
    self.reason = reason
  }

  public func hasReached(_ milestone: GoalMilestone) -> Bool {
    reachedMilestoneIDs.contains(milestone.id)
  }
}

public enum GoalProgressPolicy {
  public static func progress(
    goal: GoalRecord,
    evidence: [GoalEvidence],
    now: Date = .now,
    milestoneFractions: [Double] = GoalRecord.defaultMilestoneFractions
  ) -> GoalProgress {
    let milestones = milestones(for: goal, fractions: milestoneFractions)

    // Evidence must be for this goal, already happened, and admissible for the
    // target kind.
    let counted = evidence
      .filter { $0.goalID == goal.id }
      .filter { $0.occurredAt <= now }
      .filter { GoalEvidencePolicy.counts($0, toward: goal.target) }
    let verified = counted.filter(\.verified)

    let minimum = goal.minimumVerifiedEvidence
    let conclusive = verified.count >= minimum

    if goal.status == .abandoned {
      return GoalProgress(
        goalID: goal.id,
        status: .abandoned,
        current: nil,
        baseline: goal.baseline,
        target: goal.targetValue,
        unit: goal.unit,
        fraction: nil,
        milestones: milestones,
        reachedMilestoneIDs: [],
        nextMilestone: milestones.first,
        evidenceCount: counted.count,
        verifiedEvidenceCount: verified.count,
        isConclusive: conclusive,
        reason: "Goal was abandoned")
    }

    guard conclusive else {
      let past = goal.deadline.map { now > $0 } ?? false
      return GoalProgress(
        goalID: goal.id,
        status: past ? .expired : .notStarted,
        current: nil,
        baseline: goal.baseline,
        target: goal.targetValue,
        unit: goal.unit,
        fraction: nil,
        milestones: milestones,
        reachedMilestoneIDs: [],
        nextMilestone: milestones.first,
        evidenceCount: counted.count,
        verifiedEvidenceCount: verified.count,
        isConclusive: false,
        reason: past
          ? "Deadline passed without enough verified evidence"
          : "Needs \(minimum) verified evidence record\(minimum == 1 ? "" : "s"), has \(verified.count)")
    }

    guard let current = aggregate(verified, target: goal.target) else {
      let past = goal.deadline.map { now > $0 } ?? false
      return GoalProgress(
        goalID: goal.id,
        status: past ? .expired : .notStarted,
        current: nil,
        baseline: goal.baseline,
        target: goal.targetValue,
        unit: goal.unit,
        fraction: nil,
        milestones: milestones,
        reachedMilestoneIDs: [],
        nextMilestone: milestones.first,
        evidenceCount: counted.count,
        verifiedEvidenceCount: verified.count,
        isConclusive: false,
        reason: "Verified evidence carries no measurable value")
    }

    let reached = milestones.filter { goal.comparator.isSatisfied(current, $0.value) }
    let next = milestones.first { !reached.contains($0) }
    let fraction = self.fraction(current: current, goal: goal)
    let hitTarget = goal.comparator.isSatisfied(current, goal.targetValue)

    if hitTarget {
      return GoalProgress(
        goalID: goal.id,
        status: .achieved,
        current: current,
        baseline: goal.baseline,
        target: goal.targetValue,
        unit: goal.unit,
        fraction: fraction,
        milestones: milestones,
        reachedMilestoneIDs: reached.map(\.id),
        nextMilestone: nil,
        evidenceCount: counted.count,
        verifiedEvidenceCount: verified.count,
        isConclusive: true,
        reason: "Target reached on \(verified.count) verified record\(verified.count == 1 ? "" : "s")")
    }

    if let deadline = goal.deadline, now > deadline {
      return GoalProgress(
        goalID: goal.id,
        status: .expired,
        current: current,
        baseline: goal.baseline,
        target: goal.targetValue,
        unit: goal.unit,
        fraction: fraction,
        milestones: milestones,
        reachedMilestoneIDs: reached.map(\.id),
        nextMilestone: next,
        evidenceCount: counted.count,
        verifiedEvidenceCount: verified.count,
        isConclusive: true,
        reason: "Deadline passed at \(format(current)) \(goal.unit.name) of \(format(goal.targetValue)) \(goal.unit.name)")
    }

    let status = pace(goal: goal, fraction: fraction ?? 0, now: now)
    return GoalProgress(
      goalID: goal.id,
      status: status,
      current: current,
      baseline: goal.baseline,
      target: goal.targetValue,
      unit: goal.unit,
      fraction: fraction,
      milestones: milestones,
      reachedMilestoneIDs: reached.map(\.id),
      nextMilestone: next,
      evidenceCount: counted.count,
      verifiedEvidenceCount: verified.count,
      isConclusive: true,
      reason: next.map { "Next milestone \($0.label) at \(format($0.value)) \(goal.unit.name)" })
  }

  /// Deterministic ladder between baseline and target, independent of evidence.
  public static func milestones(
    for goal: GoalRecord,
    fractions: [Double] = GoalRecord.defaultMilestoneFractions
  ) -> [GoalMilestone] {
    let baseline = goal.baseline
    let target = goal.targetValue
    return fractions.map { fraction in
      let value = baseline + (target - baseline) * fraction
      return GoalMilestone(
        id: "\(goal.id)#\(fraction)",
        fraction: fraction,
        value: value,
        label: "\(Int((fraction * 100).rounded()))%")
    }
  }

  // MARK: internals

  static func aggregate(_ verified: [GoalEvidence], target: GoalTarget) -> Double? {
    switch target {
    case .benchmark(let benchmark):
      let values = verified.compactMap(\.value)
      guard !values.isEmpty else { return nil }
      switch benchmark.comparator {
      case .atLeast: return values.max()
      case .atMost: return values.min()
      }
    case .skill, .adherence:
      // Counted, not measured: each verified record is one unit of proof.
      return Double(verified.count)
    }
  }

  static func fraction(current: Double, goal: GoalRecord) -> Double? {
    let span = goal.targetValue - goal.baseline
    guard span != 0 else {
      return goal.comparator.isSatisfied(current, goal.targetValue) ? 1 : 0
    }
    let raw = (current - goal.baseline) / span
    return min(max(raw, 0), 1)
  }

  static func pace(goal: GoalRecord, fraction: Double, now: Date) -> GoalStatus {
    guard let deadline = goal.deadline, deadline > goal.createdAt else { return .onTrack }
    let total = deadline.timeIntervalSince(goal.createdAt)
    let elapsed = min(max(now.timeIntervalSince(goal.createdAt), 0), total)
    let expected = elapsed / total
    return fraction + 0.05 >= expected ? .onTrack : .atRisk
  }

  static func format(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
  }
}

// MARK: - Goal validation

public enum GoalValidationCode: String, Equatable, Sendable, CaseIterable {
  case emptyIdentifier
  case emptyTitle
  case deadlineBeforeCreation
  case achievedWithoutSufficientEvidence
  case achievedBelowTarget
  case evidenceCountMismatch
  case targetEqualsBaseline
  case unsupportedVersion
}

public struct GoalValidationIssue: Equatable, Identifiable, Sendable {
  public let id: String
  public let code: GoalValidationCode
  public let severity: WeekPlanValidationSeverity
  public let message: String

  public init(
    id: String,
    code: GoalValidationCode,
    severity: WeekPlanValidationSeverity,
    message: String
  ) {
    self.id = id
    self.code = code
    self.severity = severity
    self.message = message
  }
}

public struct GoalValidation: Equatable, Sendable {
  public let issues: [GoalValidationIssue]

  public init(issues: [GoalValidationIssue] = []) {
    self.issues = issues
  }

  public var errors: [GoalValidationIssue] { issues.filter { $0.severity == .error } }
  public var warnings: [GoalValidationIssue] { issues.filter { $0.severity == .warning } }
  public var isValid: Bool { errors.isEmpty }
  public func contains(_ code: GoalValidationCode) -> Bool { issues.contains { $0.code == code } }
}

public enum GoalValidationPolicy {
  /// The guardrail: a record that *claims* success must be backed by verified
  /// evidence that actually reaches the target.
  public static func validate(
    goal: GoalRecord,
    evidence: [GoalEvidence],
    now: Date = .now
  ) -> GoalValidation {
    var issues: [GoalValidationIssue] = []

    if goal.id.isEmpty {
      issues.append(
        GoalValidationIssue(
          id: "goal#empty-id",
          code: .emptyIdentifier,
          severity: .error,
          message: "Goal has no stable identifier"))
    }
    if goal.title.isEmpty {
      issues.append(
        GoalValidationIssue(
          id: "\(goal.id)#empty-title",
          code: .emptyTitle,
          severity: .warning,
          message: "Goal has no title"))
    }
    if let deadline = goal.deadline, deadline <= goal.createdAt {
      issues.append(
        GoalValidationIssue(
          id: "\(goal.id)#deadline",
          code: .deadlineBeforeCreation,
          severity: .error,
          message: "Deadline is not after the creation date"))
    }
    if goal.version > GoalRecord.currentSchemaVersion {
      issues.append(
        GoalValidationIssue(
          id: "\(goal.id)#version",
          code: .unsupportedVersion,
          severity: .warning,
          message: "Goal was written by a newer schema version (\(goal.version))"))
    }
    if goal.baseline == goal.targetValue {
      issues.append(
        GoalValidationIssue(
          id: "\(goal.id)#flat-target",
          code: .targetEqualsBaseline,
          severity: .warning,
          message: "Target equals baseline, so progress is not measurable"))
    }

    let progress = GoalProgressPolicy.progress(goal: goal, evidence: evidence, now: now)
    if goal.status == .achieved {
      if !progress.isConclusive {
        issues.append(
          GoalValidationIssue(
            id: "\(goal.id)#achieved-without-evidence",
            code: .achievedWithoutSufficientEvidence,
            severity: .error,
            message: "Goal claims achieved with \(progress.verifiedEvidenceCount) verified evidence record(s); \(goal.minimumVerifiedEvidence) required"))
      } else if let current = progress.current,
        !goal.comparator.isSatisfied(current, goal.targetValue)
      {
        issues.append(
          GoalValidationIssue(
            id: "\(goal.id)#achieved-below-target",
            code: .achievedBelowTarget,
            severity: .error,
            message: "Goal claims achieved but verified evidence is \(GoalProgressPolicy.format(current)) \(goal.unit.name), target is \(GoalProgressPolicy.format(goal.targetValue)) \(goal.unit.name)"))
      }
    }

    if goal.evidenceCount != progress.evidenceCount {
      issues.append(
        GoalValidationIssue(
          id: "\(goal.id)#evidence-count",
          code: .evidenceCountMismatch,
          severity: .warning,
          message: "Recorded evidence count \(goal.evidenceCount) does not match \(progress.evidenceCount) admissible record(s)"))
    }

    return GoalValidation(issues: issues)
  }
}
