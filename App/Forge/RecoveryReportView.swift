import ForgeCore
import SwiftData
import SwiftUI

/// Recovery: recovered enough to train hard today? Last night's sleep first, then the
/// 7-day window. Days without a check-in stay unknown, not zero.
struct RecoveryReportView: View {
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @State private var lastNightHK: Double?
  @State private var restingHR: Double?

  private var week: [CheckIn] {
    checkIns.filter { $0.date > Date.now.addingTimeInterval(-7 * 86400) }
  }

  private var latest: CheckIn? { checkIns.last }

  private var todayCheckIn: CheckIn? {
    checkIns.last { Calendar.current.isDateInToday($0.date) }
  }

  /// Last night's hours: today's check-in first, Apple Health as the fallback.
  private var lastNightHours: Double? {
    if let hours = todayCheckIn?.sleepHours, hours > 0 { return hours }
    return lastNightHK
  }

  private var subtitle: String? {
    guard let latest else { return nil }
    if let today = todayCheckIn {
      return String(
        localized: "Checked in today at \(today.date.formatted(.dateTime.hour().minute().locale(L10n.locale)))",
        bundle: L10n.bundle)
    }
    return String(
      localized: "Last check-in \(latest.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ProgressLargeTitle(title: "Recovery", subtitle: subtitle, art: "art-sleep")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
        todayBlock
          .padding(.bottom, 20)
        LogBand()
        lastSevenDays
        LogBand()
        howKaiUsesThis.padding(.bottom, 24)
      }
    }
    .background(Theme.page)
    .progressTitleNavigation("Recovery")
    .task {
      if lastNightHours == nil { lastNightHK = await Health.lastNightSleepHours() }
      restingHR = await Health.cardioSignals().rhr
    }
  }

  // MARK: today

  @ViewBuilder private var todayBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let hours = lastNightHours {
          Text(verbatim: Fmt.num(hours))
            .forge(44, .bold)
            .tracking(-1)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(verbatim: "h")
            .forge(22, .medium)
            .foregroundStyle(Theme.textSecondary)
          Text(String(localized: "slept last night", bundle: L10n.bundle))
            .forge(17, .medium)
            .foregroundStyle(Theme.textSecondary)
        } else {
          Text(verbatim: "—")
            .forge(44, .bold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "no sleep logged", bundle: L10n.bundle))
            .forge(17, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      if let checkIn = todayCheckIn ?? latest {
        Text(
          String(
            localized: "Sleep quality \(checkIn.sleep) of 5 · soreness \(checkIn.soreness) of 5",
            bundle: L10n.bundle))
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 12)
    .accessibilityElement(children: .combine)

    // What Kai does with the check-ins, when there are enough to say anything.
    if latest != nil {
      kaiRow
        .padding(.horizontal, Theme.margin)
    }
  }

  @ViewBuilder private var kaiRow: some View {
    let content: (title: String, detail: String) = {
      switch presentation {
      case .empty:
        return (
          String(localized: "No recovery evidence yet", bundle: L10n.bundle),
          String(
            localized: "Missing data is not treated as poor recovery.", bundle: L10n.bundle)
        )
      case .collecting(let count, let days):
        return (
          String(localized: "Collecting recovery evidence", bundle: L10n.bundle),
          String(
            localized: "\(count) of at least \(RecoveryPresentationPolicy.minimumAssessmentSamples) check-ins recorded in the last \(days) days.",
            bundle: L10n.bundle)
        )
      case .assessed(let summary, _, _):
        return (String(localized: "Kai keeps today's loads", bundle: L10n.bundle), summary)
      }
    }()
    HStack(alignment: .center, spacing: 12) {
      CoachAvatar(size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: content.title)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: content.detail)
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
    .accessibilityElement(children: .combine)
  }

  private var assessedSummary: String {
    let sorenessValues = week.map { Double($0.soreness) }
    let energyValues = week.map { Double($0.energy) }
    let avgSoreness = sorenessValues.isEmpty ? nil : sorenessValues.reduce(0, +) / Double(sorenessValues.count)
    let avgEnergy = energyValues.isEmpty ? nil : energyValues.reduce(0, +) / Double(energyValues.count)
    if let soreness = avgSoreness, soreness >= 4 {
      return String(
        localized:
          "Recorded soreness is elevated. Keep effort conservative and use the plan's recovery rules.",
        bundle: L10n.bundle)
    }
    if let energy = avgEnergy, energy <= 2 {
      return String(
        localized: "Recorded energy is low. Keep reported effort honest and prioritize recovery.",
        bundle: L10n.bundle)
    }
    return String(
      localized:
        "Recorded check-ins look stable. Follow today's prescribed session and report how it feels.",
      bundle: L10n.bundle)
  }

  private var presentation: RecoveryPresentation {
    RecoveryPresentationPolicy.presentation(
      sampleCount: week.count, assessedSummary: assessedSummary)
  }

  // MARK: last 7 days

  private var sleepDays: [V3WeekBars.Day] {
    let cal = Calendar.current
    return (0..<7).reversed().compactMap { offset in
      guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now))
      else { return nil }
      let hours = checkIns.last { cal.isDate($0.date, inSameDayAs: day) }?.sleepHours
      return V3WeekBars.Day(
        label: BodyV3.dayLabel(day), value: (hours ?? 0) > 0 ? hours : nil,
        isToday: offset == 0)
    }
  }

  private var sleepAverage: Double? {
    let logged = sleepDays.compactMap(\.value)
    return logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count)
  }

  private var lastSevenDays: some View {
    VStack(spacing: 0) {
      V3SectionHeader(
        "Last 7 days",
        trailing: String(localized: "\(week.count) of 7 check-ins", bundle: L10n.bundle))
      HStack(spacing: 8) {
        Circle().fill(Theme.metricSleep).frame(width: 8, height: 8)
        Text("Sleep").forge(17, .semibold).foregroundStyle(Theme.text)
        Spacer()
        if let average = sleepAverage {
          Text(verbatim: Fmt.num(average))
            .forge(17, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "h average", bundle: L10n.bundle))
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 12)
      .accessibilityElement(children: .combine)
      V3WeekBars(
        days: sleepDays,
        maxV: max(9, sleepDays.compactMap(\.value).max() ?? 1),
        colors: Theme.gradSleep)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)
      sorenessRow
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 12)
      if let bpm = restingHR {
        V3DetailRow(icon: "heart.fill", tint: Theme.metricHeart, title: rhrTitle, subtitle: rhrDetail) {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: Fmt.int(bpm))
              .forge(17, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
            Text(verbatim: "bpm")
              .forge(14, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)
      }
    }
  }

  private var sorenessRow: some View {
    V3DetailRow(
      icon: "figure.strengthtraining.functional", title: sorenessTitle,
      subtitle: sorenessDetail
    ) {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        if let soreness = latest?.soreness {
          Text(verbatim: "\(soreness)")
            .forge(17, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "of 5", bundle: L10n.bundle))
            .forge(14, .regular)
            .foregroundStyle(Theme.textSecondary)
        } else {
          Text(verbatim: "—")
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
        }
      }
    }
  }

  private var sorenessTitle: String { String(localized: "Soreness", bundle: L10n.bundle) }

  private var sorenessDetail: String {
    guard let checkIn = todayCheckIn ?? latest else {
      return String(localized: "No check-in yet", bundle: L10n.bundle)
    }
    let muscles = checkIn.soreMuscles.compactMap(Muscle.init(rawValue:)).map(\.a11yName)
    guard !muscles.isEmpty else {
      return String(localized: "From your check-in", bundle: L10n.bundle)
    }
    let list = muscles.formatted(.list(type: .and).locale(L10n.locale))
    return String(localized: "\(list) were sore", bundle: L10n.bundle)
  }

  private var rhrTitle: String { String(localized: "Resting heart rate", bundle: L10n.bundle) }
  private var rhrDetail: String { String(localized: "From Apple Health", bundle: L10n.bundle) }

  // MARK: how Kai uses this

  private var howKaiUsesThis: some View {
    VStack(spacing: 0) {
      V3SectionHeader("How Kai uses this")
      Text(
        "Short sleep or high soreness on the morning of a session makes Kai suggest keeping effort conservative before you start. Days without a check-in stay unknown, not zero."
      )
      .forge(15, .regular)
      .foregroundStyle(Theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Theme.margin)
    }
  }
}
