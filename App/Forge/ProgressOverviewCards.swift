import Charts
import ForgeCore
import SwiftUI

// Overview v6 parts (DESIGN.md §12, mock v6-overview.png). Composed by ProgressTabView;
// all numbers come from ProgressData / SwiftData queries passed in by the caller.

/// v6 hero on the peach field: one focal percent, its caption, and the mean strength line.
struct OverviewHero: View {
  let data: ProgressData

  /// Lifts with a comparable history: at least two workouts.
  private var compared: [LiftTrend] { data.liftTrends.filter { $0.changeKg(in: .all) != nil } }

  /// Mean percent change of every compared lift, rounded to a whole number.
  private var meanPct: Int? {
    let pcts = compared.map { ($0.changeKg(in: .all) ?? 0) / $0.first.e1rmKg * 100 }
    guard !pcts.isEmpty else { return nil }
    return Int((pcts.reduce(0, +) / Double(pcts.count)).rounded())
  }

  /// Mean percent change per week, from the week of the first session to this week. A lift
  /// contributes 0 until its first workout, then its change to the latest e1RM that week.
  private var points: [HeroPoint] {
    guard let since = data.strengthSince else { return [] }
    let cal = Calendar.current
    guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: since)?.start,
      let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start
    else { return [] }
    var weeks: [Date] = []
    var cursor = firstWeek
    while cursor <= thisWeek {
      weeks.append(cursor)
      guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
      cursor = next
    }
    return weeks.enumerated().map { index, week in
      let end = cal.date(byAdding: .weekOfYear, value: 1, to: week) ?? week
      let values = compared.map { trend -> Double in
        let first = trend.first.e1rmKg
        guard let last = trend.workouts.last(where: { $0.date < end })?.e1rmKg else { return 0 }
        return (last - first) / first * 100
      }
      return HeroPoint(index: index, pct: values.reduce(0, +) / Double(max(values.count, 1)))
    }
  }

  var body: some View {
    FieldSection(bottom: 24) {
      if data.comparedLiftCount == 0 {
        Text("Log a lift twice and its progress shows here.")
          .forge(17, .regular)
          .foregroundStyle(Theme.textSecondary)
      } else if let pct = meanPct, let since = data.strengthSince {
        let month = since.formatted(.dateTime.month(.wide).locale(L10n.locale))
        VStack(alignment: .leading, spacing: 0) {
          Text(verbatim: pct > 0 ? "+\(pct) %" : "\(pct) %")
            .forge(72, .bold)
            .tracking(-2)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .padding(.top, 12)
          Text(String(localized: "stronger since \(month)", bundle: L10n.bundle))
            .forge(17, .regular)
            .foregroundStyle(Theme.textSecondary)
          StrengthLine(points: points, endColor: endColor)
            .padding(.top, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          String(
            localized: "Estimated max up \(pct) percent on average since \(month)",
            bundle: L10n.bundle))
      }
    }
  }

  private var endColor: Color { data.freshRecords.isEmpty ? Theme.accent : Theme.recordRing }
}

private struct HeroPoint: Identifiable {
  let index: Int
  let pct: Double
  var id: Int { index }
}

/// v6: mean strength line — flat area fill, 3 pt accent line, dot on the last point.
private struct StrengthLine: View {
  let points: [HeroPoint]
  let endColor: Color

  private var domain: ClosedRange<Double> {
    let values = points.map(\.pct)
    return min(0, values.min() ?? 0)...(values.max() ?? 0) + 2
  }

  var body: some View {
    Chart {
      ForEach(points) { point in
        AreaMark(x: .value("Week", point.index), y: .value("Change", point.pct))
          .foregroundStyle(Theme.accent.opacity(0.12))
          .interpolationMethod(.monotone)
        LineMark(x: .value("Week", point.index), y: .value("Change", point.pct))
          .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          .foregroundStyle(Theme.accent)
          .interpolationMethod(.monotone)
      }
      if let last = points.last {
        PointMark(x: .value("Week", last.index), y: .value("Change", last.pct))
          .symbol {
            ZStack {
              Circle().fill(Theme.page).frame(width: 14, height: 14)
              Circle().fill(endColor).frame(width: 10, height: 10)
            }
          }
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: domain)
    .frame(height: 110)
    .accessibilityHidden(true)
  }
}

/// v6: one row in "Your lifts" — token, name and latest max, change, chevron.
struct OverviewLiftRow: View {
  let trend: LiftTrend
  let isLb: Bool

  var body: some View {
    HStack(spacing: 12) {
      LiftToken(exercise: trend.exercise, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(trend.exercise.localizedName)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Text(verbatim: "\(Fmt.num(latest)) \(unit)")
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      TrendChangeText(changeKg: trend.changeKg(in: .all), isLb: isLb, size: 17)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 60)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var unit: String { isLb ? "lb" : "kg" }

  private var latest: Double {
    let kg = trend.latest.e1rmKg
    return (isLb ? Plates.kgToLb(kg) : kg).rounded()
  }
}

/// v6: one glyph item in the "Your body" row — symbol, value, label.
struct OverviewBodyItem: View {
  let glyph: String
  let tint: Color
  /// nil when nothing is logged: the item then reads "Add".
  let value: String?
  let label: LocalizedStringKey
  let a11y: String

  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: glyph)
        .font(.system(size: 24))
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      if let value {
        Text(verbatim: value)
          .forge(17, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
      } else {
        Text(String(localized: "Add", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.accentText)
      }
      Text(label)
        .forge(13, .regular)
        .foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 72)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(a11y)
  }
}

/// v6: pending volume-increase ask under "Your body" — the same tinted row and review
/// sheet the v3 muscles card showed.
struct VolumeAskRow: View {
  struct Ask {
    let title: String
    let detail: String
    let onReview: () -> Void
  }

  let ask: Ask
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 12) {
      CoachAvatar(size: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(ask.title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(2)
        HStack(spacing: 5) {
          Circle().fill(Theme.accent).frame(width: 6, height: 6)
          Text(ask.detail)
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      Button(action: ask.onReview) {
        Text(String(localized: "Review", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.onAccent)
          .padding(.horizontal, 16)
          .frame(height: 36)
          .background(Capsule().fill(Theme.accentStrong))
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(String(localized: "Review \(ask.title)", bundle: L10n.bundle))
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(colorScheme == .dark ? Theme.innerSurface : Theme.accentTint))
  }
}

/// v6: one row in the "More" hairline list — SF Symbol glyph (or coach avatar), title, value.
struct ToolGlyphRow: View {
  private let glyph: String?
  private let tint: Color
  private let avatar: Bool
  private let title: LocalizedStringKey
  private let value: String?

  init(symbol: String, tint: Color, title: LocalizedStringKey, value: String? = nil) {
    self.glyph = symbol
    self.tint = tint
    self.avatar = false
    self.title = title
    self.value = value
  }

  init(avatar: Bool, verbatimTitle: String, value: String? = nil) {
    self.glyph = nil
    self.tint = Theme.accent
    self.avatar = avatar
    self.title = LocalizedStringKey(verbatimTitle)
    self.value = value
  }

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if avatar {
          CoachAvatar(size: 28)
        } else if let glyph {
          Image(systemName: glyph)
            .font(.system(size: 20))
            .foregroundStyle(tint)
        }
      }
      .frame(width: 28)
      .accessibilityHidden(true)
      Text(title)
        .forge(17, .regular)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let value {
        Text(verbatim: value)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 8)
    .frame(minHeight: 52)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
