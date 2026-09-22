import Charts
import ForgeCore
import SwiftData
import SwiftUI

struct NutritionView: View {
  @Environment(\.modelContext) private var modelContext
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
      VStack(spacing: Theme.groupGap) {
        if nutrition == nil {
          heroCard
        } else {
          todayCard
          mealShortcutsCard
          mealsCard
          weightCard
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Fuel")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Edit targets") { showSetup = true }
          Button("Quick-add favorites") { quickAdd = true }
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
    .overlay(alignment: .bottom) {
      if !undoEntries.isEmpty {
        HStack {
          Text("Added \(undoEntries.count) item\(L10n.pluralSuffix(undoEntries.count))")
            .forgeBodyStrong()
          Spacer()
          Button("Undo", action: undoLastAdd).forgeLabel()
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.2), value: undoEntries.count)
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

  /// One honest line: which day these numbers are for, and on what basis they were set.
  private var targetBasisLabel: String {
    let date = Date.now.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let basis: String
    switch intakeBasis {
    case .deload:
      basis = String(localized: "deload day", bundle: L10n.bundle)
    case .completedTraining:
      basis = String(localized: "training day, session logged", bundle: L10n.bundle)
    case .plannedTraining:
      basis = String(localized: "planned training day", bundle: L10n.bundle)
    case .rest:
      basis = String(localized: "rest day", bundle: L10n.bundle)
    }
    let source =
      recommendationApplied
      ? String(localized: "Override for \(date)", bundle: L10n.bundle)
      : String(localized: "Target for \(date)", bundle: L10n.bundle)
    return "\(source) · \(basis)"
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

  private var todayCard: some View {
    let targets = effectiveTargets
    let kcalTarget = Double(targets.kcal)
    let adjustment = dailyRecommendation.carbAdjustmentG
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 1) {
          Text("Today").forgeSection()
          Text(targetBasisLabel).forgeCaption()
        }
        Spacer()
        Menu {
          ForEach(Phase.allCases, id: \.self) { phase in
            Button(phase.name) { setPhase(phase) }
          }
        } label: {
          HStack(spacing: 4) {
            Text(Phase(rawValue: nutrition?.phase ?? "")?.name ?? "")
            Image(systemName: "chevron.down")
          }
          .font(.forge(12, .semibold))
          .foregroundStyle(Theme.onAccent)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Capsule().fill(Theme.accent))
        }
      }
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(Fmt.grouped(max(0, kcalTarget - consumed.kcal)))
            .foregroundStyle(Theme.metricEnergy)
            .forgeNumber()
          Text(
            captureComplete
              ? String(localized: "kcal left", bundle: L10n.bundle)
              : String(localized: "kcal left so far", bundle: L10n.bundle)
          )
          .forgeCaption()
        }
        Spacer()
        Text("\(Fmt.grouped(consumed.kcal)) / \(Fmt.grouped(kcalTarget))")
          .forgeLabel()
          .monospacedDigit()
      }
      HStack(spacing: 10) {
        Image(systemName: dayTypeSymbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(dayTypeColor)
          .frame(width: 32, height: 32)
          .background(Circle().fill(dayTypeColor.opacity(0.12)))
        Button {
          showGuidance = true
        } label: {
          VStack(alignment: .leading, spacing: 1) {
            Text(dailyRecommendation.dayType.name).forgeBodyStrong()
            Text(
              "\(adjustment >= 0 ? "+" : "")\(adjustment) g carbs · \(Fmt.grouped(Double(dailyRecommendation.recommended.kcal))) kcal target"
            )
            .forgeCaption().monospacedDigit()
          }
        }
        .buttonStyle(RowPressStyle())
        Spacer()
        Button(recommendationApplied ? "Return to base" : "Use for today") {
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
        }
        .forge(12, .semibold)
        .foregroundStyle(Theme.accent)
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
      )
      macroRow(
        label: String(localized: "protein", bundle: L10n.bundle), value: consumed.protein,
        target: Double(targets.proteinG), tint: Theme.accentValue)
      macroRow(
        label: String(localized: "carbs", bundle: L10n.bundle), value: consumed.carbs,
        target: Double(targets.carbsG), tint: Theme.metricTime)
      macroRow(
        label: String(localized: "fat", bundle: L10n.bundle), value: consumed.fat,
        target: Double(targets.fatG), tint: Theme.metricEffort)
      captureStatusRow
    }
    .card()
  }

  /// Nothing is inferred: an unlogged day is "incomplete", not zero, until the lifter says
  /// the day's food is fully recorded.
  private var captureStatusRow: some View {
    HStack(spacing: 8) {
      Image(systemName: captureComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(captureComplete ? Theme.positive : Theme.metricEnergy)
      Text(
        captureComplete
          ? String(localized: "Everything you ate today is logged", bundle: L10n.bundle)
          : String(localized: "Intake may be incomplete", bundle: L10n.bundle)
      )
      .forgeCaption()
      Spacer(minLength: 0)
      Button(
        captureComplete
          ? String(localized: "Reopen", bundle: L10n.bundle)
          : String(localized: "Mark complete", bundle: L10n.bundle)
      ) {
        captureCompleteDay = captureComplete ? "" : localDayKey
      }
      .forge(12, .semibold)
      .foregroundStyle(Theme.accent)
      .accessibilityLabel(
        captureComplete
          ? String(localized: "Reopen today's food log", bundle: L10n.bundle)
          : String(localized: "Mark today's food log complete", bundle: L10n.bundle))
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
  }

  private func macroRow(label: String, value: Double, target: Double, tint: Color) -> some View {
    HStack {
      Text(label).forgeBodyStrong().frame(width: 72, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule()
            .fill(tint)
            .frame(width: geo.size.width * min(1, target > 0 ? value / target : 0))
        }
      }
      .frame(height: 10)
      Text("\(Fmt.grouped(value)) / \(Fmt.grouped(target)) g")
        .forgeLabel()
        .monospacedDigit()
        .frame(width: 104, alignment: .trailing)
    }
  }

  private func setPhase(_ phase: Phase) {
    guard let nutrition, nutrition.phase != phase.rawValue else { return }
    nutrition.phase = phase.rawValue
    Macros.recompute(profile: nutrition, weightKg: currentWeightKg, weeklySets: weeklySets)
    Analytics.track("nutrition_phase", ["phase": phase.rawValue])
  }

  @ViewBuilder
  private var mealShortcutsCard: some View {
    if !yesterdayEntries.isEmpty || !recentEntries.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Quick log").forgeSection()
          Spacer()
          if canRepeatYesterday {
            Button("Repeat yesterday") { confirmRepeatYesterday = true }
              .forge(12, .semibold)
              .foregroundStyle(Theme.accent)
          } else if !yesterdayEntries.isEmpty && lastRepeatDate == localDayKey {
            Label("Repeated today", systemImage: "checkmark.circle.fill")
              .forgeCaption()
              .foregroundStyle(Theme.positive)
          }
        }
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
                .accessibilityLabel("Add \(entry.name), \(Fmt.grouped(entry.kcal)) calories")
              }
            }
          }
        }
      }
      .card()
    }
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

  private func entrySignature(_ entry: FoodEntry) -> String {
    "\(entry.meal)|\(entry.itemID)|\(Int(entry.grams.rounded()))"
  }

  private func undoLastAdd() {
    undoEntries.forEach(modelContext.delete)
    undoEntries = []
    lastRepeatDate = ""
    try? modelContext.save()
  }
  private var mealsCard: some View {
    let split = Double(nutrition?.proteinG ?? 0) / 4
    return VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Meals").forgeSection()
        Spacer()
        if (nutrition?.proteinG ?? 0) > 0 {
          Text("protein target \(Fmt.grouped(split)) g per meal").forgeCaption()
        }
      }
      .padding(.bottom, 10)
      ForEach(Array(Meal.allCases.enumerated()), id: \.element) { index, meal in
        let mealEntries = todayEntries.filter { $0.meal == meal.rawValue }
        let kcal = mealEntries.reduce(0.0) { $0 + $1.kcal }
        let proteinG = mealEntries.reduce(0.0) { $0 + $1.proteinG }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            Image(systemName: meal.symbol)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Theme.accent)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(meal.name).forgeBodyStrong()
              if kcal > 0 {
                Text("\(Fmt.grouped(kcal)) kcal · \(Fmt.grouped(proteinG)) g protein")
                  .forgeCaption()
                  .monospacedDigit()
              }
            }
            Spacer()
            if split > 0 && proteinG >= split {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.positive)
            }
            Button {
              addMeal = meal
            } label: {
              Text("Add")
                .forge(12, .semibold)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accentTint))
            }
            .buttonStyle(RowPressStyle())
          }
          .frame(minHeight: 32)
          ForEach(mealEntries) { entry in
            SwipeDeleteRow {
              modelContext.delete(entry)
            } content: {
              HStack(spacing: 10) {
                Text(entry.name).forgeBodyStrong()
                Text(Fmt.grouped(entry.grams) + " g").forgeCaption().monospacedDigit()
                Spacer()
                Text(Fmt.grouped(entry.kcal) + " kcal").forgeLabel().monospacedDigit()
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
                  Theme.innerSurface)
              )
              .contentShape(Rectangle())
            }
            .padding(.leading, 34)
          }
        }
        if index < Meal.allCases.count - 1 {
          Divider().overlay(Theme.ring).padding(.vertical, 6)
        }
      }
    }
    .card()
  }

  // MARK: weight vs intake

  private var weightByDay: [Date: Double] {
    var map: [Date: Double] = [:]
    let cal = Calendar.current
    for m in measurements where (m.weightKg ?? 0) > 0 {
      let day = cal.startOfDay(for: m.date)
      if map[day] == nil { map[day] = m.weightKg }
    }
    return map
  }

  private struct DayDatum: Identifiable {
    let date: Date
    let kcal: Double
    let weight: Double?
    /// False for a day nothing was logged on: an unlogged day is unknown, not zero.
    let hasLog: Bool
    var id: Date { date }
  }

  private var dayData: [DayDatum] {
    let cal = Calendar.current
    let weights = weightByDay
    let kcalByDay = Dictionary(grouping: entries, by: { cal.startOfDay(for: $0.date) })
      .mapValues { $0.reduce(0.0) { $0 + $1.kcal } }
    return (0..<28).compactMap { offset in
      guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else {
        return nil
      }
      let window = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: day) }
      let rolling = window.compactMap { weights[$0] }
      return DayDatum(
        date: day,
        kcal: kcalByDay[day] ?? 0,
        weight: rolling.isEmpty ? nil : rolling.reduce(0, +) / Double(rolling.count),
        hasLog: kcalByDay[day] != nil)
    }
  }

  private var weightWindow: [Double] {
    weightByDay
      .filter { $0.key > Date.now.addingTimeInterval(-28 * 86400) }
      .map(\.value)
  }

  private var lineScale: (min: Double, max: Double) {
    let values = weightWindow
    guard let lo = values.min(), let hi = values.max(), hi > lo else { return (0, 1) }
    return (lo, hi)
  }

  private var kcalMax: Double {
    max(Double(nutrition?.kcal ?? 0), (dayData.map(\.kcal).max() ?? 0)) * 1.15
  }

  private func lineY(_ kg: Double) -> Double {
    let (lo, hi) = lineScale
    let fraction = hi > lo ? (kg - lo) / (hi - lo) : 0.5
    return fraction * kcalMax * 0.75
  }

  private var weightCard: some View {
    let target = nutrition?.kcal ?? 0
    let scale = kcalMax
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Weight vs intake").forgeSection()
        Spacer()
        Text("last 28 days · kcal bars · weight line (\(unit), right)").forgeCaption()
      }
      Chart {
        ForEach(dayData.filter(\.hasLog)) { day in
          BarMark(x: .value("Date", day.date, unit: .day), y: .value("kcal", day.kcal))
            .foregroundStyle(barTint(day.kcal, target: target))
            .cornerRadius(3)
        }
        if target > 0 {
          RuleMark(y: .value("Target", target))
            .foregroundStyle(Theme.textSecondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        ForEach(dayData.filter { $0.weight != nil }) { day in
          LineMark(x: .value("Date", day.date), y: .value("Weight", lineY(day.weight!)))
            .foregroundStyle(Theme.accent)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
      }
      // ponytail: Swift Charts has no dual y-axis — weight line is scaled onto the kcal axis, right ticks invert it
      .chartYScale(domain: 0...max(scale, 1))
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear)) {
          AxisGridLine().foregroundStyle(Theme.track)
          AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
          AxisGridLine().foregroundStyle(Theme.track)
          AxisValueLabel()
            .font(.forge(11, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
        AxisMarks(position: .trailing, values: weightTickValues) { value in
          AxisValueLabel {
            if let y = value.as(Double.self), let kg = yToKg[y] {
              Text(displayWeight(kg)).forge(11, .medium).foregroundStyle(Theme.textTertiary)
            }
          }
        }
      }
      .frame(height: 180)
      caption
    }
    .card()
  }

  private var weightTicks: [(y: Double, kg: Double)] {
    let (lo, hi) = lineScale
    guard hi > lo else { return [] }
    return [lo, (lo + hi) / 2, hi].map { kg in (lineY(kg), kg) }
  }

  private var weightTickValues: [Double] {
    weightTicks.map(\.y)
  }

  private var yToKg: [Double: Double] {
    Dictionary(weightTicks.map { ($0.y.rounded(), $0.kg) }, uniquingKeysWith: { a, _ in a })
  }

  private func barTint(_ kcal: Double, target: Int) -> Color {
    guard kcal > 0, target > 0 else { return Theme.track }
    return abs(kcal - Double(target)) <= 0.1 * Double(target) ? Theme.positive : Theme.negative
  }

  @ViewBuilder private var caption: some View {
    if let slope = weeklySlopeKg {
      Text(
        "Average \(slope >= 0 ? "+" : "−")\(Fmt.num(abs(displayWeightNumber(slope)))) \(unit)/week on \(Fmt.grouped(Double(meanKcal))) kcal"
      )
      .forgeCaption()
      .monospacedDigit()
    } else {
      Text("Log weight and food for a couple of weeks to see the trend.").forgeCaption()
    }
  }

  private var meanKcal: Int {
    let logged = dayData.map(\.kcal).filter { $0 > 0 }
    guard !logged.isEmpty else { return 0 }
    return Int(logged.reduce(0, +) / Double(logged.count))
  }

  private var weeklySlopeKg: Double? {
    let points =
      weightByDay
      .filter { $0.key > Date.now.addingTimeInterval(-28 * 86400) }
      .sorted { $0.key < $1.key }
      .compactMap { entry -> (x: Double, y: Double)? in
        let x = entry.key.timeIntervalSince1970 / 86400
        return (x, entry.value)
      }
    guard points.count >= 2 else { return nil }
    let n = Double(points.count)
    let sumX = points.reduce(0) { $0 + $1.x }
    let sumY = points.reduce(0) { $0 + $1.y }
    let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
    let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
    let denominator = n * sumXX - sumX * sumX
    guard abs(denominator) > 0.0001 else { return nil }
    return ((n * sumXY - sumX * sumY) / denominator) * 7
  }

  private func displayWeight(_ kg: Double) -> String {
    Fmt.num(usesLb ? Plates.kgToLb(kg) : kg)
  }

  private func displayWeightNumber(_ kg: Double) -> Double {
    usesLb ? Plates.kgToLb(kg) : kg
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
            "Calories", base: "\(recommendation.base.kcal)",
            recommended: "\(recommendation.recommended.kcal) kcal")
          guidanceRow(
            "Protein", base: "\(recommendation.base.proteinG)",
            recommended: "\(recommendation.recommended.proteinG) g")
          guidanceRow(
            "Carbs", base: "\(recommendation.base.carbsG)",
            recommended: "\(recommendation.recommended.carbsG) g")
          guidanceRow(
            "Fat", base: "\(recommendation.base.fatG)",
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
      Image(systemName: "arrow.right").forgeCaption()
      Text(recommended).forgeLabel().monospacedDigit()
    }
  }
}
