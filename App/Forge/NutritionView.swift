import ForgeCore
import SwiftData
import SwiftUI

/// Fuel: eating enough to grow? Today's two rings and one-tap logging, then the 7-day
/// averages and the meals of the day. Opened from Today and from Progress.
struct NutritionView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var profiles: [UserProfile]
  @Query(sort: \NutritionProfile.updated, order: .reverse) private var nutritionProfiles:
    [NutritionProfile]
  @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

  @State private var showSetup = false
  @State private var addMeal: Meal?
  @State private var quickAdd = false
  @State private var showGuidance = false
  @State private var confirmRepeatYesterday = false
  @State private var repeatingYesterday = false
  @State private var undoEntries: [FoodEntry] = []
  @State private var pendingDeleteEntry: FoodEntry?
  @State private var pendingPhase: Phase?
  @AppStorage("nutrition.dailyOverrideDate") private var dailyOverrideDate = ""
  @AppStorage("nutrition.dailyOverrideType") private var dailyOverrideType = ""
  @AppStorage("nutrition.lastRepeatDate") private var lastRepeatDate = ""
  /// The day key the lifter marked as fully logged. Empty means "not stated yet".
  @AppStorage("nutrition.captureCompleteDay") private var captureCompleteDay = ""

  private var profile: UserProfile? { profiles.first }
  private var nutrition: NutritionProfile? { nutritionProfiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var todayEntries: [FoodEntry] {
    entries.filter { !$0.tombstoned && Calendar.current.isDateInToday($0.date) }
  }

  private var consumed: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
    todayEntries.reduce((0, 0, 0, 0)) { acc, e in
      (acc.0 + e.kcal, acc.1 + e.proteinG, acc.2 + e.carbsG, acc.3 + e.fatG)
    }
  }

  private var currentWeightKg: Double {
    measurements.first { ($0.weightKg ?? 0) > 0 }?.weightKg ?? profile?.bodyweightKg ?? 75
  }

  private var weeklySets: Int {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    return
      sessions
      .filter { $0.completed && $0.date >= cutoff }
      .flatMap(\.sets)
      .filter { $0.rpe >= 6 }
      .count
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ProgressLargeTitle(title: "Fuel", subtitle: dayBasisLine, art: "art-bowl")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
        if nutrition == nil {
          heroCard
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        } else {
          todaySection
          LogBand()
          weekSection
          LogBand()
          mealsSection
          LogBand()
          quickLogSection
            .padding(.bottom, 24)
        }
      }
    }
    .background(Theme.page)
    .progressTitleNavigation("Fuel")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Edit targets") { showSetup = true }
          Button("Quick-add favorites") { quickAdd = true }
          Menu(String(localized: "Phase", bundle: L10n.bundle)) {
            ForEach(Phase.allCases, id: \.self) { phase in
              if nutrition?.phase == phase.rawValue {
                Label(phase.name, systemImage: "checkmark")
              } else {
                Button(phase.name) { pendingPhase = phase }
              }
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More options")
      }
    }
    .sheet(isPresented: $showSetup) {
      NutritionSetupSheet(
        existing: nutrition,
        weightKg: currentWeightKg,
        weeklySets: weeklySets,
        usesLb: usesLb)
    }
    .sheet(item: $addMeal) { meal in
      FoodSearchView(meal: meal)
    }
    .sheet(isPresented: $quickAdd) {
      FoodSearchView(meal: .snack, favoritesOnly: true)
    }
    .sheet(isPresented: $showGuidance) {
      NutritionGuidanceSheet(recommendation: dailyRecommendation)
    }
    .confirmationDialog(
      "Repeat yesterday's meals?",
      isPresented: $confirmRepeatYesterday,
      titleVisibility: .visible
    ) {
      Button("Add \(yesterdayEntries.count) items") { repeatYesterday() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Only items not already logged today will be added.")
    }
    .confirmationDialog(
      Text(
        String(localized: "Switch to \(pendingPhase?.name ?? "")?", bundle: L10n.bundle)),
      isPresented: Binding(
        get: { pendingPhase != nil },
        set: { if !$0 { pendingPhase = nil } }),
      titleVisibility: .visible
    ) {
      Button(String(localized: "Switch", bundle: L10n.bundle)) {
        if let phase = pendingPhase { setPhase(phase) }
        pendingPhase = nil
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) { pendingPhase = nil }
    } message: {
      Text("Your calorie and protein targets are recalculated.")
    }
    .confirmationDialog(
      "Delete this entry?",
      isPresented: Binding(
        get: { pendingDeleteEntry != nil },
        set: { if !$0 { pendingDeleteEntry = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete entry", role: .destructive) {
        if let entry = pendingDeleteEntry {
          SyncEngine.shared.deleteEverywhere(
            type: "nutrition", wireID: entry.remoteID.isEmpty ? "" : "food-\(entry.remoteID)")
          modelContext.delete(entry)
        }
        pendingDeleteEntry = nil
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This can't be undone.")
    }
    .overlay(alignment: .bottom) {
      if !undoEntries.isEmpty {
        HStack {
          Text("Added \(undoEntries.count) item\(L10n.pluralSuffix(undoEntries.count))")
            .forgeBodyStrong()
          Spacer()
          Button(action: undoLastAdd) {
            Text("Undo")
              .forgeLabel()
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
        }
        .padding(14)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).stroke(Theme.ring)
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 12)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: undoEntries.count)
  }

  private var baseTargets: MacroTargets {
    MacroTargets(
      kcal: nutrition?.kcal ?? 0,
      proteinG: nutrition?.proteinG ?? 0,
      carbsG: nutrition?.carbsG ?? 0,
      fatG: nutrition?.fatG ?? 0)
  }

  /// Why today's numbers are what they are. Read from the plan and the log, never assumed.
  private enum IntakeBasis { case deload, completedTraining, plannedTraining, rest }

  /// The session already recorded today, if the lifter trained.
  private var todaySession: WorkoutSession? {
    sessions.first { $0.completed && Calendar.current.isDateInToday($0.date) }
  }

  /// Today's slot on the week plan, when a plan exists at all.
  private var todayPlanDay: WeekPlanDay? {
    profile?.weekPlan?.day(on: .now)
  }

  private var intakeBasis: IntakeBasis {
    guard let profile else { return .rest }
    if profile.currentWeek(sessions: sessions) == Mesocycle.deloadWeek { return .deload }
    if todaySession != nil { return .completedTraining }
    if let day = todayPlanDay,
      day.state == .planned || day.state == .remaining || day.state == .moved
    {
      return .plannedTraining
    }
    // No accepted plan: the block still owes sessions this week, which is the same basis the
    // base target was built on. With a plan, its own days decide — a day it leaves open is a
    // rest day, not a gap the generated block fills in.
    if todayPlanDay == nil, profile.weekPlan == nil,
      WeekStrip.completed(sessions) < max(profile.daysPerWeek, 1)
    {
      return .plannedTraining
    }
    return .rest
  }

  private var nutritionDayType: NutritionDayType {
    switch intakeBasis {
    case .deload: return .deload
    case .completedTraining, .plannedTraining: return .training
    case .rest: return .rest
    }
  }

  private var dailyRecommendation: NutritionDailyRecommendation {
    NutritionTargetAdvisor.recommend(base: baseTargets, dayType: nutritionDayType)
  }

  private var localDayKey: String {
    Date.now.formatted(.iso8601.year().month().day())
  }

  private var recommendationApplied: Bool {
    dailyOverrideDate == localDayKey && dailyOverrideType == nutritionDayType.rawValue
  }

  private var canRepeatYesterday: Bool {
    !yesterdayEntries.isEmpty && lastRepeatDate != localDayKey && !repeatingYesterday
  }
  private var effectiveTargets: MacroTargets {
    recommendationApplied ? dailyRecommendation.recommended : baseTargets
  }

  /// Food logging is per day and opt-in: until the lifter says the day is fully logged, the
  /// totals are a floor, not a measurement.
  private var captureComplete: Bool { captureCompleteDay == localDayKey }

  private var basisName: String {
    switch intakeBasis {
    case .deload: return String(localized: "deload day", bundle: L10n.bundle)
    case .completedTraining: return String(localized: "training day, session logged", bundle: L10n.bundle)
    case .plannedTraining: return String(localized: "planned training day", bundle: L10n.bundle)
    case .rest: return String(localized: "rest day", bundle: L10n.bundle)
    }
  }

  /// "Build muscle · training day" under the page title.
  private var dayBasisLine: String? {
    guard let profile else { return nil }
    let goal = Goal(rawValue: profile.goal)?.name ?? ""
    return String(localized: "\(goal) · \(basisName)", bundle: L10n.bundle)
  }

  private var recentEntries: [FoodEntry] {
    let cutoff = Date.now.addingTimeInterval(-14 * 86400)
    var seen = Set<String>()
    return entries.filter {
      !$0.tombstoned && !Calendar.current.isDateInToday($0.date) && $0.date >= cutoff
    }
    .filter { entry in
      let key = "\(entry.itemID)|\(Int(entry.grams.rounded()))"
      return seen.insert(key).inserted
    }
    .prefix(4).map { $0 }
  }

  private var yesterdayEntries: [FoodEntry] {
    entries.filter { !$0.tombstoned && Calendar.current.isDateInYesterday($0.date) }
  }

  private var dayTypeColor: Color {
    switch nutritionDayType {
    case .training: return Theme.metricTime
    case .rest: return Theme.metricSets
    case .deload: return Theme.plateGold
    }
  }

  private var dayTypeSymbol: String {
    switch nutritionDayType {
    case .training: return "figure.strengthtraining.traditional"
    case .rest: return "bed.double.fill"
    case .deload: return "arrow.down.right.circle.fill"
    }
  }

  // MARK: today

  private var todaySection: some View {
    let targets = effectiveTargets
    return VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        ringStat(
          value: Fmt.grouped(consumed.kcal),
          unit: nil,
          of: String(localized: "of \(Fmt.grouped(Double(targets.kcal))) kcal", bundle: L10n.bundle),
          progress: targets.kcal > 0 ? consumed.kcal / Double(targets.kcal) : 0,
          colors: Theme.gradMove,
          dot: Theme.metricLoad,
          label: String(localized: "Calories", bundle: L10n.bundle))
        ringStat(
          value: Fmt.grouped(consumed.protein),
          unit: "g",
          of: String(localized: "of \(Fmt.grouped(Double(targets.proteinG))) g", bundle: L10n.bundle),
          progress: targets.proteinG > 0 ? consumed.protein / Double(targets.proteinG) : 0,
          colors: Theme.gradBrand,
          dot: Theme.accent,
          label: String(localized: "Protein", bundle: L10n.bundle))
      }
      .frame(minHeight: 176)
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 20)
      .accessibilityElement(children: .contain)

      Text(verbatim: partialDayLine)
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)

      Button {
        addMeal = .current
      } label: {
        Label(String(localized: "Log food", bundle: L10n.bundle), systemImage: "plus")
          .frame(maxWidth: .infinity, minHeight: 56)
      }
      .buttonStyle(PillButtonStyle())
      .accessibilityIdentifier("fuel.logFood")
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 20)

      guidanceRow
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 12)
      captureStatusRow
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
    }
  }

  /// One ring with the value in its center and a dot-labeled name below (mock .rg1).
  private func ringStat(value: String, unit: String?, of: String, progress: Double, colors: [Color], dot: Color, label: String) -> some View {
    VStack(spacing: 10) {
      ZStack {
        V3GradientRing(progress: progress, colors: colors, lineWidth: 14)
          .frame(minWidth: 136, minHeight: 136)
        VStack(spacing: 0) {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: value)
              .forge(28, .bold)
              .tracking(-0.5)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
            if let unit {
              Text(verbatim: unit)
                .forge(15, .medium)
                .foregroundStyle(Theme.textSecondary)
            }
          }
          Text(verbatim: of)
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      HStack(spacing: 6) {
        Circle().fill(dot).frame(width: 8, height: 8)
        Text(verbatim: label).forge(15, .semibold).foregroundStyle(Theme.text)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(value) \(of)")
  }

  /// "Breakfast logged at 7:30. 2,110 kcal and 112 g protein to go."
  private var partialDayLine: String {
    guard !todayEntries.isEmpty else {
      return String(localized: "Nothing logged yet today.", bundle: L10n.bundle)
    }
    let firstLogged = Meal.allCases.first { meal in
      todayEntries.contains { $0.meal == meal.rawValue }
    }
    let firstTime = firstLogged.flatMap { meal in
      todayEntries.filter { $0.meal == meal.rawValue }.map(\.date).min()
    }
    guard let meal = firstLogged, let first = firstTime else {
      return String(localized: "Nothing logged yet today.", bundle: L10n.bundle)
    }
    let targets = effectiveTargets
    let kcalLeft = max(0, Double(targets.kcal) - consumed.kcal)
    let proteinLeft = max(0, Double(targets.proteinG) - consumed.protein)
    let time = first.formatted(.dateTime.hour().minute().locale(L10n.locale))
    return String(
      localized: "\(meal.name) logged at \(time). \(Fmt.grouped(kcalLeft)) kcal and \(Fmt.grouped(proteinLeft)) g protein to go.",
      bundle: L10n.bundle)
  }

  /// The day-type basis row: what today's target is and why, with the day's override.
  private var guidanceRow: some View {
    let targets = effectiveTargets
    let adjustment = dailyRecommendation.carbAdjustmentG
    return HStack(spacing: 12) {
      Image(systemName: dayTypeSymbol)
        .scaledSystemFont(14, weight: .semibold)
        .foregroundStyle(dayTypeColor)
        .frame(width: 32, height: 32)
        .background(Circle().fill(dayTypeColor.opacity(0.12)))
      Button {
        showGuidance = true
      } label: {
        VStack(alignment: .leading, spacing: 1) {
          Text(dailyRecommendation.dayType.name).forgeBodyStrong()
          Text(
            String(
              localized: "\(adjustment >= 0 ? "+" : "")\(adjustment) g carbs · \(Fmt.grouped(Double(targets.kcal))) kcal target",
              bundle: L10n.bundle)
          )
          .forgeCaption().monospacedDigit()
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("fuel.guidance")
      Spacer(minLength: 8)
      Button {
        if recommendationApplied {
          dailyOverrideDate = ""
          dailyOverrideType = ""
        } else {
          dailyOverrideDate = localDayKey
          dailyOverrideType = nutritionDayType.rawValue
        }
        Analytics.track(
          "nutrition_daily_guidance",
          ["type": nutritionDayType.rawValue, "applied": recommendationApplied ? "0" : "1"])
      } label: {
        Text(
          recommendationApplied
            ? String(localized: "Return to base", bundle: L10n.bundle)
            : String(localized: "Use for today", bundle: L10n.bundle)
        )
        .forge(13, .semibold)
        .foregroundStyle(Theme.accentText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityIdentifier("fuel.dailyOverride")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
  }

  /// Nothing is inferred: an unlogged day is "incomplete", not zero, until the lifter says
  /// the day's food is fully recorded.
  private var captureStatusRow: some View {
    HStack(spacing: 8) {
      Image(systemName: captureComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .scaledSystemFont(14, weight: .semibold)
        .foregroundStyle(captureComplete ? Theme.positive : Theme.metricEnergy)
      Text(
        captureComplete
          ? String(localized: "Everything you ate today is logged", bundle: L10n.bundle)
          : String(localized: "Intake may be incomplete", bundle: L10n.bundle)
      )
      .forgeCaption()
      Spacer(minLength: 0)
      Button {
        captureCompleteDay = captureComplete ? "" : localDayKey
      } label: {
        Text(
          captureComplete
            ? String(localized: "Reopen", bundle: L10n.bundle)
            : String(localized: "Mark complete", bundle: L10n.bundle)
        )
        .forge(12, .semibold)
        .foregroundStyle(Theme.accentText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityLabel(
        captureComplete
          ? String(localized: "Reopen today's food log", bundle: L10n.bundle)
          : String(localized: "Mark today's food log complete", bundle: L10n.bundle))
      .accessibilityIdentifier("fuel.capture")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
  }

  // MARK: last 7 days

  /// One entry per calendar day; `nil` values are days with no log (unknown, not zero).
  private var weekDays: [(day: Date, kcal: Double?, protein: Double?)] {
    let cal = Calendar.current
    return (0..<7).reversed().compactMap { offset in
      guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now))
      else { return nil }
      let dayEntries = entries.filter { !$0.tombstoned && cal.isDate($0.date, inSameDayAs: day) }
      return dayEntries.isEmpty
        ? (day, nil, nil)
        : (
          day,
          dayEntries.reduce(0.0) { $0 + $1.kcal },
          dayEntries.reduce(0.0) { $0 + $1.proteinG }
        )
    }
  }

  private var weekSection: some View {
    let kcalTarget = Double(effectiveTargets.kcal)
    let proteinTarget = Double(effectiveTargets.proteinG)
    let kcalDays = weekDays.compactMap(\.kcal)
    let proteinDays = weekDays.compactMap(\.protein)
    let avgKcal = kcalDays.isEmpty ? nil : kcalDays.reduce(0, +) / Double(kcalDays.count)
    let avgProtein = proteinDays.isEmpty ? nil : proteinDays.reduce(0, +) / Double(proteinDays.count)
    return VStack(spacing: 0) {
      V3SectionHeader(
        "Last 7 days",
        trailing: LogV3.spanText(
          from: Date.now.addingTimeInterval(-6 * 86400), to: Date.now))
      VStack(spacing: 18) {
        if let avgKcal {
          averageBar(
            name: String(localized: "Calories", bundle: L10n.bundle),
            dot: Theme.metricLoad,
            value: Fmt.grouped(avgKcal),
            unit: String(localized: "kcal a day", bundle: L10n.bundle),
            fraction: kcalTarget > 0 ? avgKcal / kcalTarget : 0,
            colors: Theme.gradMove,
            detail: averageDetail(avg: avgKcal, target: kcalTarget, unit: "kcal"))
        }
        if let avgProtein {
          averageBar(
            name: String(localized: "Protein", bundle: L10n.bundle),
            dot: Theme.accent,
            value: Fmt.grouped(avgProtein),
            unit: String(localized: "g a day", bundle: L10n.bundle),
            fraction: proteinTarget > 0 ? avgProtein / proteinTarget : 0,
            colors: Theme.gradBrand,
            detail: averageDetail(avg: avgProtein, target: proteinTarget, unit: "g"))
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)

      proteinByDay(proteinTarget: proteinTarget)
        .padding(.bottom, 20)
      if let verdict = verdictLine(avgKcal: avgKcal, kcalTarget: kcalTarget, avgProtein: avgProtein, proteinTarget: proteinTarget) {
        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: verdict.headline)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          Text(verbatim: verdict.detail)
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func averageDetail(avg: Double, target: Double, unit: String) -> String {
    guard target > 0 else { return "" }
    let pct = Int((avg / target * 100).rounded())
    let distance = target - avg
    if abs(distance) < 0.5 * unitStep(unit) {
      return String(localized: "\(pct)% of target", bundle: L10n.bundle)
    }
    let word = distance > 0 ? "under" : "over"
    return String(
      localized: "\(pct)% of target · \(Fmt.grouped(abs(distance).rounded())) \(unit) \(word)",
      bundle: L10n.bundle)
  }

  /// Rough rounding step per unit, so "170 kcal under" shows but "0 g under" does not.
  private func unitStep(_ unit: String) -> Double { unit == "kcal" ? 10 : 1 }

  private func averageBar(name: String, dot: Color, value: String, unit: String, fraction: Double, colors: [Color], detail: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Circle().fill(dot).frame(width: 8, height: 8)
        Text(verbatim: name).forge(17, .semibold).foregroundStyle(Theme.text)
        Spacer(minLength: 8)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(verbatim: value).forge(17, .semibold).monospacedDigit().foregroundStyle(Theme.text)
          Text(verbatim: unit).forge(14, .regular).foregroundStyle(Theme.textSecondary)
        }
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule()
            .fill(.mark(colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: geo.size.width * min(1, max(0, fraction)))
        }
      }
      .frame(height: 8)
      Text(verbatim: detail)
        .forge(14, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  private func proteinByDay(proteinTarget: Double) -> some View {
    let days = weekDays.map { day in
      V3WeekBars.Day(label: BodyV3.dayLabel(day.day), value: day.protein, isToday: Calendar.current.isDateInToday(day.day))
    }
    let logged = weekDays.compactMap { day in day.protein.map { (day.day, $0) } }
    let best = logged.max { $0.1 < $1.1 }
    return VStack(spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Protein by day").forge(17, .semibold).foregroundStyle(Theme.text)
        Spacer(minLength: 8)
        if let best {
          Text(
            String(
              localized: "Best \(Fmt.grouped(best.1)) g, \(BodyV3.dayLabel(best.0))",
              bundle: L10n.bundle))
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, Theme.margin)
      V3WeekBars(
        days: days,
        maxV: max(proteinTarget, logged.map(\.1).max() ?? 1) * 1.15,
        colors: Theme.gradBrand,
        barHeight: 108,
        target: proteinTarget > 0 ? proteinTarget : nil,
        targetLabel: proteinTarget > 0
          ? String(localized: "\(Fmt.grouped(proteinTarget)) g target", bundle: L10n.bundle)
          : nil
      )
      .padding(.horizontal, Theme.margin)
    }
  }

  /// "Protein is the gap", only when protein misses its target by a larger share than kcal.
  private func verdictLine(avgKcal: Double?, kcalTarget: Double, avgProtein: Double?, proteinTarget: Double) -> (headline: String, detail: String)? {
    guard let avgKcal, let avgProtein, kcalTarget > 0, proteinTarget > 0 else { return nil }
    let kcalMiss = 1 - avgKcal / kcalTarget
    let proteinMiss = 1 - avgProtein / proteinTarget
    guard proteinMiss > kcalMiss, proteinMiss > 0.05 else { return nil }
    let short = proteinTarget - avgProtein
    return (
      String(localized: "Protein is the gap", bundle: L10n.bundle),
      String(
        localized: "About \(Fmt.grouped(short.rounded())) g short a day.", bundle: L10n.bundle)
    )
  }

  // MARK: meals

  private var mealsSection: some View {
    let split = Double(nutrition?.proteinG ?? 0) / 4
    return VStack(spacing: 0) {
      V3SectionHeader(
        "Meals today",
        trailing: (nutrition?.proteinG ?? 0) > 0
          ? String(localized: "Aim for \(Fmt.grouped(split)) g protein a meal", bundle: L10n.bundle)
          : nil)
      ForEach(Array(Meal.allCases.enumerated()), id: \.element) { index, meal in
        if index > 0 {
          Divider()
            .padding(.leading, Theme.margin + 44)
            .padding(.trailing, Theme.margin)
        }
        mealRow(meal, split: split)
          .padding(.horizontal, Theme.margin)
        ForEach(todayEntries.filter { $0.meal == meal.rawValue }) { entry in
          entryRow(entry)
            .padding(.leading, 44)
            .padding(.trailing, Theme.margin)
        }
      }
    }
    .padding(.bottom, 20)
  }

  private func mealRow(_ meal: Meal, split: Double) -> some View {
    let mealEntries = todayEntries.filter { $0.meal == meal.rawValue }
    let kcal = mealEntries.reduce(0.0) { $0 + $1.kcal }
    let proteinG = mealEntries.reduce(0.0) { $0 + $1.proteinG }
    return V3DetailRow(icon: meal.symbol, title: meal.name, subtitle: mealSub(meal, kcal: kcal, proteinG: proteinG)) {
      HStack(spacing: 10) {
        if split > 0 && proteinG >= split {
          Image(systemName: "checkmark.circle.fill")
            .scaledSystemFont(16)
            .foregroundStyle(Theme.positive)
            .accessibilityLabel(String(localized: "Protein goal reached", bundle: L10n.bundle))
        }
        Button {
          addMeal = meal
        } label: {
          Text(String(localized: "Add", bundle: L10n.bundle))
            .forge(13, .semibold)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Capsule().fill(Theme.innerSurface))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(String(localized: "Add to \(meal.name)", bundle: L10n.bundle))
      }
    }
  }

  /// "7:30 · 540 kcal · 38 g protein", or "Not logged yet".
  private func mealSub(_ meal: Meal, kcal: Double, proteinG: Double) -> String? {
    let mealEntries = todayEntries.filter { $0.meal == meal.rawValue }
    guard !mealEntries.isEmpty else {
      return String(localized: "Not logged yet", bundle: L10n.bundle)
    }
    let time = mealEntries.map(\.date).min()?.formatted(.dateTime.hour().minute().locale(L10n.locale)) ?? ""
    return String(
      localized: "\(time) · \(Fmt.grouped(kcal)) kcal · \(Fmt.grouped(proteinG)) g protein",
      bundle: L10n.bundle)
  }

  private func entryRow(_ entry: FoodEntry) -> some View {
    SwipeDeleteRow(
      onDelete: { pendingDeleteEntry = entry }, surface: Theme.page
    ) {
      HStack(spacing: 10) {
        Text(entry.name).forge(15, .regular).foregroundStyle(Theme.text)
        Text(Fmt.grouped(entry.grams) + " g").forgeCaption().monospacedDigit()
        Spacer(minLength: 8)
        Text(Fmt.grouped(entry.kcal) + " kcal").forge(14, .regular).monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.vertical, 5)
      .contentShape(Rectangle())
    }
  }

  // MARK: quick log

  @ViewBuilder private var quickLogSection: some View {
    if !yesterdayEntries.isEmpty || !recentEntries.isEmpty {
      VStack(spacing: 0) {
        HStack {
          Text("Quick log").forge(20, .bold).tracking(-0.3).foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          if canRepeatYesterday {
            Button {
              confirmRepeatYesterday = true
            } label: {
              Text("Repeat yesterday")
                .forge(15, .semibold)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
          } else if !yesterdayEntries.isEmpty && lastRepeatDate == localDayKey {
            Label("Repeated today", systemImage: "checkmark.circle.fill")
              .forgeCaption()
              .foregroundStyle(Theme.positive)
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 10)
        if !recentEntries.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(recentEntries) { entry in
                Button {
                  addRecent(entry)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    HStack {
                      Image(systemName: Meal(rawValue: entry.meal)?.symbol ?? "fork.knife")
                        .foregroundStyle(Theme.accent)
                      Spacer()
                      Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                    Text(entry.name).forgeBodyStrong().lineLimit(1)
                    Text(
                      "\(Fmt.grouped(entry.kcal)) kcal · \(Fmt.grouped(entry.proteinG)) g protein"
                    )
                    .forgeCaption().monospacedDigit().lineLimit(1)
                  }
                  .frame(width: 178, alignment: .leading)
                  .padding(12)
                  .background(
                    RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
                      Theme.innerSurface))
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(
                  String(
                    localized: "Add \(entry.name), \(Fmt.grouped(entry.kcal)) calories",
                    bundle: L10n.bundle))
              }
            }
            .padding(.horizontal, Theme.margin)
          }
        }
      }
    }
  }

  // MARK: setup hero

  private var heroCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-plan", height: 140)
      Text("Fuel the block").forgeTitle()
      Text(
        "Calories, protein, carbs and fat tuned to your phase and training volume — set once, then just log."
      ).forgeLabel()
        .multilineTextAlignment(.center)
      Button("Set targets") { showSetup = true }
        .buttonStyle(PillButtonStyle())
    }
    .frame(maxWidth: .infinity)
    .card()
  }

  // MARK: actions

  private func setPhase(_ phase: Phase) {
    guard let nutrition, nutrition.phase != phase.rawValue else { return }
    nutrition.phase = phase.rawValue
    Macros.recompute(profile: nutrition, weightKg: currentWeightKg, weeklySets: weeklySets)
    Analytics.track("nutrition_phase", ["phase": phase.rawValue])
  }

  private func addRecent(_ entry: FoodEntry) {
    let added = clone(entry)
    undoEntries = added.map { [$0] } ?? []
  }

  private func repeatYesterday() {
    guard canRepeatYesterday else { return }
    repeatingYesterday = true
    let operationDate = localDayKey
    var added: [FoodEntry] = []
    for entry in yesterdayEntries {
      if let copy = clone(entry) { added.append(copy) }
    }
    if added.count == yesterdayEntries.count {
      undoEntries = added
      lastRepeatDate = operationDate
      Analytics.track("nutrition_repeat_yesterday", ["items": "\(added.count)"])
    } else {
      added.forEach(modelContext.delete)
      try? modelContext.save()
    }
    repeatingYesterday = false
  }

  private func clone(_ entry: FoodEntry) -> FoodEntry? {
    guard let meal = Meal(rawValue: entry.meal) else { return nil }
    let copy = FoodEntry(
      date: .now,
      meal: meal,
      itemID: entry.itemID,
      name: entry.name,
      grams: entry.grams,
      kcal: entry.kcal,
      proteinG: entry.proteinG,
      carbsG: entry.carbsG,
      fatG: entry.fatG)
    modelContext.insert(copy)
    try? modelContext.save()
    return copy
  }

  private func undoLastAdd() {
    SyncEngine.shared.deleteEverywhere(
      undoEntries.map { ("nutrition", $0.remoteID.isEmpty ? "" : "food-\($0.remoteID)") })
    undoEntries.forEach(modelContext.delete)
    undoEntries = []
    lastRepeatDate = ""
    try? modelContext.save()
  }
}

private struct NutritionGuidanceSheet: View {
  @Environment(\.dismiss) private var dismiss
  let recommendation: NutritionDailyRecommendation

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text(recommendation.dayType.name).forgeTitle()
        Text(recommendation.explanation).forgeBody()
        VStack(spacing: 10) {
          guidanceRow(
            "Calories", base: "\(recommendation.base.kcal) kcal",
            recommended: "\(recommendation.recommended.kcal) kcal")
          guidanceRow(
            "Protein", base: "\(recommendation.base.proteinG) g",
            recommended: "\(recommendation.recommended.proteinG) g")
          guidanceRow(
            "Carbs", base: "\(recommendation.base.carbsG) g",
            recommended: "\(recommendation.recommended.carbsG) g")
          guidanceRow(
            "Fat", base: "\(recommendation.base.fatG) g",
            recommended: "\(recommendation.recommended.fatG) g")
        }
        .card()
        Text("This is a daily training recommendation, not a permanent target change.")
          .forgeCaption()
        Spacer()
      }
      .padding(Theme.margin)
      .background(Theme.page)
      .navigationTitle("Daily fuel guidance")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }

  private func guidanceRow(_ label: String, base: String, recommended: String) -> some View {
    HStack {
      Text(label).forgeBodyStrong()
      Spacer()
      Text(base).forgeCaption().strikethrough(base != recommended)
      Image(systemName: "arrow.forward").forgeCaption()
      Text(recommended).forgeLabel().monospacedDigit()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(localized: "\(label): was \(base), now \(recommended)", bundle: L10n.bundle))
  }
}
