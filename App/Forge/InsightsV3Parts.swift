import ForgeCore
import Foundation
import SwiftUI

/// Shared derivations and small parts for the Plan insights v3 screens (Plan audit, Kai's
/// suggestions, Experiments, Balance). Data helpers here so every screen reads the same
/// block walk, the same measured-outcome walk and the same muscle-day walk.
enum InsightsV3 {
  // MARK: - measured outcomes

  /// What happened to one lift after a change: the best comparable e1RM before the change
  /// versus the best after it. "Better" is the same 0.5 kg threshold TrendChangeText uses.
  struct Measurement {
    enum Outcome { case better, noChange, measuring }

    let outcome: Outcome
    let bestBefore: Double?
    let bestAfter: Double?
    let bestAfterDate: Date?
  }

  /// Best-before / best-after for one exercise around `since`. nil when the lift was never
  /// logged, so a whole-session change cannot pretend to be measured.
  static func measurement(exerciseID: String?, since: Date, sessions: [WorkoutSession]) -> Measurement? {
    guard let exerciseID, !exerciseID.isEmpty else { return nil }
    let cal = Calendar.current
    let dayStart = cal.startOfDay(for: since)
    let history = LogV3.e1rmHistory(exerciseID: exerciseID, sessions: sessions)
    guard !history.isEmpty else { return nil }
    let before = history.filter { $0.date < dayStart }.map(\.e1rm).max()
    let after = history.filter { $0.date >= dayStart }.max { $0.e1rm < $1.e1rm }
    guard let before, let after else {
      return Measurement(outcome: .measuring, bestBefore: before, bestAfter: nil, bestAfterDate: nil)
    }
    return Measurement(
      outcome: after.e1rm > before + 0.5 ? .better : .noChange,
      bestBefore: before, bestAfter: after.e1rm, bestAfterDate: after.date)
  }

  // MARK: - blocks

  /// Block number a date falls in, by each block's first-session week; a date at or after
  /// the profile's block start reads as the next block even before its first session.
  static func blockNumber(of date: Date, sessions: [WorkoutSession], profile: UserProfile?) -> Int {
    let blocks = LogV3.blocks(sessions: sessions, profile: profile)
    let numbers = blocks.compactMap { block -> (start: Date, number: Int)? in
      guard let first = block.firstDate else { return nil }
      return (LogV3.weekStart(containing: first), block.number)
    }
    if let mesoStart = profile?.mesoStart, date >= mesoStart {
      return (numbers.last?.number ?? 0) + 1
    }
    return numbers.last(where: { $0.start <= date })?.number ?? 1
  }

  /// Done and planned sessions over every logged block, on the calendar-week plan math
  /// History uses (planned/missed runs on calendar weeks, never on program weeks).
  static func planTotals(sessions: [WorkoutSession], profile: UserProfile?) -> (done: Int, planned: Int) {
    guard let profile, profile.daysPerWeek > 0 else { return (0, 0) }
    var done = 0
    var planned = 0
    for block in LogV3.blocks(sessions: sessions, profile: profile) {
      for column in LogV3.weekColumns(block: block, daysPerWeek: profile.daysPerWeek) {
        done += column.done
        planned += max(profile.daysPerWeek, column.done)
      }
    }
    return (done, planned)
  }

}

// MARK: - shared parts

/// The plain-words answer under a screen's large title: one verdict line plus one line
/// that names the gaps (mock `.verdict`).
struct InsightsVerdict: View {
  let title: String
  let line: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .forge(22, .semibold, tracking: -0.33)
        .foregroundStyle(Theme.text)
      Text(line)
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Section header of a white detail page: bold title with a quiet trailing note
/// (mock `.sh`). `minor` renders the h3 weight.
struct InsightsSectionHeader: View {
  let title: LocalizedStringKey
  var trailing: String? = nil
  var minor = false

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .forge(minor ? 18 : 20, .semibold, tracking: minor ? -0.18 : -0.3)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      if let trailing {
        Text(trailing)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
  }
}

/// Three-stat row of the v6 field: big tabular value with the "of N" tail inline, the
/// label below, and 1 pt hairlines between the columns (mock `.stats`).
struct InsightsStatColumns: View {
  struct Item {
    let label: String
    let value: String
    let of: String
  }

  let items: [Item]
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            statCell(item)
          }
        }
      } else {
        HStack(alignment: .top, spacing: 16) {
          ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            statCell(item)
            if index < items.count - 1 {
              Rectangle().fill(Theme.ring).frame(width: 1)
            }
          }
        }
      }
    }
  }

  private func statCell(_ item: Item) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(item.value)
          .forge(28, .bold, tracking: -0.56)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text(item.of)
          .forge(15)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
      Text(item.label)
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// Weekly-sets range bar: grey track, the landmark zone in peach, the value as an amber
/// dot, and the zone edges labelled (mock `.rng`).
struct InsightsRangeBar: View {
  let value: Double
  let mev: Int
  let mrv: Int

  var body: some View {
    GeometryReader { geo in
      let scale = Double(max(mrv, 1)) * 1.2
      let w = geo.size.width
      let mevX = Double(mev) / scale * w
      let mrvX = Double(mrv) / scale * w
      let valX = min(value, scale) / scale * w
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track).frame(height: 6)
        Capsule().fill(Theme.ramp[2])
          .frame(width: max(0, mrvX - mevX), height: 6)
          .offset(x: mevX)
        Circle().fill(Theme.metricSets)
          .frame(width: 12, height: 12)
          .overlay(Circle().strokeBorder(Theme.page, lineWidth: 2))
          .offset(x: max(0, valX - 6))
        Text("\(mev)")
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .fixedSize()
          .offset(x: mevX - 10, y: 16)
        Text("\(mrv)")
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .fixedSize()
          .offset(x: mrvX - 10, y: 16)
      }
    }
    .frame(height: 32)
    .accessibilityHidden(true)
  }
}

/// One funnel row of Kai's suggestions: the number, the label, a quiet note, and the bar
/// (mock `.fs`).
struct InsightsFunnelRow: View {
  let value: Int
  let label: String
  var note: String? = nil
  let fraction: Double
  let fill: [Color]

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Text("\(value)")
        .forge(28, .bold, tracking: -0.56)
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .frame(width: 44, alignment: .leading)
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(label)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          if let note {
            Text(note)
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
              .lineLimit(1)
          }
        }
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.track)
            Capsule()
              .fill(.mark(fill, startPoint: .leading, endPoint: .trailing))
              .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
          }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
      }
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
  }
}

/// The outcome word of a suggestion row: "Better" in the gain color, everything else in
/// secondary (mock `.oc`).
struct InsightsOutcomeWord: View {
  let text: String
  var better = false

  var body: some View {
    Text(text)
      .forge(15, better ? .semibold : .medium)
      .foregroundStyle(better ? Theme.positiveText : Theme.textSecondary)
      .lineLimit(1)
  }
}

/// Round 44 pt icon badge for rows that sit beside 44 pt avatars and tokens (mock `.ib.c44`).
struct InsightsRoundBadge: View {
  let symbol: String
  let tint: Color

  var body: some View {
    Image(systemName: symbol)
      .scaledSystemFont(20, weight: .semibold)
      .foregroundStyle(tint)
      .frame(width: 44, height: 44)
      .background(Circle().fill(tint.opacity(0.14)))
      .accessibilityHidden(true)
  }
}
