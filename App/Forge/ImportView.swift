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
  @State private var pasteText = ""
  @State private var parsedLines: [TextImport.Line] = []
  @State private var showAudit = false

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

          pasteCard
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
      .navigationDestination(isPresented: $showAudit) { PlanAuditView() }
      .onReceive(NotificationCenter.default.publisher(for: .forgeAuditStarted)) { _ in
        dismiss()
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
      showAudit = true
    }
  }

  private var candidates: [QuickLogCandidate] {
    ExerciseDB.everything.map { QuickLogCandidate(id: $0.id, name: $0.name) }
  }

  private var pasteCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Paste a workout", bundle: L10n.bundle)).forgeSection()
      TextEditor(text: $pasteText)
        .frame(minHeight: 120)
        .forgeBody()
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
      Text("Bench 80x8 @8 / Squat 120x5 / 3x10 lat pulldown 45")
        .forgeCaption()
      Button {
        parsedLines = TextImport.parse(pasteText, candidates: candidates, defaultLb: assumeLb)
      } label: {
        Text(String(localized: "Parse", bundle: L10n.bundle))
      }
      .buttonStyle(PillSecondaryButtonStyle())
      if !parsedLines.isEmpty {
        // Positional by design: two pasted lines can be byte-identical, and the array is only
        // ever replaced wholesale by a re-parse.
        ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
          if let parsed = line.parsed {
            HStack(spacing: 8) {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
              Text(parsedDescription(parsed)).forgeBody()
              Spacer()
            }
          } else {
            HStack(spacing: 8) {
              Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.negative)
              Text(line.raw).forgeBody().foregroundStyle(Theme.negative)
              Spacer()
            }
          }
        }
      }
      Button {
        importPasted()
      } label: {
        Text(String(localized: "Import", bundle: L10n.bundle))
      }
      .buttonStyle(PillButtonStyle())
      .disabled(TextImport.sets(from: parsedLines).isEmpty)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func parsedDescription(_ parsed: QuickLogParse) -> String {
    let name = ExerciseDB.find(parsed.exerciseID)?.localizedName ?? parsed.exerciseID
    let weight = assumeLb ? Plates.kgToLb(parsed.weightKg) : parsed.weightKg
    let unit = assumeLb ? "lb" : "kg"
    let rpeText = parsed.rpe.map { " @\(Fmt.num($0))" } ?? ""
    return "\(name) · \(Fmt.num(weight)) \(unit) × \(parsed.reps)\(rpeText)"
  }

  private func importPasted() {
    let parsed = TextImport.sets(from: parsedLines)
    guard !parsed.isEmpty else { return }
    let session = WorkoutSession(date: .now, dayName: String(localized: "Imported", bundle: L10n.bundle), week: 0, completed: true)
    session.updatedAt = .now
    modelContext.insert(session)
    for (i, set) in parsed.enumerated() {
      session.sets.append(LoggedSet(
        exerciseID: set.exerciseID,
        setIndex: i,
        weightKg: set.weightKg,
        reps: set.reps,
        rpe: set.rpe ?? 8,
        targetRPE: 8,
        loggedAt: .now))
    }
    try? modelContext.save()
    Analytics.track("import_completed", ["source": "text"])
    Task {
      await SyncEngine.shared.sync()
      showAudit = true
    }
  }
}
