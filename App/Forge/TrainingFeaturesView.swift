import ForgeCore
import SwiftData
import SwiftUI

struct TrainingConstraintsView: View {
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var constraints = TrainingConstraints()
  @State private var showGymEditor = false
  @State private var editingGym: GymProfileConfig?
  @State private var loaded = false

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        gymCard
        NavigationLink {
          EquipmentPassportView()
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Equipment passport").forgeBodyStrong()
              Text(equipmentPassportSummary).forgeLabel()
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Equipment passport")
        .accessibilityValue(equipmentPassportSummary)
        .accessibilityHint("Records what a load number means on each unit at each gym.")
        .card()
        modeCard
        sessionCard
        NavigationLink {
          ExerciseLocksView(constraints: $constraints)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Exercise rules").forgeBodyStrong()
              Text(
                "\(constraints.lockedExerciseIDs.count) locked · \(constraints.excludedExerciseIDs.count) excluded"
              ).forgeLabel()
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Training setup")
    .safeAreaInset(edge: .bottom) {
      Button("Save training setup", action: save)
        .buttonStyle(PillButtonStyle())
        .padding(.horizontal, Theme.barMargin)
        .padding(.vertical, 10)
        .background(Theme.page.opacity(0.92))
        .background(.ultraThinMaterial)
    }
    .onAppear {
      guard !loaded else { return }
      constraints = profiles.first?.trainingConstraints ?? TrainingConstraints()
      loaded = true
    }
    .onChange(of: constraints) { _, value in
      guard loaded, let profile = profiles.first else { return }
      profile.trainingConstraints = value
      try? modelContext.save()
    }
    .sheet(isPresented: $showGymEditor) {
      GymProfileForm(existing: editingGym) { profile in
        if let index = constraints.gymProfiles.firstIndex(where: { $0.id == profile.id }) {
          constraints.gymProfiles[index] = profile
        } else {
          constraints.gymProfiles.append(profile)
        }
        constraints.activeGymProfileID = profile.id
      }
    }
  }

  private var gymCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Gym profiles").forgeSection()
        Spacer()
        Button {
          editingGym = nil
          showGymEditor = true
        } label: {
          Label("Add gym", systemImage: "plus")
        }
        .forgeLabel()
      }
      ForEach(constraints.gymProfiles) { gym in
        Button {
          constraints.activeGymProfileID = gym.id
        } label: {
          HStack(spacing: 10) {
            Image(
              systemName: constraints.activeGymProfileID == gym.id
                ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(
              constraints.activeGymProfileID == gym.id ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
              Text(gym.name).forgeBodyStrong()
              Text(gym.equipment.map(\.name).sorted().joined(separator: " · ")).forgeCaption()
                .lineLimit(2)
            }
            Spacer()
            if !["commercial", "home", "hotel"].contains(gym.id) {
              Menu {
                Button("Edit") {
                  editingGym = gym
                  showGymEditor = true
                }
                Button("Delete", role: .destructive) {
                  constraints.gymProfiles.removeAll { $0.id == gym.id }
                  if constraints.activeGymProfileID == gym.id {
                    constraints.activeGymProfileID =
                      constraints.gymProfiles.first?.id ?? "commercial"
                  }
                }
              } label: {
                Image(systemName: "ellipsis")
              }
              .accessibilityLabel("Options for \(gym.name)")
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if gym.id != constraints.gymProfiles.last?.id { Divider().overlay(Theme.ring) }
      }
    }
    .card()
  }

  private var modeCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Real-life modes").forgeSection()
      Toggle("Travel mode", isOn: $constraints.travelMode).tint(Theme.accent)
      Text("Uses dumbbells, bands and bodyweight only.").forgeCaption()
      Divider().overlay(Theme.ring)
      Toggle("Crowded gym", isOn: $constraints.crowdMode).tint(Theme.accent)
      Text("Avoids machines and cables for this plan.").forgeCaption()
    }
    .forgeBody()
    .card()
  }

  private var sessionCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Session constraints").forgeSection()
      Picker("Time budget", selection: budgetBinding) {
        Text("Plan default").tag(0)
        ForEach([20, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
      }
      .pickerStyle(.menu)
      Divider().overlay(Theme.ring)
      Toggle("Minimum effective workout", isOn: $constraints.minimumEffectiveWorkout).tint(
        Theme.accent)
      Text("Keeps the highest-value exercises and caps the session at eight working sets.")
        .forgeCaption()
      Divider().overlay(Theme.ring)
      Toggle("Start workouts in Focus Mode", isOn: $constraints.focusModeDefault).tint(Theme.accent)
    }
    .forgeBody()
    .card()
  }

  /// One line describing what the passport already knows about the active gym, so the row
  /// reads before it is opened. Counts only live instances recorded at that gym.
  private var equipmentPassportSummary: String {
    let instances = profiles.first?.equipmentPassport.instances ?? []
    let gymID = constraints.activeGymProfileID
    let gymName = constraints.gymProfiles.first { $0.id == gymID }?.name
    let place = gymName.map { " at \($0)" } ?? ""
    let here = instances.filter { !$0.isRetired && $0.gymProfileID == gymID }
    guard !here.isEmpty else { return "No equipment recorded\(place)" }
    let needsReview = here.filter { $0.loadModel.normalizationStatus != .verified }.count
    let reviewText =
      needsReview == 0
      ? "all confirmed" : (needsReview == 1 ? "1 needs review" : "\(needsReview) need review")
    return "\(here.count) item\(here.count == 1 ? "" : "s")\(place) · \(reviewText)"
  }

  private var budgetBinding: Binding<Int> {
    Binding(
      get: { constraints.sessionBudgetMinutes ?? 0 },
      set: { constraints.sessionBudgetMinutes = $0 == 0 ? nil : $0 })
  }

  private func save() {
    guard let profile = profiles.first else { return }
    profile.trainingConstraints = constraints
    let evidence = [
      constraints.activeGymProfile?.name ?? "No gym profile",
      constraints.sessionBudgetMinutes.map { "\($0) min" } ?? "Plan time",
      constraints.minimumEffectiveWorkout ? "minimum effective" : "full session",
      constraints.travelMode ? "travel mode" : nil,
      constraints.crowdMode ? "crowded gym" : nil,
    ].compactMap { $0 }
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "constraints-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: "constraints",
          exerciseID: nil,
          muscle: nil,
          fromValue: nil,
          toValue: constraints.sessionBudgetMinutes.map(Double.init),
          reasonCodes: [DecisionSignal.userOverride.code, DecisionSignal.timeBudget.code],
          evidence: evidence,
          humanSummary: "Training constraints updated: " + evidence.joined(separator: ", ") + ".")))
    try? modelContext.save()
    Analytics.track(
      "training_constraints_saved",
      [
        "travel": constraints.travelMode ? "1" : "0",
        "crowd": constraints.crowdMode ? "1" : "0",
        "minimum": constraints.minimumEffectiveWorkout ? "1" : "0",
      ])
    dismiss()
  }
}

private struct GymProfileForm: View {
  @Environment(\.dismiss) private var dismiss
  let existing: GymProfileConfig?
  let onSave: (GymProfileConfig) -> Void
  @State private var name = ""
  @State private var equipment = Set(Equipment.allCases)

  var body: some View {
    NavigationStack {
      Form {
        TextField("Gym name", text: $name)
        Section("Equipment") {
          ForEach(Equipment.allCases, id: \.self) { item in
            Toggle(
              item.name,
              isOn: Binding(
                get: { equipment.contains(item) },
                set: { selected in
                  if selected { equipment.insert(item) } else { equipment.remove(item) }
                }))
          }
        }
      }
      .navigationTitle(existing == nil ? "New gym" : "Edit gym")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let profile = GymProfileConfig(
              id: existing?.id ?? UUID().uuidString,
              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
              equipment: equipment)
            onSave(profile)
            dismiss()
          }
          .disabled(
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || equipment.isEmpty)
        }
      }
      .onAppear {
        name = existing?.name ?? ""
        equipment = existing?.equipment ?? Set(Equipment.allCases)
      }
    }
  }
}

private struct ExerciseLocksView: View {
  @Binding var constraints: TrainingConstraints
  @State private var query = ""

  private var exercises: [Exercise] {
    let all = ExerciseDB.everything.sorted { $0.localizedName < $1.localizedName }
    return query.isEmpty
      ? all : all.filter { $0.localizedName.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    List(exercises) { exercise in
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.localizedName).forgeBodyStrong()
          Text("\(exercise.primary.a11yName) · \(exercise.equipment.name)").forgeCaption()
        }
        Spacer()
        Menu {
          Button("Use normally") { set(exercise.id, state: 0) }
          Button("Lock into plan") { set(exercise.id, state: 1) }
          Button("Exclude") { set(exercise.id, state: 2) }
        } label: {
          Text(stateLabel(exercise.id)).forgeLabel()
        }
      }
    }
    .searchable(text: $query, prompt: "Search exercises")
    .navigationTitle("Exercise rules")
  }

  private func set(_ id: String, state: Int) {
    constraints.lockedExerciseIDs.remove(id)
    constraints.excludedExerciseIDs.remove(id)
    if state == 1 { constraints.lockedExerciseIDs.insert(id) }
    if state == 2 { constraints.excludedExerciseIDs.insert(id) }
  }

  private func stateLabel(_ id: String) -> String {
    if constraints.lockedExerciseIDs.contains(id) { return "Locked" }
    if constraints.excludedExerciseIDs.contains(id) { return "Excluded" }
    return "Normal"
  }
}

struct TrainingExperimentsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext
  @State private var showNew = false

  private var profile: UserProfile? { profiles.first }
  private var experiment: TrainingExperiment? { profile?.trainingExperiment }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if let experiment {
          experimentCard(experiment)
        } else {
          emptyCard
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Training experiments")
    .sheet(isPresented: $showNew) {
      NewExperimentSheet(exerciseIDs: loggedExerciseIDs, sessions: sessions, onStart: start)
    }
  }

  private var emptyCard: some View {
    VStack(spacing: 12) {
      Image(systemName: "flask.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
      Text("Test one change").forgeTitle()
      Text("Run one controlled four-week change, then keep or revert it using your logged results.")
        .forgeLabel().multilineTextAlignment(.center)
      Button("Start experiment") { showNew = true }.buttonStyle(PillButtonStyle())
    }
    .card()
  }

  private func experimentCard(_ experiment: TrainingExperiment) -> some View {
    let comparableSets = sessions.flatMap(\.trustedSets).filter {
      $0.exerciseID == experiment.exerciseID && $0.loggedAt >= experiment.startedAt
    }
    let current =
      comparableSets
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max() ?? experiment.baselineE1RM
    let presentation = ExperimentPresentationPolicy.presentation(
      startedAt: experiment.startedAt,
      endsAt: experiment.endsAt,
      comparableCount: comparableSets.count,
      baseline: experiment.baselineE1RM,
      current: current,
      isActive: experiment.status == .active)

    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(ExerciseDB.find(experiment.exerciseID)?.localizedName ?? experiment.exerciseID)
          .forgeTitle()
        Spacer()
        Text(experiment.status.rawValue.capitalized).forgeCaption()
      }
      Text(experiment.intervention.name).forgeBodyStrong()

      switch presentation {
      case .collecting(let day, let totalDays, let count):
        VStack(alignment: .leading, spacing: 6) {
          Text("Collecting results").forgeSection().foregroundStyle(Theme.metricTime)
          Text("Day \(day) of \(totalDays) · \(count) comparable set\(count == 1 ? "" : "s")")
            .forgeLabel().monospacedDigit()
          ProgressView(value: Double(day), total: Double(totalDays)).tint(Theme.metricTime)
        }
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
            Theme.innerSurface))
        MetricGrid(items: [
          MetricItem("Baseline e1RM", Fmt.num(experiment.baselineE1RM), unit: "kg"),
          MetricItem("Follow-up sets", "\(count)"),
        ])
        Text(
          "No effect is calculated until the four-week window closes and at least two comparable follow-up sets exist."
        ).forgeCaption()

      case .inconclusive(let reason, let count):
        VStack(alignment: .leading, spacing: 6) {
          Text("Inconclusive").forgeSection().foregroundStyle(Theme.metricEffort)
          Text(reason).forgeBody()
          Text("\(count) comparable set\(count == 1 ? "" : "s") recorded").forgeCaption()
            .monospacedDigit()
        }
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
            Theme.innerSurface))

      case .result(let delta, let count):
        MetricGrid(items: [
          MetricItem("Baseline e1RM", Fmt.num(experiment.baselineE1RM), unit: "kg"),
          MetricItem("Current e1RM", Fmt.num(current), unit: "kg"),
          MetricItem(
            "Change", (delta >= 0 ? "+" : "") + Fmt.num(delta), unit: "kg",
            color: delta >= 0 ? Theme.positive : Theme.negative),
          MetricItem("Comparable sets", "\(count)"),
        ])
        if experiment.status == .active {
          HStack {
            Button("Keep change") { finish(experiment, keep: true) }.buttonStyle(PillButtonStyle())
            Button("Revert") { finish(experiment, keep: false) }.buttonStyle(
              PillSecondaryButtonStyle())
          }
        }
      }

      if experiment.status != .active {
        Button("Start another experiment") {
          profile?.trainingExperiment = nil
          showNew = true
        }
        .buttonStyle(PillSecondaryButtonStyle())
      }
    }
    .card()
  }

  private var loggedExerciseIDs: [String] {
    Array(Set(sessions.flatMap { $0.trustedSets.map(\.exerciseID) })).sorted {
      (ExerciseDB.find($0)?.localizedName ?? $0) < (ExerciseDB.find($1)?.localizedName ?? $1)
    }
  }

  private func bestE1RM(_ id: String) -> Double {
    sessions.flatMap(\.trustedSets).filter { $0.exerciseID == id }
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
  }

  private func start(exerciseID: String, intervention: TrainingExperimentIntervention) {
    guard let profile else { return }
    let experiment = TrainingExperiment(
      exerciseID: exerciseID,
      intervention: intervention,
      baselineE1RM: bestE1RM(exerciseID),
      previousSetDelta: profile.setDeltas[exerciseID] ?? 0,
      previousRepRange: profile.repRangeOverrides[exerciseID])
    switch intervention {
    case .addSet: profile.setDeltas[exerciseID] = experiment.previousSetDelta + 1
    case .lowerRepRange: profile.repRangeOverrides[exerciseID] = "5-8"
    }
    profile.trainingExperiment = experiment
    let name = ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "experiment-\(experiment.id)",
          date: .now,
          type: "experiment",
          exerciseID: exerciseID,
          muscle: nil,
          fromValue: experiment.baselineE1RM,
          toValue: nil,
          reasonCodes: [DecisionSignal.userOverride.code],
          evidence: [
            intervention.name, "baseline e1RM \(Fmt.num(experiment.baselineE1RM)) kg", "4 weeks",
          ],
          humanSummary: "Started a four-week \(name) experiment: \(intervention.name.lowercased())."
        )))
    try? modelContext.save()
    Analytics.track("training_experiment_started", ["kind": intervention.rawValue])
  }

  private func finish(_ experiment: TrainingExperiment, keep: Bool) {
    guard let profile else { return }
    var completed = experiment
    completed.status = keep ? .kept : .reverted
    if !keep {
      profile.setDeltas[experiment.exerciseID] =
        experiment.previousSetDelta == 0 ? nil : experiment.previousSetDelta
      profile.repRangeOverrides[experiment.exerciseID] = experiment.previousRepRange
    }
    profile.trainingExperiment = completed
    let current = bestE1RM(experiment.exerciseID)
    let name = ExerciseDB.find(experiment.exerciseID)?.localizedName ?? experiment.exerciseID
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "experiment-result-\(experiment.id)",
          date: .now,
          type: "experiment_result",
          exerciseID: experiment.exerciseID,
          muscle: nil,
          fromValue: experiment.baselineE1RM,
          toValue: current,
          reasonCodes: [
            DecisionSignal.userOverride.code,
            current >= experiment.baselineE1RM
              ? DecisionSignal.e1rmUp.code : DecisionSignal.e1rmDown.code,
          ],
          evidence: [
            "baseline \(Fmt.num(experiment.baselineE1RM)) kg", "current \(Fmt.num(current)) kg",
            keep ? "kept" : "reverted",
          ],
          humanSummary:
            "\(keep ? "Kept" : "Reverted") the \(name) experiment after comparing baseline and current e1RM."
        )))
    try? modelContext.save()
    Analytics.track("training_experiment_finished", ["kept": keep ? "1" : "0"])
  }
}

private struct NewExperimentSheet: View {
  @Environment(\.dismiss) private var dismiss
  let exerciseIDs: [String]
  let sessions: [WorkoutSession]
  let onStart: (String, TrainingExperimentIntervention) -> Void
  @State private var exerciseID = ""
  @State private var intervention = TrainingExperimentIntervention.addSet

  var body: some View {
    NavigationStack {
      Form {
        Picker("Exercise", selection: $exerciseID) {
          ForEach(exerciseIDs, id: \.self) { id in
            Text(ExerciseDB.find(id)?.localizedName ?? id).tag(id)
          }
        }
        Picker("Change", selection: $intervention) {
          ForEach(TrainingExperimentIntervention.allCases, id: \.self) { item in
            Text(item.name).tag(item)
          }
        }
        Section {
          Text(
            "Regulift changes one variable for four weeks. Everything else stays as stable as possible."
          ).forgeLabel()
        }
      }
      .navigationTitle("New experiment")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Start") {
            onStart(exerciseID, intervention)
            dismiss()
          }
          .disabled(exerciseID.isEmpty)
        }
      }
      .onAppear { if exerciseID.isEmpty { exerciseID = exerciseIDs.first ?? "" } }
    }
  }
}
