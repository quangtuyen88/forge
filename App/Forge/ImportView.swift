import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ForgeCore

struct ImportView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var existing: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var assumeLb = false
  @State private var assumeLbTouched = false
  @State private var picking = false
  @State private var csvText: String?
  @State private var readFailed = false
  @State private var importedCount: Int?
  @State private var result: WorkoutImport.Result?

  private var failed: Bool {
    readFailed || (csvText != nil && result == nil)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Strong: Settings → Export Data.").forgeBody()
            Text("Hevy: Settings → Export & Import Data.").forgeBody()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()

          Picker("Weights in", selection: unitBinding) {
            Text("kg").tag(false)
            Text("lb").tag(true)
          }
          .pickerStyle(.segmented)

          Button {
            picking = true
          } label: {
            Label("Choose file", systemImage: "doc")
          }
          .buttonStyle(PillSecondaryButtonStyle())

          if failed {
            Text("Couldn't read that file. Export it again and retry.").forgeLabel()
          }

          if let result {
            VStack(alignment: .leading, spacing: 10) {
              Text(String(localized: "\(result.sessions.count) workouts · \(totalSets(result)) sets · weights in \(result.unitIsLb ? "lb" : "kg")", bundle: L10n.bundle)).forgeBodyStrong()
              if !result.unmatchedNames.isEmpty {
                Text(String(localized: "\(result.unmatchedNames.count) exercises not matched", bundle: L10n.bundle)).forgeBody()
                ForEach(result.unmatchedNames, id: \.self) { name in
                  Text(name).forgeLabel()
                }
              }
              Button {
                importAll(result)
              } label: {
                Text("Import")
              }
              .buttonStyle(PillButtonStyle())
              .disabled(importedCount != nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
          }

          if let n = importedCount {
            Text(String(localized: "Imported \(n) workouts", bundle: L10n.bundle)).forgeBodyStrong().foregroundStyle(Theme.positive)
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Import history")
      .toolbar { Button("Done") { dismiss() }.bold() }
      .onAppear {
        if !assumeLbTouched, let p = profiles.first { assumeLb = p.usesLb }
      }
      .onChange(of: assumeLb) { _, _ in
        result = csvText.flatMap { WorkoutImport.parse($0, assumeLb: assumeLb) }
      }
      .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { outcome in
        guard case .success(let url) = outcome else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
          readFailed = true
          csvText = nil
          result = nil
          return
        }
        readFailed = false
        csvText = csv
        result = WorkoutImport.parse(csv, assumeLb: assumeLb)
      }
    }
  }

  private var unitBinding: Binding<Bool> {
    Binding(
      get: { assumeLb },
      set: { assumeLb = $0; assumeLbTouched = true })
  }

  private func totalSets(_ result: WorkoutImport.Result) -> Int {
    result.sessions.reduce(0) { $0 + $1.sets.count }
  }

  private func importAll(_ result: WorkoutImport.Result) {
    var inserted = 0
    for session in result.sessions {
      let clash = existing.contains {
        $0.dayName == session.name && abs($0.date.timeIntervalSince(session.date)) <= 60
      }
      if clash { continue }
      let model = WorkoutSession(date: session.date, dayName: session.name, week: 0, completed: true)
      model.notes = session.notes
      model.updatedAt = .now
      modelContext.insert(model)
      for (i, set) in session.sets.enumerated() {
        guard let exercise = WorkoutImport.match(set.exerciseName) else { continue }
        model.sets.append(LoggedSet(
          exerciseID: exercise.id,
          setIndex: set.setIndex,
          weightKg: set.weightKg,
          reps: set.reps,
          rpe: set.rpe ?? 8,
          targetRPE: 8,
          loggedAt: session.date.addingTimeInterval(TimeInterval(session.durationSeconds ?? session.sets.count) * Double(i) / Double(max(1, session.sets.count - 1)))))
      }
      inserted += 1
    }
    try? modelContext.save()
    Analytics.track("import_completed", ["source": result.source == .strong ? "strong" : "hevy", "sessions": "\(inserted)"])
    importedCount = inserted
    Task {
      try? await Task.sleep(for: .seconds(1))
      await SyncEngine.shared.sync()
      dismiss()
    }
  }
}
