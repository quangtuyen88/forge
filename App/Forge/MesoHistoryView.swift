import SwiftUI
import SwiftData
import ForgeCore

struct MesoHistoryView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var blocks: [[WorkoutSession]] {
    var out: [[WorkoutSession]] = []
    var prevWeek: Int?
    for s in sessions.filter(\.completed).sorted(by: { $0.date < $1.date }) {
      if out.isEmpty || s.week < (prevWeek ?? s.week) {
        out.append([])
      }
      out[out.count - 1].append(s)
      prevWeek = s.week
    }
    return out
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if blocks.count >= 2 { latestVsPreviousCard }
        ForEach(Array(blocks.reversed().enumerated()), id: \.offset) { _, block in
          blockCard(block)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Mesocycles")
  }

  private func blockCard(_ block: [WorkoutSession]) -> some View {
    let sets = block.flatMap(\.sets)
    let tonnage = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return VStack(alignment: .leading, spacing: 10) {
      Text("\(block.first!.date.formatted(.dateTime.month().day().locale(L10n.locale))) – \(block.last!.date.formatted(.dateTime.month().day().year().locale(L10n.locale)))")
        .forgeSection()
      HStack(spacing: 4) {
        Text("\(block.count) sessions").forgeLabel()
        Text("·").forgeLabel()
        Text("\(sets.count) sets").forgeLabel().foregroundStyle(Theme.metricSets)
        Text("·").forgeLabel()
        Text(UnitFormat.weight(tonnage, usesLb: usesLb)).forgeLabel().monospacedDigit().foregroundStyle(Theme.metricLoad)
      }
      ForEach(topLifts(block), id: \.0) { name, e1rm in
        HStack {
          Text(name).forgeBodyStrong()
          Spacer()
          Text(UnitFormat.weight(e1rm, usesLb: usesLb))
            .forgeLabel()
            .monospacedDigit()
            .foregroundStyle(Theme.metricLoad)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func topLifts(_ block: [WorkoutSession]) -> [(String, Double)] {
    var bests: [String: Double] = [:]
    for s in block {
      for set in s.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return bests
      .compactMap { id, e in ExerciseDB.find(id).map { ($0.name, e) } }
      .sorted { $0.1 > $1.1 }
      .prefix(3).map { $0 }
  }

  private var latestVsPreviousCard: some View {
    let latest = blocks[blocks.count - 1]
    let previous = blocks[blocks.count - 2]
    return VStack(alignment: .leading, spacing: 10) {
      Text("Latest vs previous").forgeSection()
      deltaRow("Sessions",
               Double(latest.count - previous.count),
               suffix: "")
      deltaRow("Tonnage",
               UnitFormat.plain(tonnage(latest), usesLb: usesLb) - UnitFormat.plain(tonnage(previous), usesLb: usesLb),
               suffix: usesLb ? " lb" : " kg")
      ForEach([("barbell_bench", "Bench"), ("back_squat", "Squat"), ("deadlift", "Deadlift")], id: \.0) { id, name in
        if let l = bestE1RM(id, in: latest), let p = bestE1RM(id, in: previous) {
          deltaRow(name, UnitFormat.plain(l, usesLb: usesLb) - UnitFormat.plain(p, usesLb: usesLb), suffix: usesLb ? " lb" : " kg", decimals: 1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func tonnage(_ block: [WorkoutSession]) -> Double {
    block.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
  }

  private func bestE1RM(_ exerciseID: String, in block: [WorkoutSession]) -> Double? {
    block.flatMap(\.sets)
      .filter { $0.exerciseID == exerciseID }
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
  }

  @ViewBuilder
  private func deltaRow(_ label: String, _ delta: Double, suffix: String, decimals: Int = 0) -> some View {
    if delta != 0 {
      HStack {
        Text(label).forgeLabel()
        Spacer()
        Text(String(format: "%@%.\(decimals)f%@", delta > 0 ? "+" : "−", abs(delta), suffix))
          .forgeBodyStrong()
          .monospacedDigit()
          .foregroundStyle(delta > 0 ? Theme.positive : Theme.negative)
      }
    }
  }
}
