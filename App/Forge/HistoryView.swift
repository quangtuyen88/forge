import ForgeCore
import SwiftData
import SwiftUI

enum UnitFormat {
  static func plain(_ kg: Double, usesLb: Bool) -> Double {
    usesLb ? Plates.kgToLb(kg) : kg
  }

  static func weight(_ kg: Double, usesLb: Bool) -> String {
    String(
      localized: "\(Int(plain(kg, usesLb: usesLb).rounded()).formatted()) \(usesLb ? "lb" : "kg")",
      bundle: L10n.bundle)
  }
}

/// Session arithmetic the screens share. Internal, not private, so the duration policy can
/// be asserted in tests rather than re-implemented in each view.
enum SessionMath {
  static func tonnageText(_ sessions: [WorkoutSession], usesLb: Bool) -> String {
    let kg = sessions.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return Fmt.grouped(usesLb ? Plates.kgToLb(kg) : kg)
  }

  static func totalMinutes(_ sessions: [WorkoutSession]) -> Int {
    sessions.reduce(0) { total, session in
      let times = session.sets.map(\.loggedAt)
      guard let lo = times.min(), let hi = times.max(), hi > lo else { return total }
      return total + (Int(hi.timeIntervalSince(lo)) + 59) / 60
    }
  }

  /// Seconds between the first and last logged set. One definition of "how long", so the
  /// summary and History cannot round the same session to 0 in one place and 1 in another.
  static func totalSeconds(_ sessions: [WorkoutSession]) -> Int {
    sessions.reduce(0) { total, session in
      let times = session.sets.map(\.loggedAt)
      guard let lo = times.min(), let hi = times.max(), hi > lo else { return total }
      return total + Int(hi.timeIntervalSince(lo))
    }
  }

  /// How a duration is written. Under a minute is stated as such rather than shown as "0 min"
  /// — two sets a few seconds apart are a real workout, just a short one.
  static func durationText(_ sessions: [WorkoutSession]) -> String {
    let seconds = totalSeconds(sessions)
    if seconds <= 0 { return String(localized: "—", bundle: L10n.bundle) }
    if seconds < 60 { return String(localized: "Under 1 min", bundle: L10n.bundle) }
    return String(localized: "\(seconds / 60) min", bundle: L10n.bundle)
  }
}

struct HistoryView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext
  @State private var pendingDelete: WorkoutSession?

  private var months: [(date: Date, sessions: [WorkoutSession])] {
    let cal = Calendar.current
    let groups = Dictionary(grouping: sessions.filter { $0.completed && !$0.tombstoned }) {
      cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
    }
    return
      groups
      .map { (date: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        WeekStrip(sessions: sessions, plannedDays: profiles.first?.daysPerWeek ?? 0)
          .padding(.horizontal, 6)
        ForEach(months, id: \.date) { month in
          VStack(alignment: .leading, spacing: 10) {
            Text(month.date, format: .dateTime.month(.wide).year().locale(L10n.locale)).forgeTitle()
            MonthTotalsRow(
              sessions: month.sessions.count,
              minutes: SessionMath.totalMinutes(month.sessions),
              sets: month.sessions.reduce(0) { $0 + $1.sets.count },
              tonnage: SessionMath.tonnageText(month.sessions, usesLb: usesLb),
              unit: usesLb ? "lb" : "kg")
            VStack(spacing: 0) {
              ForEach(Array(month.sessions.enumerated()), id: \.element.persistentModelID) {
                index, session in
                SwipeDeleteRow {
                  pendingDelete = session
                } content: {
                  NavigationLink {
                    SessionDetailView(session: session, usesLb: usesLb)
                  } label: {
                    SessionRow(
                      title: localizedDayName(session.dayName),
                      value: SessionMath.tonnageText([session], usesLb: usesLb),
                      unit: usesLb ? "lb" : "kg",
                      trailing: String(
                        localized:
                          "\(session.date.formatted(.dateTime.month().day().locale(L10n.locale))) · \(session.sets.count) sets",
                        bundle: L10n.bundle))
                  }
                  .buttonStyle(RowPressStyle())
                }
                if index < month.sessions.count - 1 { Divider().overlay(Theme.ring) }
              }
            }
            .card()
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("History")
    .confirmationDialog(
      "Delete this session?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete session", role: .destructive) {
        guard let session = pendingDelete else { return }
        Analytics.track("session_deleted")
        Task { await SessionDetailView.delete(session, context: modelContext) }
      }
    }
  }
}

struct SessionDetailView: View {
  let session: WorkoutSession
  let usesLb: Bool
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var editing = false
  @State private var confirmDelete = false
  @State private var editTracked = false
  @State private var feedbackSet: LoggedSet?

  private var coach: Coach { Coach.from(coachID) }

  private var prs: [PRRecord] { compatibleSessionPRs() }

  /// Session PRs restricted to baselines whose recorded equipment context is compatible with
  /// this session's set. A different machine, or a legacy-unknown load, can never stand as the
  /// predecessor, so incompatible verified instances are not merged into one baseline.
  private func compatibleSessionPRs() -> [PRRecord] {
    guard session.verified else { return [] }
    let earlier = allSessions.filter { $0.completed && $0 !== session && $0.date < session.date }
    let e1rm: (LoggedSet) -> Double = { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
    return Set(session.analysisSets(.achievements).map(\.exerciseID)).compactMap {
      id -> PRRecord? in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      let mine = session.analysisSets(.achievements).filter { $0.exerciseID == id }
      guard let reference = mine.max(by: { e1rm($0) < e1rm($1) }) else { return nil }
      let best = e1rm(reference)
      let previous = earlier.flatMap { $0.analysisSets(.achievements) }
        .filter { $0.exerciseID == id && $0.isComparableForBaseline(to: reference) }
        .map(e1rm).max()
      guard let previous, best > previous else { return nil }
      return PRRecord(exercise: exercise, e1rm: best, previous: previous)
    }
    .sorted { $0.exercise.localizedName < $1.exercise.localizedName }
  }

  /// Human-readable equipment context for this session's loads, when passport instances were
  /// recorded. Absent for legacy/imported sets, which stay unlabeled rather than guessed.
  private var equipmentContextLine: String? {
    let ids = Set(session.sets.compactMap(\.equipmentInstanceID))
    guard !ids.isEmpty, let profile = profiles.first else { return nil }
    let names = ids.compactMap { profile.equipmentPassport.instance(id: $0)?.name }.sorted()
    guard !names.isEmpty else { return nil }
    return String(localized: "Equipment: \(names.joined(separator: ", "))", bundle: L10n.bundle)
  }

  /// True when this session recorded verified loads on more than one instance for a single
  /// exercise — those must never be merged into one baseline.
  private var hasIncomparableInstances: Bool {
    Dictionary(
      grouping: session.sets.filter { $0.comparisonContext.normalizationStatus == .verified },
      by: \.exerciseID
    ).values.contains { sets in
      guard let first = sets.first else { return false }
      return !sets.allSatisfy { $0.isComparableForBaseline(to: first) }
    }
  }

  private var debrief: [DebriefLine] {
    guard session.completed, !session.sets.isEmpty else { return [] }
    return debriefLines(
      session: session, sessions: allSessions, prs: prs, profile: profiles.first, usesLb: usesLb)
  }

  private var orderedIDs: [String] {
    var seen: [String] = []
    for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex })
    where !seen.contains(set.exerciseID) {
      seen.append(set.exerciseID)
    }
    return seen
  }

  private var timeRange: String {
    let times = session.sets.sorted { $0.loggedAt < $1.loggedAt }.map(\.loggedAt)
    guard let first = times.first, let last = times.last else {
      return session.date.formatted(.dateTime.hour().minute().locale(L10n.locale))
    }
    if times.count == 1 { return first.formatted(.dateTime.hour().minute().locale(L10n.locale)) }
    return
      "\(first.formatted(.dateTime.hour().minute().locale(L10n.locale)))–\(last.formatted(.dateTime.hour().minute().locale(L10n.locale)))"
  }

  private var detailItems: [MetricItem] {
    var items = [
      MetricItem(
        String(localized: "Duration", bundle: L10n.bundle),
        SessionMath.durationText([session]), color: Theme.metricTime),
      MetricItem(
        String(localized: "Sets", bundle: L10n.bundle), "\(session.sets.count)",
        color: Theme.metricSets),
      MetricItem(
        String(localized: "Tonnage", bundle: L10n.bundle),
        SessionMath.tonnageText([session], usesLb: usesLb), unit: usesLb ? "lb" : "kg",
        color: Theme.metricLoad),
      MetricItem(String(localized: "Exercises", bundle: L10n.bundle), "\(orderedIDs.count)"),
    ]
    // Effort is an observation, not a field that always holds a number. Averaging every
    // set's `rpe` turned the plan's target into a reported average for sets nobody rated —
    // the tile now counts only what the lifter actually reported, and says how many.
    let rated = session.sets.filter(\.effortReported)
    if !session.sets.isEmpty {
      if rated.isEmpty {
        items.append(
          MetricItem(
            String(localized: "Avg RPE", bundle: L10n.bundle),
            String(localized: "—", bundle: L10n.bundle),
            caption: String(localized: "you didn't rate these", bundle: L10n.bundle),
            color: Theme.metricEffort))
      } else {
        items.append(
          MetricItem(
            String(localized: "Avg RPE", bundle: L10n.bundle),
            Fmt.num(rated.reduce(0.0) { $0 + $1.rpe } / Double(rated.count)),
            caption: rated.count == session.sets.count
              ? nil
              : String(localized: "\(rated.count) of \(session.sets.count) sets", bundle: L10n.bundle),
            color: Theme.metricEffort))
      }
    }
    return items
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        SessionHeader(
          symbol: "dumbbell.fill", title: localizedDayName(session.dayName), subtitle: timeRange,
          caption: "Week \(session.week)")
        VStack(alignment: .leading, spacing: 10) {
          Text("Workout details").forgeSection()
          MetricGrid(items: detailItems)
          if session.sets.contains(where: { !$0.effortReported }) && !session.sets.isEmpty {
            // The RPE field is pre-filled from the plan, so most sets are never rated. A
            // dash here means "you didn't tell us", not "we lost it" — say which.
            Text(
              String(
                localized:
                  "RPE starts on your plan's target. Only sets you rated yourself count toward effort.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
            .accessibilityIdentifier("history.effortExplainer")
          }
          if !session.verified {
            Text(
              String(
                localized:
                  "Not counted for PRs, badges or Crew: sets came in too fast or a load jumped.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
          }
          if let context = equipmentContextLine {
            Text(context)
              .forgeCaption()
              .foregroundStyle(Theme.textSecondary)
          }
          if hasIncomparableInstances {
            Text(
              String(
                localized: "Loads on different equipment are kept as separate baselines.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        if !session.notes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Notes").forgeSection()
            Text(session.notes).forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }
        if !debrief.isEmpty {
          DebriefCard(debrief: debrief, coachName: coach.name, hasPR: !prs.isEmpty)
        }
        ForEach(orderedIDs, id: \.self) { id in
          if let exercise = ExerciseDB.find(id) {
            exerciseCard(
              exercise,
              sets: session.sets.filter { $0.exerciseID == id }.sorted { $0.setIndex < $1.setIndex }
            )
          }
        }
        if editing {
          Button(role: .destructive) {
            confirmDelete = true
          } label: {
            Text("Delete session")
              .forgeBody()
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .foregroundStyle(Theme.negative)
          .buttonStyle(.plain)
          .background(
            RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
              Theme.innerSurface))
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(localizedDayName(session.dayName))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(
          editing
            ? String(localized: "Done", bundle: L10n.bundle)
            : String(localized: "Edit", bundle: L10n.bundle)
        ) {
          if editing { editTracked = false }
          editing.toggle()
        }
        .bold()
        .accessibilityIdentifier("session.edit.toggle")
      }
    }
    .confirmationDialog(
      "Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button("Delete session", role: .destructive) {
        Analytics.track("session_deleted")
        Task { await deleteSession() }
      }
    }
    .sheet(item: $feedbackSet) { set in
      SetFeedbackSheet(
        set: set,
        exerciseName: ExerciseDB.find(set.exerciseID)?.localizedName ?? set.exerciseID,
        usesLb: profiles.first?.isLb(for: set.exerciseID) ?? usesLb,
        onSaved: { touch() })
    }
  }

  private func touch() {
    session.updatedAt = .now
    try? modelContext.save()
    if !editTracked {
      Analytics.track("set_edited")
      editTracked = true
    }
  }

  private func deleteSet(_ set: LoggedSet) {
    session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
    modelContext.delete(set)
    touch()
  }

  /// Tombstone + sync when signed in, then local delete. Shared by swipe-delete and the detail view.
  @MainActor static func delete(_ session: WorkoutSession, context: ModelContext) async {
    if AuthClient.shared.user != nil {
      session.tombstoned = true
      session.updatedAt = .now
      try? context.save()
      await SyncEngine.shared.sync()
    }
    context.delete(session)
    try? context.save()
  }

  @MainActor private func deleteSession() async {
    dismiss()
    await SessionDetailView.delete(session, context: modelContext)
  }

  private func exerciseCard(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    let lb = profiles.first?.isLb(for: exercise.id) ?? usesLb
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(exercise.localizedName).forgeBodyStrong()
        Spacer()
        if let best = sets.map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max() {
          HStack(spacing: 4) {
            Text("e1RM").forgeCaption()
            MetricValue(
              value: Fmt.num(UnitFormat.plain(best, usesLb: lb)), unit: lb ? "lb" : "kg", size: 16,
              color: Theme.accentValue)
          }
        }
      }
      ForEach(sets, id: \.persistentModelID) { set in
        if editing {
          EditSetRow(set: set, usesLb: lb, onChange: touch, onDelete: deleteSet)
        } else {
          HStack(spacing: 8) {
            Text(
              "\(Int(UnitFormat.plain(set.weightKg, usesLb: lb).rounded())) × \(set.reps) @ \(set.rpe, specifier: "%g")"
            )
            .forgeLabel()
            .monospacedDigit()
            if set.variant != "straight", let label = SetVariant(rawValue: set.variant)?.label {
              Text(label)
                .forge(11, .semibold)
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accentTint))
            }
            Spacer()
            Button {
              feedbackSet = set
            } label: {
              Image(systemName: set.setFeedback == nil ? "text.bubble" : "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(set.setFeedback == nil ? Theme.textTertiary : Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              set.setFeedback == nil
                ? String(
                  localized: "Add set feedback for set \(set.setIndex + 1)", bundle: L10n.bundle)
                : String(
                  localized: "Edit set feedback for set \(set.setIndex + 1)", bundle: L10n.bundle))
          }
        }
        if let note = SetFeedbackAnalysisPolicy.historyNote(for: set.setFeedback) {
          Text(note)
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

private struct EditSetRow: View {
  let set: LoggedSet
  let usesLb: Bool
  let onChange: () -> Void
  let onDelete: (LoggedSet) -> Void

  @State private var weightText = ""

  var body: some View {
    HStack(spacing: 10) {
      TextField(
        "Weight",
        text: Binding(
          get: { weightText },
          set: { text in
            weightText = text
            // ponytail: comma→dot parse only, no locale-aware grouping handling
            if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 {
              set.weightKg = usesLb ? Plates.lbToKg(v) : v
              onChange()
            }
          })
      )
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.center)
      .frame(width: 64)
      .innerSurface(padding: 8)
      .forgeLabel()
      Text(usesLb ? "lb" : "kg").forgeCaption()
      Stepper(
        value: Binding(
          get: { set.reps },
          set: {
            set.reps = $0
            onChange()
          }), in: 1...50
      ) {
        Text("\(set.reps) reps").forgeLabel().monospacedDigit().fixedSize()
      }
      Menu {
        ForEach([6.0, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10], id: \.self) { rpe in
          Button(Fmt.num(rpe)) {
            set.rpe = rpe
            onChange()
          }
        }
      } label: {
        Text("RPE \(Fmt.num(set.rpe))")
          .forgeLabel()
          .monospacedDigit()
          .innerSurface(padding: 8)
      }
      Button {
        onDelete(set)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(Theme.negative)
          .frame(width: 32, height: 32)
      }
    }
    .onAppear {
      if weightText.isEmpty { weightText = Fmt.num(UnitFormat.plain(set.weightKg, usesLb: usesLb)) }
    }
  }
}
