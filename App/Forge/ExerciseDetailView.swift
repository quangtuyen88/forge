import SwiftUI
import AVKit
import SwiftData
import ForgeCore

/// Exercise detail sheet: header, looping demo clip, last-3 history, per-exercise note.
struct ExerciseDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  let exercise: Exercise
  let sessions: [WorkoutSession]
  let usesLb: Bool
  @Binding var note: String

  private var profile: UserProfile? { profiles.first }
  private var isLb: Bool { profile?.isLb(for: exercise.id) ?? usesLb }
  private var unit: String { isLb ? "lb" : "kg" }

  private var unitSelection: Int {
    switch profile?.unitOverrides[exercise.id] {
    case true: return 2
    case false: return 1
    default: return 0
    }
  }

  private func setUnit(_ selection: Int) {
    switch selection {
    case 1: profile?.unitOverrides[exercise.id] = false
    case 2: profile?.unitOverrides[exercise.id] = true
    default: profile?.unitOverrides.removeValue(forKey: exercise.id)
    }
    try? modelContext.save()
  }

  private var patternWords: String {
    let raw = exercise.pattern.rawValue
    var out = String(raw.prefix(1))
    for ch in raw.dropFirst() {
      out += ch.isUppercase ? " \(ch.lowercased())" : String(ch)
    }
    return out
  }

  private var history: [WorkoutSession] {
    Array(
      sessions
        .filter { s in s.sets.contains { $0.exerciseID == exercise.id } }
        .sorted { $0.date > $1.date }
        .prefix(3))
  }

  private var bestE1RM: Double? {
    let best = sessions
      .flatMap(\.sets)
      .filter { $0.exerciseID == exercise.id }
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    return (best ?? 0) > 0 ? best : nil
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          header
          demoCard
          unitCard
          historyCard
          notesCard
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle(exercise.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
    .presentationDetents([.large])
    .presentationBackground(Theme.page)
  }

  // MARK: header

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      EquipmentThumb(equipment: exercise.equipment, size: 56)
      VStack(alignment: .leading, spacing: 4) {
        Text(exercise.name).forgeTitle()
        Text("\(exercise.equipment.rawValue.capitalized) · \(patternWords) · \(muscleDisplayName(exercise.primary)) · \(exercise.difficulty.rawValue.capitalized)")
          .forgeLabel()
        if !exercise.synergists.isEmpty {
          Text(exercise.synergists.map(muscleDisplayName).joined(separator: ", "))
            .forgeCaption()
        }
      }
    }
  }

  // MARK: demo

  @ViewBuilder private var demoCard: some View {
    if let videoURL = exercise.videoURL {
      DemoPlayer(url: videoURL, id: exercise.id)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    } else {
      demoPlaceholder
    }
  }

  private var demoPlaceholder: some View {
    VStack(spacing: 8) {
      Illustration(name: "art-plan", height: 120)
      Text("Demo clip coming").forgeCaption()
    }
    .frame(maxWidth: .infinity)
    .card()
  }

  // MARK: unit

  private var unitCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Unit").forgeSection()
      Picker("Unit", selection: Binding(get: { unitSelection }, set: { setUnit($0) })) {
        Text("Default").tag(0)
        Text("kg").tag(1)
        Text("lb").tag(2)
      }
      .pickerStyle(.segmented)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  // MARK: history

  private var historyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("History").forgeSection()
        Spacer()
        if let best = bestE1RM {
          VStack(alignment: .trailing, spacing: 2) {
            Text("Best e1RM").forgeCaption()
            Text("\(display(best)) \(unit)").forgeNumber()
          }
        }
      }
      if history.isEmpty {
        Text("First time with this exercise").forgeLabel()
      } else {
        ForEach(history) { s in
          HStack(alignment: .firstTextBaseline) {
            Text(s.date.formatted(date: .abbreviated, time: .omitted))
              .forgeCaption()
              .frame(width: 96, alignment: .leading)
            Text(setLine(s))
              .forgeLabel()
              .monospacedDigit()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func setLine(_ session: WorkoutSession) -> String {
    session.sets
      .filter { $0.exerciseID == exercise.id }
      .sorted { $0.setIndex < $1.setIndex }
      .map { String(localized: "\(display($0.weightKg)) × \($0.reps) @ \(String(format: "%g", $0.rpe))") }
      .joined(separator: " · ")
  }

  // MARK: notes

  private var notesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Notes").forgeSection()
      TextEditor(text: $note)
        .forgeBody()
        .frame(height: 120)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func display(_ kg: Double) -> String {
    String(format: "%.1f", isLb ? Plates.kgToLb(kg) : kg)
  }
}

/// Looping, muted 16:9 demo clip. Downloads once to Caches/ExerciseDemos and plays from disk.
struct DemoPlayer: View {
  let url: URL
  let id: String
  @State private var player: AVQueuePlayer?
  @State private var looper: AVPlayerLooper?
  @State private var downloading = false

  private var cacheURL: URL {
    FileManager.default
      .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "ExerciseDemos", directoryHint: .isDirectory)
      .appending(path: "\(id).mp4")
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.innerSurface)
      if let player {
        VideoPlayer(player: player)
      } else if downloading {
        ProgressView()
      } else {
        Illustration(name: "art-plan", height: 100)
        Text("Demo clip coming").forgeCaption()
      }
    }
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .task { await prepare() }
  }

  private func prepare() async {
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      play(cacheURL)
      return
    }
    downloading = true
    do {
      let (tmp, _) = try await URLSession.shared.download(from: url)
      try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: cacheURL.path) {
        try? FileManager.default.removeItem(at: tmp)
      } else {
        try FileManager.default.moveItem(at: tmp, to: cacheURL)
      }
      play(cacheURL)
    } catch {
      // player stays nil → placeholder below
    }
    downloading = false
  }

  private func play(_ file: URL) {
    let q = AVQueuePlayer()
    looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: file))
    q.isMuted = true
    player = q
    q.play()
  }
}
