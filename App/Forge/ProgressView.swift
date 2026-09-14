import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct ProgressTabView: View {
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var selectedLift = ""

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
      List {
        if !loggedExerciseIDs.isEmpty {
          Section("Strength") {
            Picker("Lift", selection: $selectedLift) {
              ForEach(loggedExerciseIDs, id: \.self) { id in
                Text(ExerciseDB.find(id)?.name ?? id).tag(id)
              }
            }
            if !history.isEmpty {
              Chart(history, id: \.self) { point in
                LineMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
                PointMark(x: .value("Date", point.date), y: .value("e1RM", point.e1rm))
              }
              .frame(height: 200)
              if Strength.isPlateaued(history, asOf: .now) {
                Label("Plateau", systemImage: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
              }
            }
          }
        }
        Section("Consistency") {
          Text("\(streakWeeks(sessions: sessions))-week streak")
        }
        Section("This week") {
          ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) { muscle in
            let landmarks = VolumeLandmarks.base(for: muscle)!
            let volume = weekVolume[muscle] ?? 0
            HStack {
              Text(muscle.rawValue)
              Spacer()
              Text("\(Int(volume.rounded())) / MEV \(landmarks.mev) · MRV \(landmarks.mrv)")
                .foregroundStyle(volumeColor(volume, landmarks: landmarks))
            }
          }
        }
      }
      .navigationTitle("Progress")
      .toolbar {
        ShareLink(item: csvURL) {
          Label("Export CSV", systemImage: "square.and.arrow.up")
        }
      }
      .onAppear {
        if selectedLift.isEmpty { selectedLift = loggedExerciseIDs.first ?? "" }
      }
    }
  }

  private func volumeColor(_ volume: Double, landmarks: VolumeLandmarks) -> Color {
    if volume > Double(landmarks.mrv) { return .red }
    if volume >= Double(landmarks.mev) { return .green }
    return .gray
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
