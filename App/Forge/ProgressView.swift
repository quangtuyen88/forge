import Charts
import ForgeCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query private var progressPhotos: [ProgressPhoto]
  @Query private var journeyProfiles: [JourneyPrivateProfile]
  @Environment(\.modelContext) private var modelContext
  @Environment(AuthClient.self) private var auth
  @State private var selectedLift = ""
  @State private var chartWindowWeeks = 8
  @State private var scrubDate: Date?
  @State private var selectedBadge: BadgeProgress?
  @State private var newBadgeToast: Badge?
  @AppStorage("badgesSeen") private var badgesSeen = ""
  /// Which Progress surface is showing: Overview or the Journey timeline. Device-local and
  /// remembered, so returning to the tab reopens the same one. Overview is the default.
  @AppStorage(JourneyPref.segmentKey) private var segment = JourneyPref.segmentOverview
  @State private var showJourneyProfile = false
  @State private var showSettings = false

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private func lbValue(_ kg: Double, id: String) -> Double {
    (profile?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  private func unit(for id: String) -> String {
    (profile?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }

  private var loggedExerciseIDs: [String] {
    Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).sorted()
  }

  /// Sets of `exerciseID` comparable with the most recent verified equipment context, so two
  /// incompatible verified instances never merge into one baseline. Falls back to all sets
  /// when there is no verified passport context (legacy history stays continuous).
  private func comparableSets(_ sets: [LoggedSet], exerciseID: String) -> [LoggedSet] {
    let pool = sets.filter { $0.exerciseID == exerciseID }
    let reference =
      pool
      .filter { $0.comparisonContext.normalizationStatus == .verified }
      .max(by: { $0.loggedAt < $1.loggedAt })
    guard let reference else { return pool }
    return pool.filter { $0.isComparableForBaseline(to: reference) }
  }

  /// Equipment context for the selected lift, when a verified passport instance was recorded.
  /// `nil` for legacy/imported loads, which stay unlabeled rather than guessed.
  private var selectedLiftEquipmentContext: String? {
    guard !selectedLift.isEmpty, let profile else { return nil }
    let sets = sessions.analysisSets(.trends).filter { $0.exerciseID == selectedLift }
    guard
      let reference = sets.first(where: { $0.comparisonContext.normalizationStatus == .verified }),
      let instanceID = reference.equipmentInstanceID
    else { return nil }
    let instance = profile.equipmentPassport.instance(id: instanceID)
    let gymName = instance?.gymProfileID.flatMap { gymID in
      profile.trainingConstraints.gymProfiles.first { $0.id == gymID }?.name
    }
    return [instance?.name ?? instanceID, gymName].compactMap { $0 }.joined(separator: " · ")
  }

  private var history: [E1RMPoint] {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return
      sessions
      .filter { $0.date > cutoff }
      .compactMap { session -> E1RMPoint? in
        let best = comparableSets(session.analysisSets(.trends), exerciseID: selectedLift)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
          .max()
        guard let best else { return nil }
        return E1RMPoint(date: session.date, e1rm: best)
      }
      .sorted { $0.date < $1.date }
  }

  private var weekVolume: [Muscle: Double] {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    let entries: [(exercise: Exercise, set: SetLog)] =
      sessions
      .filter { $0.date > cutoff }
      .flatMap { session in
        session.analysisSets(.trends).compactMap { set in
          ExerciseDB.find(set.exerciseID).map { exercise in
            (
          exercise: exercise,
          set: SetLog(
            weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
            effortReported: set.effortReported)
        )
          }
        }
      }
    return Volume.weeklySets(entries)
  }

  private var csvURL: URL {
    let rows =
      sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map {
            "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)"
          }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: Theme.groupGap) {
          privateHeader
          segmentPicker
        }
        .padding(.horizontal, Theme.margin)

        if isTimeline {
          JourneyTimelineView(usesLb: usesLb)
        } else {
          overview
        }
      }
      .background(Theme.page)
      .navigationTitle("My Progress")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showSettings = true
          } label: {
            Text("Settings")
          }
          .accessibilityIdentifier("progress.settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            HistoryView(usesLb: usesLb)
          } label: {
            Image(systemName: "clock.arrow.circlepath")
          }
          .accessibilityLabel("History")
          .accessibilityIdentifier("progress.history")
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: csvURL) { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("Export CSV")
        }
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
      }
      .sheet(isPresented: $showJourneyProfile) {
        if let profile {
          JourneyPrivateProfileSheet(
            repository: JourneyRepository(
              context: modelContext, profile: profile, accountID: auth.user?.id))
        }
      }
      .onAppear {
        if selectedLift.isEmpty { selectedLift = loggedExerciseIDs.first ?? "" }
        celebrateNewBadges()
      }
      .overlay(alignment: .top) {
        if let badge = newBadgeToast {
          HStack(spacing: 8) {
            Image(systemName: badge.symbol)
            Text("New badge · \(badge.title)")
          }
          .forge(13, .semibold)
          .foregroundStyle(Theme.onAccent)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Capsule().fill(Theme.accent))
          .shadow(color: Theme.shadow, radius: 12, y: 4)
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
          .task(id: badge) {
            try? await Task.sleep(for: .seconds(3))
            if newBadgeToast == badge { newBadgeToast = nil }
          }
        }
      }
      .animation(.spring(duration: 0.3), value: newBadgeToast)
    }
  }

  private var isTimeline: Bool { segment == JourneyPref.segmentTimeline }

  /// The overview this tab has always shown: same cards, same order, same margins.
  private var overview: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        statTiles
        // Recent sessions and the tools that open recorded data come first, so a thin or
        // empty chart never buries what the lifter can actually act on.
        analyticsGrid
        trendsCard
        weeklySetsCard
        strengthCard
        volumeLoadCard
        volumeCard
        calendarCard
        awardsCard
      }
      .padding(.horizontal, Theme.margin)
    }
  }

  /// The compact private header. It states what the timeline calls the lifter, the active
  /// training goal, and how far the recorded log actually reaches — never a start date inferred
  /// from the first workout — and it opens the editor that sets the name and explicit start.
  private var privateHeader: some View {
    Button {
      showJourneyProfile = true
    } label: {
      HStack(alignment: .center, spacing: 12) {
        ZStack {
          Circle().fill(Theme.accentTint)
          Image(systemName: "person.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(journeyProfileName).forgeBodyStrong().lineLimit(1)
          if let goalText {
            Text(goalText)
              .forgeCaption()
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let recordsSinceText {
            Text(recordsSinceText)
              .forgeCaption()
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let startedTrainingText {
            Text(startedTrainingText)
              .forgeCaption()
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.card)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .stroke(Theme.ring, lineWidth: 0.7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(headerAccessibilityLabel)
    .accessibilityHint("Opens your private profile")
    .accessibilityIdentifier("journey.privateHeader")
  }

  /// The stored identity card for this owner, matched on the exact owner rule the repository
  /// uses — the signed-in account id when present, otherwise the device-local owner id — so a
  /// card written under a different spelling is still found and `profile.remoteID` is never used.
  private var journeyProfileRecord: JourneyPrivateProfile? {
    let account = JourneyEventID.canonicalOwner(auth.user?.id ?? "")
    let local = JourneyEventID.canonicalOwner(profile?.journeyLocalOwnerID ?? "")
    let owner = !account.isEmpty ? account : local
    guard !owner.isEmpty else { return nil }
    return journeyProfiles.first { $0.ownerID == owner }
  }

  private var journeyProfileName: String {
    guard let record = journeyProfileRecord, !record.displayName.isEmpty else {
      return String(localized: "Private profile", bundle: L10n.bundle)
    }
    return record.displayName
  }

  /// `Current goal: …`, exactly the active training goal. No goal is ever invented: without a
  /// profile the line is omitted.
  private var goalText: String? {
    guard let profile else { return nil }
    let goal =
      Goal(rawValue: profile.goal)?.name
      ?? String(localized: "Training", bundle: L10n.bundle)
    return String(localized: "Current goal: \(goal)", bundle: L10n.bundle)
  }

  /// The header read as one VoiceOver element: name, goal, the reach of the recorded log, and
  /// the explicit start date when the lifter set one.
  private var headerAccessibilityLabel: String {
    var parts = [journeyProfileName]
    if let goalText { parts.append(goalText) }
    if let recordsSinceText { parts.append(recordsSinceText) }
    if let startedTrainingText { parts.append(startedTrainingText) }
    return parts.joined(separator: ", ")
  }

  /// `Training records since {month year}`, derived from the earliest completed, non-deleted
  /// workout — the log's actual reach, not a chosen start date. `nil` when no workout exists.
  private var recordsSinceText: String? {
    guard
      let earliest =
        sessions
        .filter({ $0.completed && !$0.tombstoned })
        .min(by: { $0.date < $1.date })
    else { return nil }
    let date = earliest.date.formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    return String(localized: "Training records since \(date)", bundle: L10n.bundle)
  }

  /// `Started training {month year}`, only when the lifter explicitly supplied a start date.
  private var startedTrainingText: String? {
    guard let start = journeyProfileRecord?.trainingStartDate else { return nil }
    let date = start.formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    return String(localized: "Started training \(date)", bundle: L10n.bundle)
  }

  /// Overview or Timeline. Remembered per device, Overview by default; the timeline keeps its
  /// own month, filter and scroll anchor, so switching back and forth does not lose a place.
  private var segmentPicker: some View {
    Picker("View", selection: $segment) {
      Text("Overview").tag(JourneyPref.segmentOverview)
      Text("Timeline").tag(JourneyPref.segmentTimeline)
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("journey.segment")
  }

  private var verifiedSessions: [WorkoutSession] { sessions.filter(\.verified) }

  private var streak: Int { streakWeeks(sessions: verifiedSessions) }

  /// One definition, shared with Balance and History via `analysisEligibleSessions`.
  private var totalWorkouts: Int { sessions.analysisEligibleSessions.count }

  /// Lifetime tonnage over completed, verified sessions, kg.
  private var lifetimeTonnageKg: Double {
    verifiedSessions
      .filter(\.completed)
      .flatMap { $0.analysisSets(.achievements) }
      .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  /// Exercises whose per-session best e1RM strictly improved over an earlier verified session's best.
  private var prCount: Int {
    var bests: [String: Double] = [:]
    var improved: Set<String> = []
    for session in verifiedSessions.filter(\.completed).sorted(by: { $0.date < $1.date }) {
      var sessionBests: [String: Double] = [:]
      for id in Set(session.analysisSets(.achievements).map(\.exerciseID)) {
        let best = comparableSets(session.analysisSets(.achievements), exerciseID: id)
          .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
        if let best { sessionBests[id] = best }
      }
      for (id, e) in sessionBests {
        if e > (bests[id] ?? 0), bests[id] != nil { improved.insert(id) }
        bests[id] = max(bests[id] ?? 0, e)
      }
    }
    return improved.count
  }

  private var earnedBadges: [Badge] {
    Badges.earned(
      sessions: totalWorkouts,
      streakWeeks: streak,
      tonnageKg: lifetimeTonnageKg,
      prCount: prCount)
  }

  private var badgeProgress: [BadgeProgress] {
    Badges.progress(
      sessions: totalWorkouts, streakWeeks: streak, tonnageKg: lifetimeTonnageKg, prCount: prCount)
  }

  private var nextBadges: [BadgeProgress] {
    badgeProgress.filter { !earnedBadges.contains($0.badge) }
      .sorted { ($0.fraction, -Double($0.target)) > ($1.fraction, -Double($1.target)) }
  }

  private var awardsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink {
        AwardsView(earned: earnedBadges, progress: badgeProgress)
      } label: {
        HStack(spacing: 6) {
          Text("Awards").forgeSection()
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
          Spacer()
          Text("\(earnedBadges.count) of \(Badge.allCases.count)").forgeCaption().monospacedDigit()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      if let next = nextBadges.first {
        NextBadgeRow(
          symbol: next.badge.symbol, title: next.badge.title, progress: next.progress,
          target: next.target)
      }
      if !earnedBadges.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 14) {
            ForEach(earnedBadges, id: \.rawValue) { badge in
              Button {
                selectedBadge = badgeProgress.first { $0.badge == badge }
              } label: {
                VStack(spacing: 6) {
                  Medallion(symbol: badge.symbol, size: 56)
                  Text(badge.title).forgeCaption().lineLimit(1)
                }
                .frame(width: 80)
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel("\(badge.title), earned")
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(item: $selectedBadge) { BadgeDetailView(progress: $0, earned: true) }
  }

  /// One-time toast for badges earned since `badgesSeen` was last updated.
  private func celebrateNewBadges() {
    let seen = Set(badgesSeen.split(separator: ",").map(String.init))
    let earnedSet = Set(earnedBadges.map(\.rawValue))
    let fresh = Badge.allCases.filter {
      earnedSet.contains($0.rawValue) && !seen.contains($0.rawValue)
    }
    guard !fresh.isEmpty else { return }
    newBadgeToast = fresh.first
    badgesSeen = earnedSet.sorted().joined(separator: ",")
  }

  /// Progress reads analysis-eligible sets only — every tile here is scoped and says so,
  /// so it can never be read as the all-recorded totals Today shows.
  private var eligibleScope: MetricScopeDescriptor {
    MetricScopePolicy.descriptor(for: .analysisEligible)
  }

  /// Sets the lifter's own feedback keeps out of these numbers. Said plainly, once, so a smaller
  /// total is never mistaken for missing work.
  private var excludedNote: String? {
    let out = max(sessions.excludedSetCount(.trends), sessions.excludedSetCount(.achievements))
    guard out > 0 else { return nil }
    return String(
      localized:
        "\(out) set\(L10n.pluralSuffix(out)) you marked are left out of these charts and awards — they stay in History as recorded.",
      bundle: L10n.bundle)
  }

  private var statTiles: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(eligibleScope.label)
        .forgeLabel()
        .foregroundStyle(Theme.textSecondary)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        StatTile(
          symbol: "flame.fill", value: "\(streak)", unit: "wk",
          label: String(localized: "streak", bundle: L10n.bundle), tint: Theme.metricTime
        )
        .accessibilityElement(children: .combine)
        StatTile(
          symbol: "dumbbell", value: "\(totalWorkouts)",
          label: String(localized: "workouts", bundle: L10n.bundle), tint: Theme.metricSets
        )
        .accessibilityElement(children: .combine)
        StatTile(
          symbol: "scalemass", value: weekTonnageNumber, unit: weekTonnageUnit,
          label: String(localized: "volume 7d", bundle: L10n.bundle), tint: Theme.metricLoad
        )
        .accessibilityElement(children: .combine)
        StatTile(
          symbol: "trophy.fill", value: bestE1RMNumber, unit: unit,
          label: String(localized: "best e1RM", bundle: L10n.bundle), tint: Theme.metricLoad
        )
        .accessibilityElement(children: .combine)
      }
      Text(eligibleScope.caption)
        .forgeCaption()
        .foregroundStyle(Theme.textTertiary)
      if let excludedNote {
        Text(excludedNote)
          .forgeCaption()
          .foregroundStyle(Theme.textTertiary)
      }
    }
  }

  private var weekTonnageKg7d: Double {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    return
      sessions
      .filter { $0.date > cutoff }
      .flatMap { $0.analysisSets(.trends) }
      .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
  }

  private var weekTonnageNumber: String {
    usesLb
      ? String(format: "%.0fk", Plates.kgToLb(weekTonnageKg7d) / 1000)
      : Fmt.num(weekTonnageKg7d / 1000)
  }

  private var weekTonnageUnit: String { usesLb ? "lb" : "t" }

  private var bestE1RMNumber: String {
    let best = sessions.analysisSets(.achievements)
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    guard let best else { return "—" }
    let value = usesLb ? Plates.kgToLb(best) : best
    return "\(Int(value.rounded()))"
  }

  private struct Trend: Identifiable {
    let id: String
    let label: String
    let value: String
    let unit: String?
    let direction: TrendDirection
    let detail: String?
    let color: Color
  }

  private var trends: [Trend] {
    let now = Date.now
    let recentStart = now.addingTimeInterval(-28 * 86400)
    let priorStart = now.addingTimeInterval(-84 * 86400)
    let completed = sessions.filter(\.completed)
    let recentSessions = completed.filter { $0.date > recentStart }
    guard !recentSessions.isEmpty else { return [] }
    let priorSessions = completed.filter { $0.date > priorStart && $0.date <= recentStart }
    let priorHasData = !priorSessions.isEmpty

    var result: [Trend] = []

    let recentSessionsPerWeek = Double(recentSessions.count) / 4
    let priorSessionsPerWeek = Double(priorSessions.count) / 8
    result.append(
      Trend(
        id: "sessions",
        label: String(localized: "Sessions per week", bundle: L10n.bundle),
        value: Fmt.num(recentSessionsPerWeek),
        unit: "/wk",
        direction: priorHasData ? dir(recentSessionsPerWeek, priorSessionsPerWeek, 0.25) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.num(priorSessionsPerWeek))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricSets))

    let recentSetsPerWeek =
      Double(recentSessions.flatMap { $0.analysisSets(.trends) }.filter { $0.rpe >= 6 }.count) / 4
    let priorSetsPerWeek =
      Double(priorSessions.flatMap { $0.analysisSets(.trends) }.filter { $0.rpe >= 6 }.count) / 8
    result.append(
      Trend(
        id: "sets",
        label: String(localized: "Sets per week", bundle: L10n.bundle),
        value: Fmt.num(recentSetsPerWeek),
        unit: "/wk",
        direction: priorHasData ? dir(recentSetsPerWeek, priorSetsPerWeek, 2) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.num(priorSetsPerWeek))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricSets))

    func tonnage(_ list: [WorkoutSession]) -> Double {
      list.flatMap { $0.analysisSets(.trends) }.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }
    let recentTonnagePerWeek = tonnage(recentSessions) / 4
    let priorTonnagePerWeek = tonnage(priorSessions) / 8
    let recentTonnageDisplay = usesLb ? Plates.kgToLb(recentTonnagePerWeek) : recentTonnagePerWeek
    let priorTonnageDisplay = usesLb ? Plates.kgToLb(priorTonnagePerWeek) : priorTonnagePerWeek
    result.append(
      Trend(
        id: "tonnage",
        label: String(localized: "Tonnage per week", bundle: L10n.bundle),
        value: Fmt.grouped(recentTonnageDisplay),
        unit: "\(unit)/wk",
        direction: priorHasData ? relDir(recentTonnagePerWeek, priorTonnagePerWeek, 0.05) : .flat,
        detail: priorHasData
          ? String(localized: "was \(Fmt.grouped(priorTonnageDisplay))", bundle: L10n.bundle)
          : String(localized: "Log 8 more weeks to compare", bundle: L10n.bundle),
        color: Theme.metricLoad))

    let recentCounts = Dictionary(
      grouping: recentSessions.flatMap { $0.analysisSets(.trends) }, by: \.exerciseID
    ).mapValues(\.count)
    for (id, _) in recentCounts.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }).prefix(3) {
      let name = ExerciseDB.find(id)?.localizedName ?? id
      let recentBest = recentSessions.flatMap { $0.analysisSets(.trends) }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      let priorBest = priorSessions.flatMap { $0.analysisSets(.trends) }
        .filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
        .max()
      guard let recentBest else { continue }
      let bestDisplay = lbValue(recentBest, id: id)
      if let priorBest {
        let priorDisplay = lbValue(priorBest, id: id)
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: unit(for: id),
            direction: relDir(recentBest, priorBest, 0.01),
            detail: "was \(Fmt.num(priorDisplay))",
            color: Theme.metricLoad))
      } else {
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: unit(for: id),
            direction: .flat,
            detail: String(localized: "Log it 8 more weeks to compare", bundle: L10n.bundle),
            color: Theme.metricLoad))
      }
    }
    return result
  }

  private func dir(_ recent: Double, _ prior: Double, _ threshold: Double) -> TrendDirection {
    if recent - prior >= threshold { return .up }
    if recent - prior <= -threshold { return .down }
    return .flat
  }

  private func relDir(_ recent: Double, _ prior: Double, _ fraction: Double) -> TrendDirection {
    guard prior > 0 else { return recent > 0 ? .up : .flat }
    if recent / prior >= 1 + fraction { return .up }
    if recent / prior <= 1 - fraction { return .down }
    return .flat
  }

  private func trendSymbol(_ id: String) -> String {
    switch id {
    case "sessions": return "calendar.badge.checkmark"
    case "sets": return "checkmark.circle.fill"
    case "tonnage": return "scalemass.fill"
    default: return "dumbbell.fill"
    }
  }
  private var trendsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Trends").forgeSection()
        Spacer()
        Text("4 weeks vs the 8 before").forgeCaption()
      }
      if trends.isEmpty {
        Text("Log four sessions to see trends.").forgeLabel()
      } else {
        ForEach(trends) { t in
          TrendRow(
            direction: t.direction, label: t.label, value: t.value, unit: t.unit, detail: t.detail,
            valueColor: t.color, metricSymbol: trendSymbol(t.id))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var mesoBlockCount: Int {
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    guard !completed.isEmpty else { return 0 }
    return 1 + zip(completed, completed.dropFirst()).filter { $0.1.week < $0.0.week }.count
  }

  private var latestWeight: String? {
    measurements.first(where: { ($0.weightKg ?? 0) > 0 })?.weightKg
      .map { UnitFormat.weight($0, usesLb: usesLb) }
  }

  private var analyticsGrid: some View {
    VStack(spacing: 10) {
      NavigationLink {
        HistoryView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "clock.fill", title: "History", subtitle: "\(totalWorkouts) eligible sessions",
          color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.history.row")
      NavigationLink {
        PlanAuditView()
      } label: {
        TrainingToolRow(
          symbol: "stethoscope", title: "Plan audit", subtitle: "What is working and what changed",
          color: Theme.metricSets)
      }
      .accessibilityIdentifier("progress.planAudit")
      NavigationLink {
        RecoveryReportView()
      } label: {
        TrainingToolRow(
          symbol: "bolt.heart.fill", title: "Recovery",
          subtitle: "Recorded inputs and 7-day coverage", color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.recovery")
      NavigationLink {
        TrainingExperimentsView()
      } label: {
        TrainingToolRow(
          symbol: "flask.fill", title: "Experiments",
          subtitle: profile?.trainingExperiment == nil ? "Test one change" : "4-week protocol",
          color: Theme.metricLoad)
      }
      .accessibilityIdentifier("progress.experiments")
      NavigationLink {
        RecommendationEffectivenessView()
      } label: {
        TrainingToolRow(
          symbol: "chart.bar.fill", title: "Recommendation effectiveness",
          subtitle: "What was proposed, applied and measured", color: Theme.metricLoad)
      }
      .accessibilityIdentifier("progress.recommendations")
      NavigationLink {
        PRBoardView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "trophy.fill", title: "PR board",
          subtitle: "\(loggedExerciseIDs.count) lifts with eligible records",
          color: Theme.metricSets)
      }
      .accessibilityIdentifier("progress.prBoard")
      NavigationLink {
        BalanceRadarView()
      } label: {
        TrainingToolRow(
          symbol: "circle.hexagongrid.fill", title: "Balance",
          subtitle: "Push, pull, legs and evidence coverage", color: Theme.metricLoad)
      }
      .accessibilityIdentifier("progress.balance")
      NavigationLink {
        MesoHistoryView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "square.stack.3d.up.fill", title: "Mesocycles",
          subtitle: "\(mesoBlockCount) recorded blocks", color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.mesocycles")
      NavigationLink {
        NutritionView()
      } label: {
        TrainingToolRow(
          symbol: "fork.knife", title: "Fuel", subtitle: "Calories, macros and daily guidance",
          color: Theme.metricEffort)
      }
      .accessibilityIdentifier("progress.fuel")
      NavigationLink {
        MeasurementsView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "scalemass", title: "Body stats",
          subtitle: latestWeight.map { LocalizedStringKey($0) } ?? "No measurements yet",
          color: Theme.metricSets)
      }
      .accessibilityIdentifier("progress.bodyStats")
      NavigationLink {
        ProgressPhotosView()
      } label: {
        TrainingToolRow(
          symbol: "camera.fill", title: "Photos",
          subtitle: progressPhotos.isEmpty
            ? "Private progress photos" : "\(progressPhotos.count) private photos",
          color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.photos")
      ShareLink(
        item: ReportPDF.url(sessions: sessions, profile: profile),
        preview: SharePreview("Training report")
      ) {
        TrainingToolRow(
          symbol: "doc.fill", title: "PDF report", subtitle: "One-page training summary",
          color: Theme.textSecondary, showsChevron: false)
      }
    }
  }

  /// Sessions with a date in the last 12 weeks, for the consistency heat map label.
  private var sessions12Weeks: Int {
    let cutoff = Date.now.addingTimeInterval(-12 * 7 * 86400)
    return sessions.filter { $0.date > cutoff }.count
  }

  private var calendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Consistency").forgeSection()
      CalendarHeat(sessions: sessions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 12 weeks, \(sessions12Weeks) sessions")
      HStack(spacing: 6) {
        Text("Last 12 weeks").forgeCaption()
        Spacer()
        Text("Less").forgeCaption()
        ForEach(0..<5) {
          RoundedRectangle(cornerRadius: 2).fill(Theme.ramp[$0])
            .frame(width: 10, height: 10)
        }
        Text("More").forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var strengthCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      if loggedExerciseIDs.isEmpty {
        emptyStrength
      } else {
        HStack {
          Text("Strength").forgeSection()
          Spacer()
          Picker("Lift", selection: $selectedLift) {
            ForEach(loggedExerciseIDs, id: \.self) { id in
              Text(ExerciseDB.find(id)?.localizedName ?? id).tag(id)
            }
          }
          .pickerStyle(.menu)
        }
        if let context = selectedLiftEquipmentContext {
          Label(context, systemImage: "dumbbell.fill")
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        }
        if !history.isEmpty {
          HStack(alignment: .firstTextBaseline) {
            MetricValue(
              value: currentDisplay, unit: unit(for: selectedLift), size: 28,
              color: Theme.metricLoad)
            if let delta = deltaDisplay {
              Text(delta).foregroundStyle(delta.hasPrefix("+") ? Theme.positive : Theme.negative)
                .forgeCaption()
                .monospacedDigit()
            }
            Spacer()
            if Strength.isPlateaued(history, asOf: .now) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.metricEffort)
            }
          }
          Chart {
            ForEach(history, id: \.self) { point in
              LineMark(
                x: .value("Date", point.date),
                y: .value("e1RM", lbValue(point.e1rm, id: selectedLift))
              )
              .foregroundStyle(Theme.metricLoad)
              .interpolationMethod(.catmullRom)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              if point == history.last {
                PointMark(
                  x: .value("Date", point.date),
                  y: .value("e1RM", lbValue(point.e1rm, id: selectedLift))
                )
                .symbolSize(70)
                .symbol {
                  Circle().fill(Theme.accent)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .frame(width: 10, height: 10)
                }
              }
            }
            if let scrubDate, let point = history.first(where: { $0.date == scrubDate }) {
              RuleMark(x: .value("Date", point.date))
                .foregroundStyle(Theme.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center) {
                  ChartCallout(
                    value:
                      "\(formatDisplay(lbValue(point.e1rm, id: selectedLift))) \(unit(for: selectedLift))",
                    caption: point.date.formatted(.dateTime.month().day().locale(L10n.locale)))
                }
            }
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(
                Theme.ring)
              AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing) {
              AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(
                Theme.ring)
              AxisValueLabel()
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartOverlay { proxy in
            GeometryReader { geo in
              Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                  LongPressGesture(minimumDuration: 0.15)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                      guard case .second(true, let drag?) = value else { return }
                      guard let plotFrame = proxy.plotFrame else { return }
                      let x = drag.location.x - geo[plotFrame].origin.x
                      if let date: Date = proxy.value(atX: x) {
                        scrubDate =
                          history.min(by: {
                            abs($0.date.timeIntervalSince(date))
                              < abs($1.date.timeIntervalSince(date))
                          })?.date
                      }
                    }
                    .onEnded { _ in scrubDate = nil })
            }
          }
          .frame(height: 180)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "\(liftName) estimated one-rep max \(currentDisplay) \(unit(for: selectedLift))")
          if history.count < 3 {
            Text(
              String(
                localized: "Log \(liftName) \(3 - history.count) more times to see a trend.",
                bundle: L10n.bundle)
            ).forgeCaption()
          }
        } else {
          Text("No \(liftName) in the last 12 weeks.").forgeLabel()
        }
        if !topLifts.isEmpty {
          Divider()
          Text("PRs").forgeSection()
          ForEach(topLifts, id: \.exercise.id) { lift in
            HStack(spacing: 12) {
              EquipmentThumb(equipment: lift.exercise.equipment, size: 32)
                .accessibilityHidden(true)
              Text(lift.exercise.localizedName).forgeBodyStrong()
              Spacer()
              Text(
                "\(formatDisplay(lbValue(lift.best, id: lift.exercise.id))) \(unit(for: lift.exercise.id))"
              )
              .forgeLabel()
              .monospacedDigit()
              .bold()
            }
          }
        }
      }
    }
    .card()
  }

  private var liftName: String {
    ExerciseDB.find(selectedLift)?.localizedName ?? selectedLift
  }

  private var topLifts: [(exercise: Exercise, best: Double)] {
    var bests: [String: Double] = [:]
    for s in sessions where s.completed {
      for set in s.analysisSets(.achievements) {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return
      bests
      .compactMap { id, best in ExerciseDB.find(id).map { (exercise: $0, best: best) } }
      .sorted { $0.best > $1.best }
      .prefix(5).map { $0 }
  }

  private var currentDisplay: String {
    guard let best = history.last?.e1rm else { return "—" }
    return formatDisplay(lbValue(best, id: selectedLift))
  }

  private var deltaDisplay: String? {
    guard let current = history.last else { return nil }
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    guard let prior = history.last(where: { $0.date <= cutoff }), prior.e1rm != current.e1rm else {
      return nil
    }
    let delta = lbValue(current.e1rm, id: selectedLift) - lbValue(prior.e1rm, id: selectedLift)
    return "\(delta > 0 ? "+" : "−")\(Fmt.num(abs(delta))) \(unit(for: selectedLift))"
  }

  private var emptyStrength: some View {
    VStack(spacing: 8) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No lifts yet").forgeSection()
      Text("Finish a workout to see your e1RM trend.")
        .forgeLabel()
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  private struct WeekSets: Identifiable {
    let start: Date
    let sets: Int
    let isCurrent: Bool
    var id: Date { start }
  }

  private var weeklySetCounts: [WeekSets] {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<chartWindowWeeks).compactMap { i in
      guard
        let start = cal.date(byAdding: .weekOfYear, value: i - (chartWindowWeeks - 1), to: thisWeek)
      else { return nil }
      let sets =
        sessions
        .filter { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start == start }
        .flatMap { $0.analysisSets(.trends) }
        .filter { $0.rpe >= 6 }
        .count
      return WeekSets(start: start, sets: sets, isCurrent: i == chartWindowWeeks - 1)
    }
  }

  private var weeklySetsCard: some View {
    let data = weeklySetCounts
    let current = data.last?.sets ?? 0
    let average = Double(data.map(\.sets).reduce(0, +)) / Double(max(data.count, 1))
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Weekly sets").forgeSection()
          MetricValue(value: "\(current)", unit: "sets", size: 32, color: Theme.metricSets)
          Text("This week · avg \(Fmt.num(average))").forgeCaption().monospacedDigit()
        }
        Spacer()
      }
      Picker("Range", selection: $chartWindowWeeks) {
        Text("4W").tag(4)
        Text("8W").tag(8)
        Text("12W").tag(12)
      }
      .pickerStyle(.segmented)
      Chart {
        ForEach(data) { week in
          BarMark(
            x: .value("Week", week.start, unit: .weekOfYear),
            y: .value("Sets", week.sets),
            width: .ratio(0.56)
          )
          .foregroundStyle(Theme.metricSets.opacity(week.isCurrent ? 1 : 0.58))
          .cornerRadius(3)
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear, count: max(1, chartWindowWeeks / 4))) {
          AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
            .font(.forge(10, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine().foregroundStyle(Theme.ring)
          AxisValueLabel().font(.forge(10, .medium)).foregroundStyle(Theme.textTertiary)
        }
      }
      .chartPlotStyle { plot in
        plot.background(Theme.innerSurface.opacity(0.32))
          .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      }
      .frame(height: 164)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Weekly sets, \(current) this week, \(chartWindowWeeks) week chart")
    }
    .card()
  }

  private struct WeekLoad: Identifiable {
    let start: Date
    let kg: Double
    let isCurrent: Bool
    var id: Date { start }
  }

  private var weeklyLoads: [WeekLoad] {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<chartWindowWeeks).compactMap { i in
      guard
        let start = cal.date(byAdding: .weekOfYear, value: i - (chartWindowWeeks - 1), to: thisWeek)
      else { return nil }
      let kg =
        sessions
        .filter { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start == start }
        .flatMap { $0.analysisSets(.trends) }
        .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
      return WeekLoad(start: start, kg: kg, isCurrent: i == chartWindowWeeks - 1)
    }
  }

  private var volumeLoadCard: some View {
    let currentKg = weeklyLoads.last?.kg ?? 0
    let display = usesLb ? Plates.kgToLb(currentKg) : currentKg
    let compact = display >= 1_000
    let headline = compact ? Fmt.num(display / 1_000) : Fmt.grouped(display)
    let displayUnit = compact ? "k \(unit)" : unit
    return VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Volume load").forgeSection()
        MetricValue(value: headline, unit: displayUnit, size: 32, color: Theme.metricLoad)
        Text("This week · total tonnage").forgeCaption()
      }
      Picker("Range", selection: $chartWindowWeeks) {
        Text("4W").tag(4)
        Text("8W").tag(8)
        Text("12W").tag(12)
      }
      .pickerStyle(.segmented)
      Chart(weeklyLoads) { week in
        BarMark(
          x: .value("Week", week.start, unit: .weekOfYear),
          y: .value("Tonnage", usesLb ? Plates.kgToLb(week.kg) : week.kg),
          width: .ratio(0.56)
        )
        .foregroundStyle(Theme.metricLoad.opacity(week.isCurrent ? 1 : 0.58))
        .cornerRadius(3)
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear, count: max(1, chartWindowWeeks / 4))) {
          AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
            .font(.forge(10, .medium))
            .foregroundStyle(Theme.textTertiary)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing) {
          AxisGridLine().foregroundStyle(Theme.ring)
          AxisValueLabel().font(.forge(10, .medium)).foregroundStyle(Theme.textTertiary)
        }
      }
      .chartPlotStyle { plot in
        plot.background(Theme.innerSurface.opacity(0.32))
          .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      }
      .frame(height: 164)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Volume load, \(Fmt.grouped(display)) \(unit) this week, \(chartWindowWeeks) week chart")
    }
    .card()
  }

  private var volumeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("This week").forgeSection()
        Spacer()
        Text("sets per muscle").forgeCaption()
      }
      MuscleMapView(intensity: weekIntensity)
        .frame(height: 220)
        .frame(maxWidth: .infinity)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) {
          muscle in
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
      Text(muscle.a11yName).forgeCaption()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(muscle.a11yName), \(Int((weekVolume[muscle] ?? 0).rounded())) sets this week, target \(l.mrv)"
    )
  }

  private var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekVolume[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }

  private func formatDisplay(_ value: Double) -> String {
    Fmt.num(value)
  }

  private func streakWeeks(sessions: [WorkoutSession]) -> Int {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
    let weeks = Set(
      sessions.filter(\.completed).compactMap {
        cal.dateInterval(of: .weekOfYear, for: $0.date)?.start
      })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }
}

private struct TrainingToolRow: View {
  let symbol: String
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  let color: Color
  var showsChevron = true

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        Text(subtitle).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).stroke(
        Theme.ring, lineWidth: 0.7)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

struct AnalyticTile: View {
  let symbol: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Theme.accentTint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(subtitle).forgeCaption()
      }
      Spacer()
    }
    .card()
    .contentShape(Rectangle())
  }
}
