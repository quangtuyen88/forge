import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var selectedLift = ""

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var loggedExerciseIDs: [String] {
    Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).sorted()
  }

  private var history: [E1RMPoint] {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return sessions
      .filter { $0.date > cutoff }
      .compactMap { session -> E1RMPoint? in
        let best = session.sets
          .filter { $0.exerciseID == selectedLift }
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
          .max()
        guard let best else { return nil }
        return E1RMPoint(date: session.date, e1rm: best)
      }
      .sorted { $0.date < $1.date }
  }

  private var weekVolume: [Muscle: Double] {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    let entries: [(exercise: Exercise, set: SetLog)] = sessions
      .filter { $0.date > cutoff }
      .flatMap { session in
        session.sets.compactMap { set in
          ExerciseDB.find(set.exerciseID).map { exercise in
            (exercise: exercise, set: SetLog(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe))
          }
        }
      }
    return Volume.weeklySets(entries)
  }

  private var csvURL: URL {
    let rows = sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map { "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)" }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          streakCard
          strengthCard
          volumeCard
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Progress")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: csvURL) { Image(systemName: "square.and.arrow.up") }
        }
      }
      .onAppear {
        if selectedLift.isEmpty { selectedLift = loggedExerciseIDs.first ?? "" }
      }
    }
  }

  private var streak: Int { streakWeeks(sessions: sessions) }

  private var streakCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "flame.fill")
        .font(.system(size: 28))
        .foregroundStyle(streak > 0 ? Theme.accent : Color(.tertiaryLabel))
      VStack(alignment: .leading, spacing: 2) {
        Text("\(streak)-week streak").font(.title2).bold().monospacedDigit()
        if streak == 0 {
          Text("Log a workout this week to start one")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
    .card()
  }

  private var strengthCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      if loggedExerciseIDs.isEmpty {
        emptyStrength
      } else {
        HStack {
          Text("Strength").font(.headline)
          Spacer()
          Picker("Lift", selection: $selectedLift) {
            ForEach(loggedExerciseIDs, id: \.self) { id in
              Text(ExerciseDB.find(id)?.name ?? id).tag(id)
            }
          }
          .pickerStyle(.menu)
        }
        if !history.isEmpty {
          HStack(alignment: .firstTextBaseline) {
            Text("\(currentDisplay) \(unit)")
              .font(.title2).bold().monospacedDigit()
            if let delta = deltaDisplay {
              Text(delta).font(.footnote)
                .foregroundStyle(delta.hasPrefix("+") ? Color.green : Color.red)
            }
            Spacer()
            if Strength.isPlateaued(history, asOf: .now) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
          }
          Chart(history, id: \.self) { point in
            AreaMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              .foregroundStyle(Theme.accent.opacity(0.1))
              .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              .foregroundStyle(Theme.accent)
              .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              .foregroundStyle(Theme.accent)
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .frame(height: 180)
        }
      }
    }
    .card()
  }

  private var currentDisplay: String {
    guard let best = history.last?.e1rm else { return "—" }
    return formatDisplay(usesLb ? Plates.kgToLb(best) : best)
  }

  private var deltaDisplay: String? {
    guard let current = history.last else { return nil }
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else { return nil }
    let delta = (usesLb ? Plates.kgToLb(current.e1rm) : current.e1rm) - (usesLb ? Plates.kgToLb(prior.e1rm) : prior.e1rm)
    return String(format: "%@%.1f %@", delta > 0 ? "+" : "−", abs(delta), unit)
  }

  private var emptyStrength: some View {
    VStack(spacing: 8) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No lifts yet").font(.headline)
      Text("Finish a workout to see your e1RM trend.")
        .font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  private var volumeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("This week").font(.headline)
        Spacer()
        Text("sets per muscle").font(.footnote).foregroundStyle(.secondary)
      }
      MuscleMapView(intensity: weekIntensity)
        .frame(height: 220)
        .frame(maxWidth: .infinity)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) { muscle in
          volumeCell(muscle)
        }
      }
    }
    .card()
  }

  private func volumeCell(_ muscle: Muscle) -> some View {
    let l = VolumeLandmarks.base(for: muscle)!
    return VStack(spacing: 4) {
      VolumeRingView(sets: weekVolume[muscle] ?? 0, mev: l.mev, mrv: l.mrv)
      Text(displayName(muscle)).font(.caption).foregroundStyle(.secondary)
    }
  }

  private var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekVolume[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }

  private func displayName(_ muscle: Muscle) -> String {
    let spaced = muscle.rawValue.replacingOccurrences(of: "Delts", with: " delts")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }

  private func formatDisplay(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private func streakWeeks(sessions: [WorkoutSession]) -> Int {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
    let weeks = Set(sessions.filter(\.completed).compactMap { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }
}
