import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct NutritionView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \NutritionProfile.updated, order: .reverse) private var nutritionProfiles: [NutritionProfile]
  @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

  @State private var showSetup = false
  @State private var addMeal: Meal?
  @State private var quickAdd = false

  private var profile: UserProfile? { profiles.first }
  private var nutrition: NutritionProfile? { nutritionProfiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var todayEntries: [FoodEntry] {
    entries.filter { Calendar.current.isDateInToday($0.date) }
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
    return sessions
      .filter { $0.completed && $0.date >= cutoff }
      .flatMap(\.sets)
      .filter { $0.rpe >= 6 }
      .count
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if nutrition == nil {
            heroCard
          } else {
            todayCard
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
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Edit targets") { showSetup = true }
            Button("Quick-add favorites") { quickAdd = true }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
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
    }
  }

  private var heroCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-plan", height: 140)
      Text("Fuel the block").forgeTitle()
      Text("Calories, protein, carbs and fat tuned to your phase and training volume — set once, then just log.").forgeLabel()
        .multilineTextAlignment(.center)
      Button("Set targets") { showSetup = true }
        .buttonStyle(PillButtonStyle())
    }
    .frame(maxWidth: .infinity)
    .card()
  }

  private var todayCard: some View {
    let kcalTarget = Double(nutrition?.kcal ?? 0)
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Today").forgeSection()
        Spacer()
        Menu {
          ForEach(Phase.allCases, id: \.self) { p in
            Button(p.name) { setPhase(p) }
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
            .forgeNumber()
            .foregroundStyle(Theme.metricEnergy)
          Text("kcal left").forgeCaption()
        }
        Spacer()
        Text("\(Fmt.grouped(consumed.kcal)) / \(Fmt.grouped(kcalTarget))")
          .forgeLabel()
          .monospacedDigit()
      }
      macroRow(label: String(localized: "protein"), value: consumed.protein, target: Double(nutrition?.proteinG ?? 0), tint: Theme.accentValue)
      macroRow(label: String(localized: "carbs"), value: consumed.carbs, target: Double(nutrition?.carbsG ?? 0), tint: Theme.ramp[2])
      macroRow(label: String(localized: "fat"), value: consumed.fat, target: Double(nutrition?.fatG ?? 0), tint: Theme.ramp[1])
    }
    .card()
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
            Button { addMeal = meal } label: {
              Text("Add")
                .forge(12, .semibold)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accentTint))
            }
            .buttonStyle(.plain)
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
              .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
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
    var id: Date { date }
  }

  private var dayData: [DayDatum] {
    let cal = Calendar.current
    let weights = weightByDay
    let kcalByDay = Dictionary(grouping: entries, by: { cal.startOfDay(for: $0.date) })
      .mapValues { $0.reduce(0.0) { $0 + $1.kcal } }
    return (0..<28).compactMap { offset in
      guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { return nil }
      let window = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: day) }
      let rolling = window.compactMap { weights[$0] }
      return DayDatum(
        date: day,
        kcal: kcalByDay[day] ?? 0,
        weight: rolling.isEmpty ? nil : rolling.reduce(0, +) / Double(rolling.count))
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
        ForEach(dayData) { day in
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
          AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
      Text("Average \(slope >= 0 ? "+" : "−")\(Fmt.num(abs(displayWeightNumber(slope)))) \(unit)/week on \(Fmt.grouped(Double(meanKcal))) kcal")
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
    let points = weightByDay
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

