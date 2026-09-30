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
  @State private var gymToDelete: GymProfileConfig?
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
            Image(systemName: "chevron.forward").foregroundStyle(Theme.textTertiary)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
            Image(systemName: "chevron.forward").foregroundStyle(Theme.textTertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
                  gymToDelete = gym
                }
              } label: {
                Image(systemName: "ellipsis")
                  .frame(minWidth: 44, minHeight: 44)
                  .contentShape(Rectangle())
              }
              .accessibilityLabel("Options for \(gym.name)")
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(
          constraints.activeGymProfileID == gym.id ? .isSelected : [])
        if gym.id != constraints.gymProfiles.last?.id { Divider().overlay(Theme.ring) }
      }
    }
    .card()
    .confirmationDialog(
      Text("Delete \(gymToDelete?.name ?? "")?"),
      isPresented: Binding(
        get: { gymToDelete != nil }, set: { if !$0 { gymToDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let gym = gymToDelete { deleteGym(gym) }
        gymToDelete = nil
      }
      Button("Cancel", role: .cancel) { gymToDelete = nil }
    } message: {
      Text("This gym and its equipment list are removed.")
    }
  }

  private func deleteGym(_ gym: GymProfileConfig) {
    constraints.gymProfiles.removeAll { $0.id == gym.id }
    if constraints.activeGymProfileID == gym.id {
      constraints.activeGymProfileID = constraints.gymProfiles.first?.id ?? "commercial"
    }
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
    let here = instances.filter { !$0.isRetired && $0.gymProfileID == gymID }
    guard !here.isEmpty else {
      return gymName.map {
        String(localized: "No equipment recorded at \($0)", bundle: L10n.bundle)
      } ?? String(localized: "No equipment recorded", bundle: L10n.bundle)
    }
    let needsReview = here.filter { $0.loadModel.normalizationStatus != .verified }.count
    let reviewText =
      needsReview == 0
      ? String(localized: "all confirmed", bundle: L10n.bundle)
      : needsReview == 1
        ? String(localized: "1 needs review", bundle: L10n.bundle)
        : String(localized: "\(needsReview) need review", bundle: L10n.bundle)
    let items = String(
      localized: "\(here.count) item\(L10n.pluralSuffix(here.count))", bundle: L10n.bundle)
    return gymName.map {
      String(localized: "\(items) at \($0) · \(reviewText)", bundle: L10n.bundle)
    } ?? "\(items) · \(reviewText)"
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
  @State private var showDiscard = false

  private var isDirty: Bool {
    name != (existing?.name ?? "")
      || equipment != (existing?.equipment ?? Set(Equipment.allCases))
  }

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
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { if isDirty { showDiscard = true } else { dismiss() } }
        }
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
      .interactiveDismissDisabled(isDirty)
      .confirmationDialog(
        "Discard changes?", isPresented: $showDiscard, titleVisibility: .visible
      ) {
        Button("Discard changes", role: .destructive) { dismiss() }
        Button("Cancel", role: .cancel) { showDiscard = false }
      } message: {
        Text("Your edits to this gym are not saved.")
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
    Group {
      if exercises.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
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
            .accessibilityLabel("\(exercise.localizedName), \(stateLabel(exercise.id))")
          }
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
    if constraints.lockedExerciseIDs.contains(id) {
      return String(localized: "Locked", bundle: L10n.bundle)
    }
    if constraints.excludedExerciseIDs.contains(id) {
      return String(localized: "Excluded", bundle: L10n.bundle)
    }
    return String(localized: "Normal", bundle: L10n.bundle)
  }
}

struct TrainingExperimentsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var checkIns: [CheckIn]
  @Environment(\.modelContext) private var modelContext
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var selected: ExperimentCandidate?
  @State private var showStop = false

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }
  private var experiment: TrainingExperiment? { profile?.trainingExperiment }

  /// One offered change, from the app's experiment catalog (one variable, four weeks).
  struct ExperimentCandidate: Identifiable, Equatable {
    let exercise: Exercise
    let intervention: TrainingExperimentIntervention
    let weeklyMuscleSets: Int
    var id: String { "\(exercise.id)-\(intervention.rawValue)" }
  }

  private var pendingIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  /// True in the block's last two weeks: a change started there would be read through the
  /// peak and the deload, so nothing is offered.
  private var lateBlock: Bool {
    guard let profile else { return false }
    return profile.currentWeek(sessions: sessions) >= Mesocycle.weeks - 1
  }

  private var injuryFlags: Set<InjuryFlag> {
    Set((profile?.injuryFlags ?? []).compactMap(InjuryFlag.init(rawValue:)))
  }

  private var candidates: [ExperimentCandidate] {
    guard !lateBlock else { return [] }
    let flags = injuryFlags
    let pending = Set(pendingIncreases.map(\.exercise.id))
    var counts: [String: Int] = [:]
    for set in sessions.filter(\.completed).flatMap(\.trustedSets) {
      counts[set.exerciseID, default: 0] += 1
    }
    let ranked = counts.keys
      .filter { !pending.contains($0) }
      .filter { flags.isEmpty || Substitution.replacement(for: $0, flags: flags) == nil }
      // Ties break by id: a Dictionary's key order changes between renders, and reshuffled
      // choices would drop the lifter's tap.
      .sorted { a, b in
        let ca = counts[a] ?? 0, cb = counts[b] ?? 0
        return ca != cb ? ca > cb : a < b
      }
    guard !ranked.isEmpty else { return [] }
    let cutoff = Date.now.addingTimeInterval(-28 * 86400)
    var weekly: [Muscle: Int] = [:]
    for session in sessions.filter({ $0.completed && $0.date >= cutoff }) {
      for set in session.trustedSets {
        if let exercise = ExerciseDB.find(set.exerciseID) {
          weekly[exercise.primary, default: 0] += 1
        }
      }
    }
    let top = Array(ranked.prefix(2)).compactMap(ExerciseDB.find)
    var out: [ExperimentCandidate] = []
    if let first = top.first {
      out.append(
        ExperimentCandidate(
          exercise: first, intervention: .addSet,
          weeklyMuscleSets: Int((Double(weekly[first.primary] ?? 0) / 4).rounded())))
    }
    let second = top.count > 1 ? top[1] : top.first
    if let second {
      out.append(
        ExperimentCandidate(
          exercise: second, intervention: .lowerRepRange,
          weeklyMuscleSets: Int((Double(weekly[second.primary] ?? 0) / 4).rounded())))
    }
    return out
  }

  /// Constraints the app actually records, stated as rows instead of silent absence.
  private var blockedRows: [(symbol: String, title: String, detail: String)] {
    var rows: [(String, String, String)] = []
    for flag in InjuryFlag.allCases where injuryFlags.contains(flag) {
      let affected = Set(sessions.filter(\.completed).flatMap(\.trustedSets).map(\.exerciseID))
        .filter { Substitution.replacement(for: $0, flags: [flag]) != nil }
      guard !affected.isEmpty else { continue }
      let names = affected.sorted().compactMap { ExerciseDB.find($0)?.localizedName }
        .prefix(2).joined(separator: ", ")
      rows.append(
        (
          "lock",
          String(localized: "\(names) changes", bundle: L10n.bundle),
          String(
            localized: "They wait until you clear your \(flag.name) flag.", bundle: L10n.bundle)
        ))
    }
    if lateBlock {
      rows.append(
        (
          "calendar",
          String(localized: "Starting this block", bundle: L10n.bundle),
          String(
            localized: "Peak week and the deload would blur the result.", bundle: L10n.bundle)
        ))
    }
    return rows
  }

  var body: some View {
    if let experiment {
      runningBody(experiment)
    } else {
      idleBody
    }
  }

  /// Today's chrome stays when an experiment is running or finished.
  private func runningBody(_ experiment: TrainingExperiment) -> some View {
    let name = ExerciseDB.find(experiment.exerciseID)?.localizedName ?? experiment.exerciseID
    return ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(
          title: "Experiments",
          subtitle: String(
            localized: "\(experiment.intervention.name) · \(name)", bundle: L10n.bundle),
          art: "art-flask"
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)
        experimentContent(experiment)
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation(String(localized: "Experiments", bundle: L10n.bundle))
  }

  // MARK: - none running

  private var idleBody: some View {
    ScrollView {
      VStack(spacing: 0) {
        FieldSection(bottom: 24) {
          fieldContent
        }
        VStack(spacing: 0) {
          if !candidates.isEmpty {
            choicesSection
          }
          if !blockedRows.isEmpty {
            blockedSection
          }
        }
        .background(Theme.page)
      }
      .padding(.bottom, 24)
    }
    .progressFieldPage(String(localized: "Experiments", bundle: L10n.bundle))
  }

  private var fieldContent: some View {
    VStack(spacing: 0) {
      ExperimentConstellation()
        .padding(.top, 8)
      Text(String(localized: "Test one change", bundle: L10n.bundle))
        .forge(28, .bold)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
      Text(
        String(
          localized: "4 weeks. \(coach.name) compares it with your best before it.",
          bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
  }

  private var choicesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "What do you want to try?", bundle: L10n.bundle))
        .forge(20, .bold)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 12)
      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 12),
          GridItem(.flexible(), spacing: 12),
        ], spacing: 12
      ) {
        ForEach(candidates) { candidate in
          candidateTile(candidate)
        }
      }
      .padding(.horizontal, Theme.margin)
      Button {
        guard let selected else { return }
        start(exerciseID: selected.exercise.id, intervention: selected.intervention)
      } label: {
        Text(String(localized: "Start experiment", bundle: L10n.bundle))
          .font(.forge(19, .bold, relativeTo: .headline))
          .foregroundStyle(selected == nil ? Theme.textSecondary : Theme.onAccent)
          .frame(maxWidth: .infinity, minHeight: 56)
          .background(Capsule().fill(selected == nil ? Theme.track : Theme.accent))
          .frame(minHeight: 56)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .disabled(selected == nil)
      .padding(.horizontal, Theme.margin)
      .padding(.top, 16)
      Text(caption)
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
      if let selected {
        compareSection(selected)
      }
    }
    .padding(.bottom, 24)
  }

  private func candidateTile(_ candidate: ExperimentCandidate) -> some View {
    let copy = candidateCopy(candidate)
    return ExperimentCandidateTile(
      imageName: copy.image,
      title: copy.title,
      detail: copy.expect,
      hint: "\(copy.expect) \(copy.cost)",
      isSelected: selected == candidate
    ) {
      selected = selected == candidate ? nil : candidate
    }
    .accessibilityIdentifier("experiments.choice.\(candidate.id)")
  }

  /// The Expect/Cost lines stay descriptive on purpose: the app records what a change does,
  /// never an outcome it has not measured.
  private func candidateCopy(_ candidate: ExperimentCandidate) -> (
    title: String, expect: String, cost: String, image: String
  ) {
    let muscle = candidate.exercise.primary
    let title: String
    let expect: String
    let cost: String
    switch candidate.intervention {
    case .addSet:
      if let plan = plannedSets(candidate) {
        title = String(
          localized:
            "\(candidate.exercise.localizedName) \(plan.sessionSets) → \(plan.sessionSets + 1) set\(L10n.pluralSuffix(plan.sessionSets + 1))",
            bundle: L10n.bundle)
        expect = String(
          localized: "One more set in \(localizedDayName(plan.day.name))", bundle: L10n.bundle)
      } else {
        title = String(
          localized: "\(candidate.exercise.localizedName) +1 set", bundle: L10n.bundle)
        expect =
          candidate.weeklyMuscleSets > 0
          ? String(
            localized: "\(muscle.a11yName) \(candidate.weeklyMuscleSets) → \(candidate.weeklyMuscleSets + 1) sets a week",
            bundle: L10n.bundle)
          : String(localized: "More weekly volume for \(muscle.a11yName)", bundle: L10n.bundle)
      }
      cost = String(localized: "1 extra set each session", bundle: L10n.bundle)
    case .lowerRepRange:
      title = String(
        localized: "\(candidate.exercise.localizedName) at 5–8 reps", bundle: L10n.bundle)
      expect = String(localized: "Heavier loads on the same lift", bundle: L10n.bundle)
      cost = String(localized: "Loads reset into the new range", bundle: L10n.bundle)
    }
    // The coach's scene of this lift's family, so the picture always shows the lift named.
    let scene = CoachScene.forExercise(candidate.exercise)
    return (title, expect, cost, coach.scene(scene))
  }

  /// The lift's planned sets in the current program week, when the program owns the schedule.
  private func plannedSets(_ candidate: ExperimentCandidate) -> (
    day: PlannedDay, sessionSets: Int, weeklySets: Int, dayCount: Int
  )? {
    guard let profile,
      profile.weekPlan == nil, !RoutineAdaptationService.weekPlanUnreadable(profile)
    else { return nil }
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    var weekly = 0
    var count = 0
    var first: (PlannedDay, Int)?
    for day in days {
      guard let planned = day.exercises.first(where: { $0.exercise.id == candidate.exercise.id })
      else { continue }
      weekly += planned.sets
      count += 1
      if first == nil { first = (day, planned.sets) }
    }
    guard let first else { return nil }
    return (first.0, first.1, weekly, count)
  }

  /// The moment comparable sets start counting: tomorrow's start when a session is already
  /// done today, else now.
  private var runWindowStart: Date {
    let cal = Calendar.current
    guard
      sessions.contains(where: { $0.completed && cal.isDate($0.date, inSameDayAs: .now) })
    else { return .now }
    return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
  }

  /// First still-planned day of the accepted week plan that trains the lift, when one exists.
  private func firstLiftDay(_ candidate: ExperimentCandidate) -> Date? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    return profile?.weekPlan?.days
      .filter { $0.state == .planned || $0.state == .remaining || $0.state == .moved }
      .compactMap { day -> Date? in
        let date = day.movedToDate ?? day.date
        guard date >= today, day.exerciseIDs.contains(candidate.exercise.id) else { return nil }
        return date
      }
      .sorted()
      .first
  }

  private var caption: String {
    guard let selected else {
      return String(localized: "Pick one change to start.", bundle: L10n.bundle)
    }
    let cal = Calendar.current
    let start = runWindowStart
    let end = cal.date(byAdding: .day, value: 27, to: start) ?? start
    var text = String(
      localized: "Runs \(start.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))) to \(end.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))), 4 weeks.",
      bundle: L10n.bundle)
    if let date = firstLiftDay(selected) {
      text += " " + String(
        localized: "First \(selected.exercise.localizedName) day: \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))).",
        bundle: L10n.bundle)
    }
    return text
  }

  /// What the coach will compare the test against, stated only from stored data.
  private func compareSection(_ candidate: ExperimentCandidate) -> some View {
    let plan = plannedSets(candidate)
    let unit = profile?.unit(for: candidate.exercise.id) ?? "kg"
    let best = bestE1RM(candidate.exercise.id)
    let bestShown = Fmt.num(profile?.display(kg: best, for: candidate.exercise.id) ?? best)
    return VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "What \(coach.name) will compare", bundle: L10n.bundle))
        .forge(20, .bold)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        compareRow(lead: LiftToken(exercise: candidate.exercise, size: 32)) {
          String(localized: "\(candidate.exercise.localizedName) estimated max", bundle: L10n.bundle)
        } detail: {
          String(localized: "\(bestShown) \(unit) now", bundle: L10n.bundle)
        }
        if let plan, candidate.intervention == .addSet {
          compareDivider
          compareRow(
            lead: Image(systemName: "chart.bar.fill")
              .scaledSystemFont(20)
              .foregroundStyle(Theme.metricSets)
              .frame(width: 32)
          ) {
            String(localized: "\(candidate.exercise.localizedName) sets a week", bundle: L10n.bundle)
          } detail: {
            String(
              localized: "\(plan.weeklySets) now, \(plan.weeklySets + plan.dayCount) during the test",
              bundle: L10n.bundle)
          }
        }
      }
      if let deload = deloadRangeInWindow {
        Text(
          String(
            localized: "Includes the deload week \(LogV3.spanText(from: deload.start, to: deload.end)). \(coach.name) leaves it out of the comparison.",
            bundle: L10n.bundle)
        )
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 12)
      }
      Text(
        String(
          localized: "You can stop any time. The change goes away and nothing else changes.",
          bundle: L10n.bundle)
      )
      .forge(13)
      .foregroundStyle(Theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Theme.margin)
      .padding(.top, 14)
    }
  }

  private var compareDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1)
      .padding(.leading, Theme.margin + 44)
      .padding(.trailing, Theme.margin)
  }

  /// One "will compare" row: 32 pt lead, title, quiet detail.
  private func compareRow<Lead: View>(
    lead: Lead, title: () -> String, detail: () -> String
  ) -> some View {
    HStack(spacing: 12) {
      lead
      VStack(alignment: .leading, spacing: 2) {
        Text(title())
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Text(detail())
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    .padding(.horizontal, Theme.margin)
  }

  /// Calendar span of the deload week inside the run window, when its days are recorded.
  private var deloadRangeInWindow: (start: Date, end: Date)? {
    let cal = Calendar.current
    let windowStart = cal.startOfDay(for: runWindowStart)
    guard let windowEnd = cal.date(byAdding: .day, value: 27, to: windowStart) else { return nil }
    let dates = sessions
      .filter {
        !$0.tombstoned && $0.week == Mesocycle.deloadWeek
          && $0.date >= windowStart && $0.date <= windowEnd
      }
      .map(\.date)
    guard let first = dates.min() else { return nil }
    let weekStart = cal.dateInterval(of: .weekOfYear, for: first)?.start ?? first
    guard let end = cal.date(byAdding: .day, value: 6, to: weekStart) else { return nil }
    return (weekStart, end)
  }

  private var blockedSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InsightsSectionHeader(title: "Not offered now")
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(blockedRows.enumerated()), id: \.offset) { index, row in
          HStack(spacing: 12) {
            Image(systemName: row.symbol)
              .scaledSystemFont(20)
              .foregroundStyle(row.symbol == "calendar" ? Theme.metricTime : Theme.textSecondary)
              .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
              Text(row.title)
                .forge(17, .semibold, tracking: -0.17)
                .foregroundStyle(Theme.text)
              Text(row.detail)
                .forge(14)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(minHeight: 60)
          .padding(.vertical, 10)
          .accessibilityElement(children: .combine)
          if index < blockedRows.count - 1 {
            Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 44)
          }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.bottom, 24)
  }

  // MARK: - running or finished

  private func experimentContent(_ experiment: TrainingExperiment) -> some View {
    let comparableSets = sessions
      .filter { $0.week != Mesocycle.deloadWeek }
      .flatMap(\.trustedSets)
      .filter { $0.exerciseID == experiment.exerciseID && $0.loggedAt >= experiment.startedAt }
    let unit = profile?.unit(for: experiment.exerciseID) ?? "kg"
    func shown(_ kg: Double) -> String {
      Fmt.num(profile?.display(kg: kg, for: experiment.exerciseID) ?? kg)
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
    let name = ExerciseDB.find(experiment.exerciseID)?.localizedName ?? experiment.exerciseID

    return VStack(spacing: 0) {
      HStack(spacing: 14) {
        if let exercise = ExerciseDB.find(experiment.exerciseID) {
          WorkoutArtTile(exercise: exercise, size: 56)
        } else {
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
            .fill(Theme.innerSurface)
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .forge(22, .bold, tracking: -0.33)
            .foregroundStyle(Theme.text)
          Text(experiment.intervention.name)
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
        Spacer(minLength: 8)
        Text(statusName(experiment.status))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 20)

      switch presentation {
      case .collecting(let day, let totalDays, let count):
        VStack(alignment: .leading, spacing: 6) {
          Text("Collecting results")
            .forge(18, .semibold, tracking: -0.18)
            .foregroundStyle(Theme.metricTime)
          Text(
            String(
              localized: "Day \(day) of \(totalDays) · \(count) comparable set\(L10n.pluralSuffix(count))",
              bundle: L10n.bundle)
          )
          .forgeLabel()
          .monospacedDigit()
          ProgressView(value: Double(day), total: Double(totalDays))
            .tint(Theme.metricTime)
            .accessibilityLabel(
              String(localized: "\(day) of \(totalDays) sessions done", bundle: L10n.bundle))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerSurface()
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
        Text(
          String(
            localized:
              "No effect is calculated until the four-week window closes and at least two comparable follow-up sets exist.",
            bundle: L10n.bundle)
        )
        .forgeLabel()
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)

      case .inconclusive(let reason, let count):
        VStack(alignment: .leading, spacing: 6) {
          Text("Inconclusive")
            .forge(18, .semibold, tracking: -0.18)
            .foregroundStyle(Theme.metricEffort)
          Text(reason).forgeBody()
          Text(
            String(
              localized: "\(count) comparable set\(L10n.pluralSuffix(count)) recorded",
              bundle: L10n.bundle)
          )
          .forgeCaption()
          .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerSurface()
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)

      case .result(let delta, let count):
        LogStatsRow(
          items: [
            LogStatsRow.Item(
              label: String(localized: "Baseline e1RM", bundle: L10n.bundle),
              value: shown(experiment.baselineE1RM),
              unit: unit,
              color: Theme.metricSets),
            LogStatsRow.Item(
              label: String(localized: "Current e1RM", bundle: L10n.bundle),
              value: shown(current),
              unit: unit,
              color: Theme.metricSets),
            LogStatsRow.Item(
              label: String(localized: "Change", bundle: L10n.bundle),
              value: (delta >= 0 ? "+" : "\u{2212}") + shown(abs(delta)),
              unit: unit,
              color: delta >= 0 ? Theme.positive : Theme.textSecondary),
          ])
          .padding(.horizontal, Theme.margin)
          .padding(.top, 16)
        Text(
          String(
            localized: "\(count) comparable set\(L10n.pluralSuffix(count))",
            bundle: L10n.bundle)
        )
        .forgeLabel()
        .monospacedDigit()
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        if experiment.status == .active {
          HStack(spacing: 12) {
            Button {
              finish(experiment, keep: true)
            } label: {
              Text(String(localized: "Keep change", bundle: L10n.bundle))
            }
            .buttonStyle(PillButtonStyle())
            Button {
              finish(experiment, keep: false)
            } label: {
              Text(String(localized: "Revert", bundle: L10n.bundle))
            }
            .buttonStyle(PillSecondaryButtonStyle())
          }
          .padding(.horizontal, Theme.margin)
          .padding(.top, 18)
        }
      }

      if experiment.status != .active {
        Button {
          profile?.trainingExperiment = nil
          selected = nil
        } label: {
          Text(String(localized: "Start another experiment", bundle: L10n.bundle))
        }
        .buttonStyle(PillSecondaryButtonStyle())
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
      }

      if experiment.status == .active {
        Button {
          showStop = true
        } label: {
          Text(String(localized: "Stop experiment", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(Theme.timelineRow))
            .contentShape(Rectangle())
        }
        .buttonStyle(ControlPressStyle())
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
        .confirmationDialog(
          String(localized: "Stop this experiment?", bundle: L10n.bundle),
          isPresented: $showStop,
          titleVisibility: .visible
        ) {
          Button(role: .destructive) {
            finish(experiment, keep: false)
          } label: {
            Text(String(localized: "Stop", bundle: L10n.bundle))
          }
          Button(role: .cancel) {} label: {
            Text(String(localized: "Cancel", bundle: L10n.bundle))
          }
        } message: {
          Text(
            String(
              localized: "You can stop any time. The change goes away and nothing else changes.",
              bundle: L10n.bundle))
        }
      }
    }
  }

  /// Localized display name for an experiment's status.
  private func statusName(_ status: TrainingExperimentStatus) -> String {
    switch status {
    case .active: return String(localized: "Active", bundle: L10n.bundle)
    case .kept: return String(localized: "Kept", bundle: L10n.bundle)
    case .reverted: return String(localized: "Reverted", bundle: L10n.bundle)
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
      startedAt: runWindowStart,
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
