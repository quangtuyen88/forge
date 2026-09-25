import ForgeCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var journeyProfiles: [JourneyPrivateProfile]
  @Environment(\.modelContext) private var modelContext
  @Environment(AuthClient.self) private var auth
  @State private var newBadgeToast: Badge?
  @AppStorage("badgesSeen") private var badgesSeen = ""
  /// Which Progress surface is showing: Overview or the Journey timeline. Device-local and
  /// remembered, so returning to the tab reopens the same one. Overview is the default.
  @AppStorage(JourneyPref.segmentKey) private var segment = JourneyPref.segmentOverview
  @State private var showJourneyProfile = false
  @State private var showSettings = false
  @State private var showReports = false

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }
  private var facts: ProgressFacts { ProgressFacts(sessions: sessions, profile: profile) }

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
            Image(systemName: "gearshape")
          }
          .accessibilityLabel("Settings")
          .accessibilityIdentifier("progress.settings")
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

  /// The Overview: the week at a glance, highlights, the two data destinations, trends and the
  /// explore rows. Everything the old Overview showed is one tap away in a detail screen.
  private var overview: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        weekCard
        Text("Highlights")
          .forgeSection()
          .frame(maxWidth: .infinity, alignment: .leading)
        // Plain HStacks, not LazyVGrids: a second lazy grid in this stack never reached the
        // accessibility tree, so VoiceOver and UI tests could not find its cards.
        HStack(alignment: .top, spacing: 12) {
          consistencyCard.frame(maxWidth: .infinity)
          bestLiftCard.frame(maxWidth: .infinity)
        }
        HStack(alignment: .top, spacing: 12) {
          historyCard.frame(maxWidth: .infinity)
          prBoardCard.frame(maxWidth: .infinity)
        }
        trendsSection
        Text("Explore")
          .forgeSection()
          .frame(maxWidth: .infinity, alignment: .leading)
        exploreCard
        footnote
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
  }

  // MARK: This week

  private var weekToDate: TrainingMetrics.WeekToDate {
    TrainingMetrics.weekToDate(
      sessions.metricSets(scopes: [.trends]), now: .now, calendar: TrainingMetrics.reportingCalendar(),
      scope: .analysisEligible, coverageStart: sessions.coverageStart)
  }

  private var weekCard: some View {
    let wtd = weekToDate
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 1) {
          Text("This week").forge(17, .semibold).foregroundStyle(Theme.text)
          Text(weekRangeText(wtd.start)).forgeLabel()
        }
        Spacer(minLength: 8)
        NavigationLink {
          ProgressVolumeView(usesLb: usesLb)
        } label: {
          HStack(spacing: 2) {
            Text("Details").forge(15, .medium).foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Theme.accent)
              .accessibilityHidden(true)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("progress.weekDetails")
        .accessibilityLabel(weekSummaryLabel(wtd))
      }
      MetricValue(
        value: weekTonnageText(wtd.volume), unit: weekTonnageUnit, size: 44,
        color: Theme.metricLoad)
      Text("volume lifted so far").forgeLabel()
      if wtd.previousCovered {
        comparisonRow(wtd)
      }
      weeklyTotals
      Divider()
      musclesRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 16)
  }

  /// The reporting week so far ("Mon 21 – Thu 24 Sep"), in the reader's own date order.
  private func weekRangeText(_ start: Date) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = L10n.locale
    formatter.dateTemplate = "EEEdMMM"
    return formatter.string(from: start, to: .now)
  }

  private func weekTonnageText(_ kg: Double) -> String {
    usesLb ? String(format: "%.0fk", Plates.kgToLb(kg) / 1000) : Fmt.num(kg / 1000)
  }

  private var weekTonnageUnit: String { usesLb ? "lb" : "t" }

  /// The signed week-over-week chip: "+2,2 t" with the arrow the direction demands.
  private func comparisonRow(_ wtd: TrainingMetrics.WeekToDate) -> some View {
    let diff = wtd.volume - wtd.previousVolume
    let up = diff >= 0
    let value =
      usesLb
      ? String(format: "%.0fk", Plates.kgToLb(abs(diff)) / 1000)
      : Fmt.num(abs(diff) / 1000)
    let text = "\(value) \(weekTonnageUnit)"
    return HStack(spacing: 6) {
      HStack(spacing: 2) {
        Image(systemName: up ? "arrow.up" : "arrow.down")
          .font(.system(size: 12, weight: .semibold))
        Text(text)
      }
      .forge(12, .semibold)
      .foregroundStyle(up ? Theme.positive : Theme.textSecondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
          .fill(up ? Theme.positive.opacity(0.12) : Theme.innerSurface))
      Text("vs the same days last week").forgeLabel()
    }
    .accessibilityElement(children: .combine)
  }

  private func weekSummaryLabel(_ wtd: TrainingMetrics.WeekToDate) -> String {
    let lifted = String(
      localized: "This week, \(weekTonnageText(wtd.volume)) \(weekTonnageUnit) lifted so far",
      bundle: L10n.bundle)
    guard wtd.previousCovered else { return lifted }
    let diff = wtd.volume - wtd.previousVolume
    let value =
      usesLb
      ? String(format: "%.0fk", Plates.kgToLb(abs(diff)) / 1000)
      : Fmt.num(abs(diff) / 1000)
    return String(
      localized:
        "This week, \(weekTonnageText(wtd.volume)) \(weekTonnageUnit) lifted so far, \(diff >= 0 ? "+" : "−")\(value) \(weekTonnageUnit) vs the same days last week",
      bundle: L10n.bundle)
  }

  private var weeklyVolumeBins: [TrainingMetrics.WeekBin] {
    TrainingMetrics.weeklyBins(
      sessions.metricSets(scopes: [.trends]), weeks: 4, now: .now,
      calendar: TrainingMetrics.reportingCalendar(), scope: .analysisEligible,
      hardSetsOnly: false, coverageStart: sessions.coverageStart)
  }

  /// Four equal columns, the last one the current week; uncovered weeks show a track stub so
  /// missing history never reads as zero.
  private var weeklyTotals: some View {
    let bins = weeklyVolumeBins
    let maxVolume = bins.map(\.volume).max() ?? 0
    return VStack(alignment: .leading, spacing: 6) {
      Text("Weekly totals").forge(12, .medium).foregroundStyle(Theme.textSecondary)
      HStack(alignment: .bottom, spacing: 12) {
        ForEach(Array(bins.enumerated()), id: \.element.start) { index, bin in
          weekBar(bin, isCurrent: index == bins.count - 1, maxVolume: maxVolume)
        }
      }
      .frame(height: 64)
      HStack(spacing: 12) {
        ForEach(Array(bins.enumerated()), id: \.element.start) { index, bin in
          weekBarLabel(bin, isCurrent: index == bins.count - 1)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(weeklyTotalsLabel(bins))
  }

  private func weekBar(
    _ bin: TrainingMetrics.WeekBin, isCurrent: Bool, maxVolume: Double
  ) -> some View {
    Group {
      if bin.covered && bin.volume > 0 {
        UnevenRoundedRectangle(
          topLeadingRadius: Theme.radiusChip, bottomLeadingRadius: 0,
          bottomTrailingRadius: 0, topTrailingRadius: Theme.radiusChip, style: .continuous)
          .fill(isCurrent ? Theme.metricLoad : Theme.metricLoad.opacity(0.35))
          .frame(width: 36, height: max(4, 64 * bin.volume / max(maxVolume, 1)))
      } else if !bin.covered {
        UnevenRoundedRectangle(
          topLeadingRadius: Theme.radiusChip, bottomLeadingRadius: 0,
          bottomTrailingRadius: 0, topTrailingRadius: Theme.radiusChip, style: .continuous)
          .fill(Theme.track)
          .frame(width: 36, height: 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: 64, alignment: .bottom)
  }

  private func weekBarLabel(_ bin: TrainingMetrics.WeekBin, isCurrent: Bool) -> some View {
    Group {
      if isCurrent {
        Text("This week").forge(11, .semibold).foregroundStyle(Theme.accent)
      } else {
        Text(bin.start, format: .dateTime.day().month(.abbreviated).locale(L10n.locale))
          .forge(11, .medium).foregroundStyle(Theme.textSecondary)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// "Weekly totals, 31 Aug 31,5 t, … This week 37,8 t" — the chart as one element.
  private func weeklyTotalsLabel(_ bins: [TrainingMetrics.WeekBin]) -> String {
    var parts = [String(localized: "Weekly totals", bundle: L10n.bundle)]
    for (index, bin) in bins.enumerated() where bin.covered {
      let name =
        index == bins.count - 1
        ? String(localized: "This week", bundle: L10n.bundle)
        : bin.start.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
      parts.append("\(name) \(weekTonnageText(bin.volume)) \(weekTonnageUnit)")
    }
    return parts.joined(separator: ", ")
  }

  private var musclesRow: some View {
    NavigationLink {
      ProgressVolumeView(usesLb: usesLb, focus: .muscles)
    } label: {
      HStack(spacing: 10) {
        WeekMuscleThumbnail(intensity: facts.weekIntensity)
          .frame(width: 62, height: 58)
        VStack(alignment: .leading, spacing: 2) {
          Text("Muscles worked").forge(15, .semibold).foregroundStyle(Theme.text)
          Text(musclesSummary)
            .forgeLabel()
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.muscles")
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Muscles worked, \(musclesSummary)", bundle: L10n.bundle))
  }

  /// Worked regions most-worked-first as one localized, list-joined sentence.
  private var musclesSummary: String {
    let regions = BodyRegions.worked(facts.weekVolume)
    guard !regions.isEmpty else {
      return String(localized: "No sets logged this week", bundle: L10n.bundle)
    }
    var names = regions.map(regionName)
    names[0] = names[0].capitalized
    let formatter = ListFormatter()
    formatter.locale = L10n.locale
    return formatter.string(from: names) ?? names.joined(separator: ", ")
  }

  private func regionName(_ region: BodyRegion) -> String {
    switch region {
    case .back: return String(localized: "back", bundle: L10n.bundle)
    case .legs: return String(localized: "legs", bundle: L10n.bundle)
    case .chest: return String(localized: "chest", bundle: L10n.bundle)
    case .shoulders: return String(localized: "shoulders", bundle: L10n.bundle)
    case .arms: return String(localized: "arms", bundle: L10n.bundle)
    case .core: return String(localized: "core", bundle: L10n.bundle)
    }
  }

  // MARK: Highlights

  private var consistencyCard: some View {
    NavigationLink {
      ProgressConsistencyView(usesLb: usesLb)
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        IconBadge(symbol: "flame.fill", tint: Theme.metricEffort)
        MetricValue(
          value: "\(facts.streak)", unit: streakUnit, size: 22, color: Theme.metricEffort)
        Text("Consistency").forgeLabel()
        Text("1+ workout every week")
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card(padding: 14)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.consistency")
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(localized: "Consistency, \(facts.streak) \(streakUnit)", bundle: L10n.bundle))
  }

  private var streakUnit: String {
    facts.streak == 1
      ? String(localized: "week in a row", bundle: L10n.bundle)
      : String(localized: "weeks in a row", bundle: L10n.bundle)
  }

  private var bestEstimateSet: MetricSet? {
    TrainingMetrics.bestEstimateSet(
      sessions.metricSets(scopes: [.trends]), scope: .analysisEligible, in: nil, exerciseID: nil)
  }

  private var bestLiftCard: some View {
    let best = bestEstimateSet
    return NavigationLink {
      ProgressStrengthView(usesLb: usesLb, liftID: best?.exerciseID)
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        bestLiftArt(best)
        if let best {
          MetricValue(
            value: bestLiftValue(best), unit: facts.unit(for: best.exerciseID), size: 22,
            color: Theme.metricRecord)
          Text(bestLiftTitle(best)).forgeLabel()
          Text(bestLiftDetail(best))
            .forge(12, .medium)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("No lifts yet").forgeBodyStrong()
          Text("Finish a workout to see your best lift").forgeLabel()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card(padding: 14)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.bestLift")
    .accessibilityElement(children: .combine)
    .accessibilityLabel(bestLiftAccessibilityLabel(best))
  }

  private func bestLiftArt(_ best: MetricSet?) -> some View {
    Group {
      if let best, let exercise = ExerciseDB.find(best.exerciseID) {
        ExerciseArt(exercise: exercise, size: 52)
          .background(
            RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
              .fill(Theme.card))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
              .strokeBorder(Theme.imageOutline, lineWidth: 1))
      } else {
        Image("art-empty-progress")
          .resizable()
          .scaledToFit()
          .frame(width: 52, height: 52)
      }
    }
    .accessibilityHidden(true)
  }

  private func bestLiftValue(_ best: MetricSet) -> String {
    let e1rm = Strength.epley(weightKg: best.weightKg, reps: best.reps)
    return "\(Int(facts.lbValue(e1rm, id: best.exerciseID).rounded()))"
  }

  private func bestLiftTitle(_ best: MetricSet) -> String {
    let name = ExerciseDB.find(best.exerciseID)?.localizedName ?? best.exerciseID
    return String(localized: "\(name) · estimated 1RM", bundle: L10n.bundle)
  }

  private func bestLiftDetail(_ best: MetricSet) -> String {
    let weight = Fmt.num(facts.lbValue(best.weightKg, id: best.exerciseID))
    let date = best.date.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
    return String(
      localized: "From \(weight) \(facts.unit(for: best.exerciseID)) × \(best.reps), \(date)",
      bundle: L10n.bundle)
  }

  private func bestLiftAccessibilityLabel(_ best: MetricSet?) -> String {
    guard let best else {
      return String(localized: "No lifts yet", bundle: L10n.bundle)
    }
    return String(
      localized: "\(bestLiftTitle(best)), \(bestLiftValue(best)) \(facts.unit(for: best.exerciseID))",
      bundle: L10n.bundle)
  }

  // MARK: Destinations

  private var historyCard: some View {
    let title = String(localized: "History", bundle: L10n.bundle)
    let subtitle = String(
      localized: "\(facts.totalWorkouts) workout\(L10n.pluralSuffix(facts.totalWorkouts))",
      bundle: L10n.bundle)
    return NavigationLink {
      HistoryView(usesLb: usesLb)
    } label: {
      destinationLabel(art: "art-welcome", title: title, subtitle: subtitle)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: "\(title), \(subtitle)"))
    .accessibilityIdentifier("progress.history")
  }

  /// Distinct exercises with an eligible achievements set in completed sessions — the PR
  /// board's own counting rule.
  private var prLiftCount: Int {
    Set(sessions.analysisSets(.achievements).map(\.exerciseID)).count
  }

  private var prBoardCard: some View {
    let title = String(localized: "PR board", bundle: L10n.bundle)
    let subtitle = String(
      localized: "\(prLiftCount) lift\(L10n.pluralSuffix(prLiftCount)) with records",
      bundle: L10n.bundle)
    return NavigationLink {
      PRBoardView(usesLb: usesLb)
    } label: {
      destinationLabel(art: "art-pro", title: title, subtitle: subtitle)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: "\(title), \(subtitle)"))
    .accessibilityIdentifier("progress.prBoard")
  }

  private func destinationLabel(art: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 10) {
      Image(art)
        .resizable()
        .scaledToFit()
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forge(15, .semibold).foregroundStyle(Theme.text)
        Text(subtitle)
          .forgeLabel()
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 12)
  }

  // MARK: Trends

  /// A comparison needs data on both sides: one completed session in the last 28 days and one
  /// in the 56 days before it.
  private var trendsComparable: Bool {
    let now = Date.now
    let recentStart = now.addingTimeInterval(-28 * 86400)
    let priorStart = now.addingTimeInterval(-84 * 86400)
    let completed = sessions.filter(\.completed)
    return completed.contains { $0.date > recentStart }
      && completed.contains { $0.date > priorStart && $0.date <= recentStart }
  }

  @ViewBuilder
  private var trendsSection: some View {
    if trendsComparable {
      trendsCard
    } else {
      trendsEmptyCard
    }
  }

  private var trendsEmptyCard: some View {
    HStack(spacing: 12) {
      Image("art-empty-progress")
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Trend comparisons need more history")
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("They compare your last 4 weeks with the 8 weeks before.")
          .forgeLabel()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 14)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("progress.trends")
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
      let bestDisplay = facts.lbValue(recentBest, id: id)
      if let priorBest {
        let priorDisplay = facts.lbValue(priorBest, id: id)
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: facts.unit(for: id),
            direction: relDir(recentBest, priorBest, 0.01),
            detail: "was \(Fmt.num(priorDisplay))",
            color: Theme.metricLoad))
      } else {
        result.append(
          Trend(
            id: id,
            label: name,
            value: Fmt.num(bestDisplay),
            unit: facts.unit(for: id),
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
      ForEach(trends) { t in
        TrendRow(
          direction: t.direction, label: t.label, value: t.value, unit: t.unit, detail: t.detail,
          valueColor: t.color, metricSymbol: trendSymbol(t.id))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  // MARK: Explore

  private var exploreCard: some View {
    VStack(spacing: 0) {
      NavigationLink {
        TrainingAnalysisView(usesLb: usesLb)
      } label: {
        ProgressListRow(
          symbol: "chart.bar.xaxis",
          title: String(localized: "Training analysis", bundle: L10n.bundle),
          subtitle: String(localized: "Plan review, recovery, balance and more", bundle: L10n.bundle)
        )
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.trainingAnalysis")
      Divider().padding(.leading, 58)
      NavigationLink {
        BodyNutritionView(usesLb: usesLb)
      } label: {
        ProgressListRow(
          symbol: "figure.stand",
          title: String(localized: "Body & nutrition", bundle: L10n.bundle),
          subtitle: String(localized: "Body stats, progress photos and fuel", bundle: L10n.bundle)
        )
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.bodyNutrition")
      Divider().padding(.leading, 58)
      Button {
        showReports = true
      } label: {
        ProgressListRow(
          symbol: "doc.text",
          title: String(localized: "Reports", bundle: L10n.bundle),
          subtitle: String(localized: "PDF summary and data export", bundle: L10n.bundle)
        )
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.reports")
    }
    .card(padding: 0)
    .sheet(isPresented: $showReports) {
      ShareProgressSheet()
    }
  }

  // MARK: Footnote

  /// Progress reads analysis-eligible sets only — every number here is scoped and says so,
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

  private var footnote: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(eligibleScope.caption)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      if let excludedNote {
        Text(excludedNote)
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// One-time toast for badges earned since `badgesSeen` was last updated.
  private func celebrateNewBadges() {
    let seen = Set(badgesSeen.split(separator: ",").map(String.init))
    let earnedSet = Set(facts.earnedBadges.map(\.rawValue))
    let fresh = Badge.allCases.filter {
      earnedSet.contains($0.rawValue) && !seen.contains($0.rawValue)
    }
    guard !fresh.isEmpty else { return }
    newBadgeToast = fresh.first
    badgesSeen = earnedSet.sorted().joined(separator: ",")
  }

  // MARK: Header and picker

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
          if let headerCaption {
            Text(headerCaption)
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

  /// The one visible caption line: the active goal, and since when — the explicit start date
  /// when the lifter set one, else the month of the earliest completed session.
  private var headerCaption: String? {
    guard let profile else { return nil }
    let goal =
      Goal(rawValue: profile.goal)?.name
      ?? String(localized: "Training", bundle: L10n.bundle)
    let since =
      journeyProfileRecord?.trainingStartDate
      ?? sessions.filter({ $0.completed && !$0.tombstoned }).map(\.date).min()
    if let since {
      let date = since.formatted(.dateTime.month(.abbreviated).year().locale(L10n.locale))
      return String(localized: "Goal: \(goal) · since \(date)", bundle: L10n.bundle)
    }
    return String(localized: "Goal: \(goal)", bundle: L10n.bundle)
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
}

/// Both muscle figures at thumbnail size, without the map's Front/Back captions — the
/// "Muscles worked" preview on the Overview.
private struct WeekMuscleThumbnail: View {
  let intensity: [Muscle: Double]

  private func tint(_ muscle: Muscle) -> Color? {
    guard let value = intensity[muscle], value > 0 else { return nil }
    return Theme.rampColor(value)
  }

  var body: some View {
    HStack(spacing: 1) {
      MuscleFigure(side: .front, tint: tint)
      MuscleFigure(side: .back, tint: tint)
    }
    .accessibilityHidden(true)
  }
}
