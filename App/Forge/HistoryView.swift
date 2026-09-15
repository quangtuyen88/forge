import SwiftUI
import SwiftData
import ForgeCore

enum UnitFormat {
  static func plain(_ kg: Double, usesLb: Bool) -> Double {
    usesLb ? Plates.kgToLb(kg) : kg
  }

  static func weight(_ kg: Double, usesLb: Bool) -> String {
    "\(Int(plain(kg, usesLb: usesLb).rounded()).formatted()) \(usesLb ? "lb" : "kg")"
  }
}

struct HistoryView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

  private var months: [(date: Date, sessions: [WorkoutSession])] {
    let cal = Calendar.current
    let groups = Dictionary(grouping: sessions.filter(\.completed)) {
      cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
    }
    return groups
      .map { (date: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    List {
      ForEach(months, id: \.date) { month in
        Section {
          ForEach(month.sessions) { session in
            NavigationLink {
              SessionDetailView(session: session, usesLb: usesLb)
            } label: {
              HistoryRow(session: session, usesLb: usesLb)
            }
          }
        } header: {
          Text(month.date, format: .dateTime.month(.wide).year())
            .forgeLabel()
        }
      }
    }
    .navigationTitle("History")
  }
}

struct HistoryRow: View {
  let session: WorkoutSession
  let usesLb: Bool

  private var durationText: String {
    let times = session.sets.map(\.loggedAt)
    guard let lo = times.min(), let hi = times.max(), hi > lo else { return "—" }
    return "\((Int(hi.timeIntervalSince(lo)) + 59) / 60) min"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(session.dayName).forgeBodyStrong()
      Text("\(session.date.formatted(.dateTime.month().day())) · \(durationText) · \(session.sets.count) sets · \(UnitFormat.weight(session.sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }, usesLb: usesLb))")
        .forgeCaption()
        .monospacedDigit()
    }
    .padding(.vertical, 2)
  }
}

struct SessionDetailView: View {
  let session: WorkoutSession
  let usesLb: Bool

  private var orderedIDs: [String] {
    var seen: [String] = []
    for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) where !seen.contains(set.exerciseID) {
      seen.append(set.exerciseID)
    }
    return seen
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if !session.notes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Notes").forgeSection()
            Text(session.notes).forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }
        ForEach(orderedIDs, id: \.self) { id in
          if let exercise = ExerciseDB.find(id) {
            exerciseCard(exercise, sets: session.sets.filter { $0.exerciseID == id }.sorted { $0.setIndex < $1.setIndex })
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(session.dayName)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func exerciseCard(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(exercise.name).forgeBodyStrong()
        Spacer()
        if let best = sets.map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max() {
          Text("e1RM \(UnitFormat.weight(best, usesLb: usesLb))")
            .forgeCaption()
            .monospacedDigit()
        }
      }
      ForEach(sets, id: \.persistentModelID) { set in
        HStack(spacing: 8) {
          Text("\(Int(UnitFormat.plain(set.weightKg, usesLb: usesLb).rounded())) × \(set.reps) @ \(set.rpe, specifier: "%g")")
            .forgeLabel()
            .monospacedDigit()
          if set.variant != "straight", let label = SetVariant(rawValue: set.variant)?.label {
            Text(label)
              .forge(11, .semibold)
              .foregroundColor(Theme.accent)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accent.opacity(0.12)))
          }
          Spacer()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}
