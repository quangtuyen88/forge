import ForgeCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query private var progressPhotos: [ProgressPhoto]
  @State private var newBadgeToast: Badge?
  @AppStorage("badgesSeen") private var badgesSeen = ""
  /// Which Progress surface is showing: Overview or the Journey timeline. Device-local and
  /// remembered, so returning to the tab reopens the same one. Overview is the default.
  @AppStorage(JourneyPref.segmentKey) private var segment = JourneyPref.segmentOverview
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
          JourneyTimelineView(usesLb: usesLb)
        } else {
          overview(data)
        }
      }
      .background {
        TodaySkyPage()
      }
      .navigationTitle("My Progress")
      .toolbarBackground(.hidden, for: .navigationBar)
      .modifier(BlockSubtitle(text: data.blockLine))
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

  /// The sky-layout overview: outcomes first (strength, records, consistency, muscles),
  /// diagnostics under "More". All derived numbers come from one `ProgressData` value.
  private func overview(_ data: ProgressData) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        strengthHero(data)
        recordsCard(data)
        consistencyCard(data)
        musclesWeekSection(data)
        awardsLink(data)
        moreSection
        scopeCaptions
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .modifier(NewRecordDemo(records: data.records, usesLb: usesLb))
  }

  private func strengthHero(_ data: ProgressData) -> some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 14) {
        Text("Strength").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
        if data.comparedLiftCount == 0 {
          Text("Log a lift twice and its progress shows here.")
            .forgeLabel()
            .foregroundStyle(Theme.textSecondary)
        } else {
          let month =
            (data.strengthSince ?? .now)
            .formatted(.dateTime.month(.wide).locale(L10n.locale))
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(data.strongerLifts.count)")
              .forge(56, .bold)
              .foregroundStyle(Theme.accent)
              .monospacedDigit()
            Text("of \(data.comparedLiftCount) lifts stronger since \(month)")
              .forge(20, .semibold)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        if !data.strongerLifts.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(data.strongerLifts.prefix(4).enumerated()), id: \.element.id) { index, lift in
              let trend = data.trend(for: lift.exercise.id)
              if index > 0 { Divider().padding(.leading, 56) }
              NavigationLink {
                LiftDetailView(exercise: lift.exercise, data: data, usesLb: usesLb)
              } label: {
                HStack(spacing: 12) {
                  LiftToken(exercise: lift.exercise, size: 44, record: trend?.latestIsRecord ?? false)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(lift.exercise.localizedName)
                      .forge(16, .semibold)
                      .foregroundStyle(Theme.text)
                      .lineLimit(3)
                      .minimumScaleFactor(0.85)
                      .fixedSize(horizontal: false, vertical: true)
                    Text(
                      verbatim:
                        "\(Fmt.num(lbValue(lift.latestE1RM, id: lift.exercise.id).rounded())) \(unit(for: lift.exercise.id))"
                    )
                      .forge(15, .regular)
                      .foregroundStyle(Theme.textSecondary)
                      .monospacedDigit()
                  }
                  Spacer(minLength: 8)
                  if let trend {
                    LiftSparkline(valuesKg: trend.workouts.map(\.e1rmKg), endIsRecord: trend.latestIsRecord)
                      .frame(width: 72, height: 28)
                  }
                  TrendChangeText(changeKg: lift.deltaKg, isLb: profile?.isLb(for: lift.exercise.id) ?? usesLb)
                    .frame(minWidth: 56, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel(
                "\(lift.exercise.localizedName), \(Fmt.num(lbValue(lift.deltaKg, id: lift.exercise.id))) \(unit(for: lift.exercise.id)) stronger"
              )
              .accessibilityIdentifier("progress.trend.\(lift.exercise.id)")
            }
          }
        }
      }
    } footer: {
      NavigationLink {
        ProgressTrendsView(usesLb: usesLb)
      } label: {
        FooterStrip(
          symbol: "chart.bar.fill", title: "Trends for every lift", detail: "\(data.liftTrends.count)")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Trends")
      .accessibilityIdentifier("progress.trends")
    }
  }

  /// The newest record event per exercise (records are newest-first overall).
  private func newestRecords(_ data: ProgressData) -> [ProgressData.Record] {
    var seen = Set<String>()
    return data.records.filter { seen.insert($0.exercise.id).inserted }
  }

  private func recordsCard(_ data: ProgressData) -> some View {
    VStack(spacing: 12) {
      if !data.records.isEmpty {
        NavigationLink {
          LiftCollectionView(data: data, usesLb: usesLb)
        } label: {
          SkySectionHeader(
            "New records",
            trailing: String(localized: "\(data.records.count) total", bundle: L10n.bundle))
        }
      }
      SkyCard {
        if data.records.isEmpty {
          Text("Beat a lift's best and it lands here.")
            .forgeLabel()
            .foregroundStyle(Theme.textSecondary)
        } else {
          HStack(spacing: 12) {
            ForEach(Array(newestRecords(data).prefix(3))) { record in
              NavigationLink {
                LiftDetailView(exercise: record.exercise, data: data, usesLb: usesLb)
              } label: {
                VStack(spacing: 4) {
                  LiftToken(exercise: record.exercise, size: 72, record: true)
                  Text(record.exercise.localizedName)
                    .forge(15, .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                  Text(
                    "\(Fmt.num(lbValue(record.weightKg, id: record.exercise.id))) \(unit(for: record.exercise.id)) × \(record.reps)"
                  )
                  .forge(15, .regular)
                  .foregroundStyle(Theme.textSecondary)
                  .monospacedDigit()
                  Text(dayLabel(record.date))
                    .forge(13, .regular)
                    .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel(
                "\(record.exercise.localizedName), record \(Fmt.num(lbValue(record.weightKg, id: record.exercise.id))) \(unit(for: record.exercise.id)) × \(record.reps), \(dayLabel(record.date))"
              )
            }
          }
        }
      } footer: {
        NavigationLink {
          LiftCollectionView(data: data, usesLb: usesLb)
        } label: {
          FooterStrip(
            symbol: "circle.grid.2x2", title: "Your lift collection", detail: "\(data.lifts.count)")
        }
        .buttonStyle(RowPressStyle())
      }
    }
  }

  private func consistencyCard(_ data: ProgressData) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Consistency").forgeSection()
        Spacer()
        if data.streakWeeks > 0 {
          SkyPill(String(localized: "\(data.streakWeeks)-week streak", bundle: L10n.bundle), symbol: "flame.fill", style: .orange)
        }
      }
      SkyCard {
        VStack(alignment: .leading, spacing: 12) {
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
          Divider()
          HStack {
            stat("\(data.sessionCount)", "sessions")
            Divider().frame(height: 36)
            stat(Fmt.num(data.sessionsPerWeek), "a week on average")
          }
        }
      }
    }
  }

  private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
    VStack(spacing: 2) {
      Text(value).forge(28, .bold).foregroundStyle(Theme.text).monospacedDigit()
      Text(label).forge(13, .regular).foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func musclesWeekSection(_ data: ProgressData) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Muscles this week").forgeSection()
        Spacer()
        NavigationLink("Details") {
          MuscleVolumeView(weekSets: data.weekSets, recoveryReduced: profile?.recoveryReduced ?? false)
        }
        .forge(17, .regular)
      }
      SkyCard { MusclesWeekCard(weekSets: data.weekSets, top: data.topMuscles) }
    }
  }

  private func awardsLink(_ data: ProgressData) -> some View {
    let medals = Badge.allCases.filter { data.earnedBadges.contains($0) }.suffix(3)
    let line: String
    if let next = data.nextBadge {
      line = String(
        localized: "\(data.earnedBadges.count) of \(Badge.allCases.count) · Next: \(next.badge.title)",
        bundle: L10n.bundle)
    } else {
      line = String(
        localized: "\(data.earnedBadges.count) of \(Badge.allCases.count)", bundle: L10n.bundle)
    }
    return NavigationLink {
      AwardsView(earned: data.earnedBadges, progress: data.badgeProgress)
    } label: {
      SkyCard {
        HStack(spacing: 14) {
          HStack(spacing: -14) {
            if medals.isEmpty {
              MedalArt(badge: .firstSession, earned: false, fraction: 0, size: 44)
            } else {
              ForEach(Array(medals), id: \.rawValue) { badge in
                MedalArt(badge: badge, earned: true, fraction: 1, size: 44)
              }
            }
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("Awards").forgeBodyStrong()
            Text(line).forge(15, .regular).foregroundStyle(Theme.textSecondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
      }
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel("Awards, \(data.earnedBadges.count) of \(Badge.allCases.count)")
  }

  private var moreSection: some View {
    VStack(spacing: 12) {
      Text("More").forgeSection()
        .frame(maxWidth: .infinity, alignment: .leading)
      SkyCard(padding: 0) { analyticsGrid }
    }
  }

  private var scopeCaptions: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(eligibleScope.label).forgeCaption().foregroundStyle(Theme.textSecondary)
      Text(eligibleScope.caption).forgeCaption().foregroundStyle(Theme.textSecondary)
      if let excludedNote {
        Text(excludedNote).forgeCaption().foregroundStyle(Theme.textSecondary)
      }
    }
  }

  /// "Today" for today, the weekday inside the last six days, else "Mar 4" style.
  private func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return String(localized: "Today", bundle: L10n.bundle) }
    let days =
      cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day
      ?? 0
    if (1...6).contains(days) {
      return date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
    }
    return date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
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

  /// Progress reads analysis-eligible sets only — every number on this tab is scoped and says
  /// so, so it can never be read as the all-recorded totals Today shows.
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

  /// One definition, shared with Balance and History via `analysisEligibleSessions`.
  private var totalWorkouts: Int { sessions.analysisEligibleSessions.count }

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
    VStack(spacing: 0) {
      NavigationLink {
        HistoryView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "clock.fill", title: "History",
          subtitle: "\(totalWorkouts) eligible session\(L10n.pluralSuffix(totalWorkouts))",
          color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.history.row")
      Divider().padding(.leading, 56)
      NavigationLink {
        PlanAuditView()
      } label: {
        TrainingToolRow(
          symbol: "stethoscope", title: "Plan audit", subtitle: "What is working and what changed",
          color: Theme.accent)
      }
      .accessibilityIdentifier("progress.planAudit")
      Divider().padding(.leading, 56)
      NavigationLink {
        RecoveryReportView()
      } label: {
        TrainingToolRow(
          symbol: "bolt.heart.fill", title: "Recovery",
          subtitle: "Recorded inputs and 7-day coverage",
          color: Theme.metricHeart)
      }
      .accessibilityIdentifier("progress.recovery")
      Divider().padding(.leading, 56)
      NavigationLink {
        TrainingExperimentsView()
      } label: {
        TrainingToolRow(
          symbol: "flask.fill", title: "Experiments",
          subtitle: profile?.trainingExperiment == nil ? "Test one change" : "4-week protocol",
          color: Theme.accent)
      }
      .accessibilityIdentifier("progress.experiments")
      Divider().padding(.leading, 56)
      NavigationLink {
        RecommendationEffectivenessView()
      } label: {
        TrainingToolRow(
          symbol: "chart.bar.fill", title: "Recommendation effectiveness",
          subtitle: "What was proposed, applied and measured",
          color: Theme.accent)
      }
      .accessibilityIdentifier("progress.recommendations")
      Divider().padding(.leading, 56)
      NavigationLink {
        PRBoardView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "trophy.fill", title: "PR board",
          subtitle: "\(loggedExerciseIDs.count) lift\(L10n.pluralSuffix(loggedExerciseIDs.count)) with eligible records",
          color: Theme.metricRecord)
      }
      .accessibilityIdentifier("progress.prBoard")
      Divider().padding(.leading, 56)
      NavigationLink {
        BalanceRadarView()
      } label: {
        TrainingToolRow(
          symbol: "circle.hexagongrid.fill", title: "Balance",
          subtitle: "Push, pull, legs and evidence coverage",
          color: Theme.metricLoad)
      }
      .accessibilityIdentifier("progress.balance")
      Divider().padding(.leading, 56)
      NavigationLink {
        MesoHistoryView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "square.stack.3d.up.fill", title: "Mesocycles",
          subtitle: "\(mesoBlockCount) recorded block\(L10n.pluralSuffix(mesoBlockCount))",
          color: Theme.metricTime)
      }
      .accessibilityIdentifier("progress.mesocycles")
      Divider().padding(.leading, 56)
      NavigationLink {
        NutritionView()
      } label: {
        TrainingToolRow(
          symbol: "fork.knife", title: "Fuel", subtitle: "Calories, macros and daily guidance",
          color: Theme.metricEnergy)
      }
      .accessibilityIdentifier("progress.fuel")
      Divider().padding(.leading, 56)
      NavigationLink {
        MeasurementsView(usesLb: usesLb)
      } label: {
        TrainingToolRow(
          symbol: "scalemass", title: "Body stats",
          subtitle: latestWeight.map { LocalizedStringKey($0) } ?? "No measurements yet",
          color: Theme.accent)
      }
      .accessibilityIdentifier("progress.bodyStats")
      Divider().padding(.leading, 56)
      NavigationLink {
        ProgressPhotosView()
      } label: {
        TrainingToolRow(
          symbol: "camera.fill", title: "Photos",
          subtitle: progressPhotos.isEmpty
            ? "Private progress photos"
            : "\(progressPhotos.count) private photo\(L10n.pluralSuffix(progressPhotos.count))",
          color: Theme.accent)
      }
      .accessibilityIdentifier("progress.photos")
      Divider().padding(.leading, 56)
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
}

private struct TrainingToolRow: View {
  let symbol: String
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  var color: Color = Theme.accent
  var showsChevron = true

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(color.opacity(0.14)))
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
