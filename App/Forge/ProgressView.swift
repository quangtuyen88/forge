import ForgeCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query private var progressPhotos: [ProgressPhoto]
  @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]
  @Query(sort: \FoodEntry.date, order: .reverse) private var foodEntries: [FoodEntry]
  @State private var newBadgeToast: Badge?
  @State private var showSettings = false
  @State private var showReport = false
  @State private var approvingIncrease: VolumeIncrease?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("badgesSeen") private var badgesSeen = ""
  /// Which Progress surface is showing: Overview or the Journey timeline. Device-local and
  /// remembered, so returning to the tab reopens the same one. Overview is the default.
  @AppStorage(JourneyPref.segmentKey) private var segment = JourneyPref.segmentOverview

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var coach: Coach { Coach.from(coachID) }

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
    let data = ProgressData(sessions: sessions, profile: profile)
    return NavigationStack {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: Theme.groupGap) {
          segmentPicker
        }
        .padding(.horizontal, Theme.margin)
        if isTimeline {
          JourneyTimelineView(usesLb: usesLb, pendingAsk: pendingVolumeAsk)
        } else {
          overview(data)
        }
      }
      .background {
        VStack(spacing: 0) {
          Theme.field.frame(height: 420)
          Theme.page
        }
        .ignoresSafeArea()
      }
      .navigationTitle("My progress")
      .toolbarBackground(Theme.field, for: .navigationBar)
      .toolbarBackground(.automatic, for: .navigationBar)
      .modifier(BlockSubtitle(text: data.blockLine))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 2) {
            Button {
              showReport = true
            } label: {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "Share report", bundle: L10n.bundle))
            .accessibilityIdentifier("progress.share")
            Button {
              showSettings = true
            } label: {
              Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "Settings", bundle: L10n.bundle))
            .accessibilityIdentifier("progress.settings")
          }
          .todayGlass(Capsule())
        }
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
      }
      .sheet(isPresented: $showReport) {
        TrainingReportSheet(
          reportURL: ReportPDF.url(sessions: sessions, profile: profile),
          csvURL: csvURL)
      }
      .sheet(item: $approvingIncrease) { increase in
        VolumeApprovalSheet(
          increase: increase,
          coachName: coach.name,
          onApprove: { VolumeApprovals.approve(increase) },
          onKeep: { VolumeApprovals.keep(increase) })
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
          .background(Capsule().fill(Theme.accentStrong))
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

  /// The Overview v6 layout: the peach hero, then hairline lists on white. All derived
  /// numbers come from one `ProgressData` value; the parts live in ProgressOverviewCards.swift.
  private func overview(_ data: ProgressData) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        OverviewHero(data: data)
        VStack(alignment: .leading, spacing: 0) {
          liftsSection(data)
          bodySection
          if let ask = pendingVolumeAsk {
            VolumeAskRow(ask: ask)
              .padding(.top, 16)
          }
          moreSection(data)
          scopeCaptions
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, Theme.margin)
        .background(Theme.page)
      }
    }
    .modifier(NewRecordDemo(records: data.records, usesLb: usesLb))
  }

  private func sectionTitle(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .forge(20, .bold)
      .tracking(-0.3)
      .foregroundStyle(Theme.text)
      .accessibilityAddTraits(.isHeader)
  }

  private func hairline(leading: CGFloat) -> some View {
    Rectangle()
      .fill(Theme.ring)
      .frame(height: 1)
      .padding(.leading, leading)
  }

  // MARK: - Your lifts

  private func liftsSection(_ data: ProgressData) -> some View {
    let top = Array(
      data.liftTrends
        .filter { $0.status(in: .all) == .stronger }
        .sorted { ($0.changeKg(in: .all) ?? 0) > ($1.changeKg(in: .all) ?? 0) }
        .prefix(3))
    return VStack(alignment: .leading, spacing: 0) {
      sectionTitle("Your lifts")
        .padding(.top, 24)
        .padding(.bottom, 4)
      ForEach(Array(top.enumerated()), id: \.element.id) { index, trend in
        if index > 0 { hairline(leading: 52) }
        NavigationLink {
          LiftDetailView(exercise: trend.exercise, data: data, usesLb: usesLb)
        } label: {
          OverviewLiftRow(trend: trend, isLb: profile?.isLb(for: trend.exercise.id) ?? usesLb)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(
          "\(trend.exercise.localizedName), \(TrendChangeText.label(changeKg: trend.changeKg(in: .all), isLb: profile?.isLb(for: trend.exercise.id) ?? usesLb)) stronger"
        )
        .accessibilityIdentifier("progress.trend.\(trend.exercise.id)")
      }
      NavigationLink {
        ProgressTrendsView(usesLb: usesLb)
      } label: {
        HStack(spacing: 2) {
          Text(String(localized: "All \(data.liftTrends.count) lifts", bundle: L10n.bundle))
          Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .accessibilityHidden(true)
        }
        .forge(15, .semibold)
        .foregroundStyle(Theme.accentText)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Trends")
      .accessibilityIdentifier("progress.trends")
    }
  }

  // MARK: - Your body

  private var bodySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle("Your body")
        .padding(.top, 24)
        .padding(.bottom, 12)
      HStack(spacing: 0) {
        sleepItem
        proteinItem
        weightItem
        photosItem
      }
    }
  }

  /// Hours slept each of the last 7 days, oldest first; nil for a day without a logged night.
  private var sleepHours7: [Double?] {
    let cal = Calendar.current
    return (0..<7).reversed().map { offset -> Double? in
      guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { return nil }
      let hours = checkIns.last { cal.isDate($0.date, inSameDayAs: day) }?.sleepHours ?? 0
      return hours > 0 ? hours : nil
    }
  }

  private var sleepItem: some View {
    let logged = sleepHours7.compactMap { $0 }
    let avg = logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count)
    let num = avg.map { Fmt.num(($0 * 10).rounded() / 10) }
    return NavigationLink {
      RecoveryReportView()
    } label: {
      OverviewBodyItem(
        glyph: "bed.double.fill",
        tint: Theme.metricSleep,
        value: num.map { String(localized: "\($0) h", bundle: L10n.bundle) },
        label: "Sleep",
        a11y: num.map {
          String(localized: "Sleep, \($0) hours average, last 7 days", bundle: L10n.bundle)
        } ?? String(localized: "Sleep, nothing logged yet", bundle: L10n.bundle))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.recovery")
  }

  /// Protein grams logged each of the last 7 days, oldest first; nil for a day without food.
  private var protein7: [Double?] {
    let cal = Calendar.current
    return (0..<7).reversed().map { offset -> Double? in
      guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { return nil }
      let entries = foodEntries.filter { !$0.tombstoned && cal.isDate($0.date, inSameDayAs: day) }
      return entries.isEmpty ? nil : entries.reduce(0) { $0 + $1.proteinG }
    }
  }

  private var proteinItem: some View {
    let logged = protein7.compactMap { $0 }
    let avg = logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count)
    let grams = avg.map { Fmt.int($0) }
    return NavigationLink {
      NutritionView()
    } label: {
      OverviewBodyItem(
        glyph: "fork.knife",
        tint: Theme.positive,
        value: grams.map { String(localized: "\($0) g", bundle: L10n.bundle) },
        label: "Protein",
        a11y: grams.map {
          String(localized: "Protein, \($0) grams average, last 7 days", bundle: L10n.bundle)
        } ?? String(localized: "Protein, nothing logged yet", bundle: L10n.bundle))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.fuel")
  }

  private var weighIns: [(date: Date, kg: Double)] {
    measurements
      .compactMap { measurement in measurement.weightKg.map { (measurement.date, $0) } }
      .filter { $0.1 > 0 }
      .sorted { $0.date < $1.date }
  }

  private var weightItem: some View {
    let num = weighIns.last.map { Fmt.num(usesLb ? Plates.kgToLb($0.kg) : $0.kg) }
    return NavigationLink {
      MeasurementsView(usesLb: usesLb)
    } label: {
      OverviewBodyItem(
        glyph: "scalemass.fill",
        tint: Theme.positive,
        value: num.map { String(localized: "\($0) \(usesLb ? "lb" : "kg")", bundle: L10n.bundle) },
        label: "Weight",
        a11y: num.map {
          String(localized: "Weight, \($0) \(usesLb ? "lb" : "kg")", bundle: L10n.bundle)
        } ?? String(localized: "Weight, nothing logged yet", bundle: L10n.bundle))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.bodyStats")
  }

  private var photosItem: some View {
    let count = progressPhotos.count
    return NavigationLink {
      ProgressPhotosView()
    } label: {
      OverviewBodyItem(
        glyph: "camera.fill",
        tint: Theme.accent,
        value: count > 0 ? "\(count)" : nil,
        label: "Photos",
        a11y: count > 0
          ? String(
            localized: "Photos, \(count) private photo\(L10n.pluralSuffix(count))",
            bundle: L10n.bundle)
          : String(localized: "Photos, none yet", bundle: L10n.bundle))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("progress.photos")
  }

  /// The tinted ask row under "Your body": the same pending volume increase Today
  /// surfaces, opening the same review sheet.
  private var pendingVolumeAsk: VolumeAskRow.Ask? {
    guard let increase = volumeIncreases.first(where: { $0.answer == nil }) else { return nil }
    let added = increase.toSets - increase.fromSets
    return VolumeAskRow.Ask(
      title: String(
        localized: "Add \(added) \(increase.exercise.localizedName) set\(L10n.pluralSuffix(added))",
        bundle: L10n.bundle),
      detail: String(
        localized: "\(coach.name) · \(increase.muscle.a11yName) short of its minimum",
        bundle: L10n.bundle)
    ) {
      approvingIncrease = increase
    }
  }

  private var volumeIncreases: [VolumeIncrease] {
    guard let profile else { return [] }
    return VolumeApprovals.increases(profile: profile, sessions: sessions, checkIns: checkIns)
  }

  // MARK: - More

  private func moreSection(_ data: ProgressData) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle("More")
        .padding(.top, 24)
        .padding(.bottom, 4)
      NavigationLink {
        PRBoardView(usesLb: usesLb)
      } label: {
        ToolGlyphRow(
          symbol: "trophy.fill", tint: Theme.recordRing, title: "Records",
          value: "\(data.records.count)")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(String(localized: "PR board", bundle: L10n.bundle))
      .accessibilityIdentifier("progress.prBoard")
      hairline(leading: 40)
      NavigationLink {
        HistoryView(usesLb: usesLb)
      } label: {
        ToolGlyphRow(
          symbol: "clock.arrow.circlepath", tint: Theme.metricTime, title: "History",
          value: String(
            localized: "\(totalWorkouts) session\(L10n.pluralSuffix(totalWorkouts))",
            bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.history.row")
      hairline(leading: 40)
      NavigationLink {
        MesoHistoryView(usesLb: usesLb)
      } label: {
        ToolGlyphRow(
          symbol: "calendar", tint: Theme.metricTime, title: "Training blocks",
          value: String(
            localized: "Block \(data.currentBlock) · week \(profile?.currentWeek(sessions: sessions) ?? 1)",
            bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.mesocycles")
      hairline(leading: 40)
      NavigationLink {
        MuscleVolumeView(
          weekSets: data.last7DaySets, recoveryReduced: profile?.recoveryReduced ?? false)
      } label: {
        ToolGlyphRow(
          symbol: "figure.strengthtraining.traditional", tint: Theme.accent, title: "Muscles")
      }
      .buttonStyle(RowPressStyle())
      hairline(leading: 40)
      NavigationLink {
        LiftCollectionView(data: data, usesLb: usesLb)
      } label: {
        ToolGlyphRow(
          symbol: "dumbbell.fill", tint: Theme.accent, title: "All lifts", value: collectionDetail(data))
      }
      .buttonStyle(RowPressStyle())
      hairline(leading: 40)
      NavigationLink {
        PlanAuditView()
      } label: {
        ToolGlyphRow(symbol: "checklist", tint: Theme.accent, title: "Plan audit")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.planAudit")
      hairline(leading: 40)
      NavigationLink {
        AdjustmentsView()
      } label: {
        ToolGlyphRow(symbol: "chart.bar.fill", tint: Theme.accent, title: "Adjustments")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.recommendations")
      hairline(leading: 40)
      NavigationLink {
        TrainingExperimentsView()
      } label: {
        ToolGlyphRow(
          symbol: "flask.fill", tint: Theme.accent, title: "Experiments", value: experimentValue)
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.experiments")
      hairline(leading: 40)
      NavigationLink {
        BalanceRadarView()
      } label: {
        ToolGlyphRow(symbol: "scale.3d", tint: Theme.accent, title: "Balance")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("progress.balance")
      hairline(leading: 40)
      NavigationLink {
        AwardsView(earned: data.earnedBadges, progress: data.badgeProgress)
      } label: {
        ToolGlyphRow(
          symbol: "medal.fill", tint: Theme.recordRing, title: "Awards",
          value: String(
            localized: "\(data.earnedBadges.count) of \(Badge.allCases.count)", bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Awards, \(data.earnedBadges.count) of \(Badge.allCases.count)")
    }
  }

  /// "<logged> of <in program>", or just the logged count when the program count is unavailable.
  private func collectionDetail(_ data: ProgressData) -> String {
    data.plannedCount > 0
      ? String(localized: "\(data.lifts.count) of \(data.plannedCount)", bundle: L10n.bundle)
      : "\(data.lifts.count)"
  }

  private var experimentValue: String {
    guard let experiment = profile?.trainingExperiment else {
      return String(localized: "None running", bundle: L10n.bundle)
    }
    let name = ExerciseDB.find(experiment.exerciseID)?.localizedName
    return name.map {
      String(localized: "\(experiment.intervention.name) · \($0)", bundle: L10n.bundle)
    } ?? experiment.intervention.name
  }

  private var scopeCaptions: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        "Sets that look like typing mistakes stay in History but are left out of trends, records and awards."
      )
      .forgeCaption()
      .foregroundStyle(Theme.textSecondary)
      if let excludedNote {
        Text(excludedNote).forgeCaption().foregroundStyle(Theme.textSecondary)
      }
    }
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

  /// One-time toast for badges earned since `badgesSeen` was last updated.
  private func celebrateNewBadges() {
    let earned = ProgressData(sessions: sessions, profile: profile).earnedBadges
    let seen = Set(badgesSeen.split(separator: ",").map(String.init))
    let earnedSet = Set(earned.map(\.rawValue))
    let fresh = Badge.allCases.filter {
      earnedSet.contains($0.rawValue) && !seen.contains($0.rawValue)
    }
    guard !fresh.isEmpty else { return }
    newBadgeToast = fresh.first
    badgesSeen = earnedSet.sorted().joined(separator: ",")
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

  /// One definition, shared with Balance and History via `analysisEligibleSessions`.
  private var totalWorkouts: Int { sessions.analysisEligibleSessions.count }
}

/// The training-block line under the title; `navigationSubtitle` exists from iOS 26.
private struct BlockSubtitle: ViewModifier {
  let text: String?

  func body(content: Content) -> some View {
    if #available(iOS 26, *), let text {
      content.navigationSubtitle(text)
    } else {
      content
    }
  }
}
