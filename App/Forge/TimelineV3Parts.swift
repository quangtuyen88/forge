import ForgeCore
import SwiftUI

// MARK: - Timeline v3 parts (DESIGN §12: week card docking, filter pills, one rail node per entry)
//
// The v3 timeline: session letters on planned days, quiet one-line body entries, week boundary
// rows and record rows on workout cards. The v2 components in TimelineComponents.swift stay in
// the target untouched; this file owns everything the v3 list draws.

// MARK: - Day stamp

/// One day-stamp shape, shared by the week card (34), the docked bar (26) and the rail nodes.
/// `letter` is the session letter (A/B/C) drawn inside `.planned`; `number` is the day-of-month
/// drawn inside the docked-bar shapes.
struct TimelineStampV3: View {
  enum Shape: Equatable {
    /// Move fill + white check.
    case done
    /// Dashed Move ring with the session letter.
    case planned
    /// Small track dot (rest days).
    case restDot
    /// Row-fill disc with the number (docked past/future days without entries).
    case quietNumber
    /// Row-fill disc with the number raised and an accent dot beneath (days with entries).
    case entryNumber
  }

  let shape: Shape
  var isToday = false
  var letter: String? = nil
  var size: CGFloat = 34
  var number: String? = nil
  /// 1 at rest in the week card; 0 while travelling.
  var haloOpacity: Double = 1
  /// Fill behind the dashed planned ring (the rail node sits it on a page-grey disc).
  var plannedFill: Color? = nil

  private var k: CGFloat { size / 34 }

  var body: some View {
    ZStack {
      switch shape {
      case .done:
        Circle()
          .fill(Theme.metricEffort)
          .background(
            Circle().stroke(Theme.metricEffort.opacity(0.18 * haloOpacity), lineWidth: 6 * k))
          .overlay(
            Image(systemName: "checkmark")
              .font(.system(size: 17 * k, weight: .heavy))
              .foregroundStyle(Theme.onAccent))
      case .planned:
        ZStack {
          if let plannedFill {
            Circle().fill(plannedFill)
          }
          Text(verbatim: letter ?? "")
            .forge(14 * k, size < 30 ? .semibold : .bold)
            .foregroundStyle(isToday ? Theme.accentText : Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .overlay(
          Circle().strokeBorder(
            Theme.metricEffort,
            style: StrokeStyle(lineWidth: 1.75 * k, dash: [4 * k, 3 * k])))
      case .restDot:
        Circle().fill(Theme.track).frame(width: 6 * k, height: 6 * k)
      case .quietNumber:
        numberDisc(raised: false)
      case .entryNumber:
        numberDisc(raised: true)
      }
      if isToday, shape != .done {
        Circle().strokeBorder(Theme.accent, lineWidth: 2.5 * k)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private func numberDisc(raised: Bool) -> some View {
    ZStack {
      Circle().fill(Theme.innerSurface)
      VStack(spacing: 0) {
        if raised {
          Text(verbatim: number ?? "")
            .forge(12 * k, .semibold)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .offset(y: -4 * k)
        } else {
          Text(verbatim: number ?? "")
            .forge(12 * k, .semibold)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
        if raised {
          Circle().fill(Theme.accent).frame(width: 4 * k, height: 4 * k).offset(y: 3 * k)
        }
      }
    }
  }
}

// MARK: - Week day model

/// One day of the week strip. `sessionLetter` is set on days the accepted plan schedules
/// ("Full A" → "A"); `hasEntries` keeps taps enabled for days the list can scroll to.
struct TimelineWeekDayV3: Identifiable, Equatable {
  let date: Date
  let initial: String
  let number: String
  let shape: TimelineStampV3.Shape
  let isToday: Bool
  let hasEntries: Bool
  let sessionLetter: String?
  let accessibilityLabel: String
  var id: Date { date }
}

// MARK: - Week card

/// Month + week strip card at the top of the timeline list. Same contract as the v2 card
/// (strip frame reporting, docking-driven stamp/detail opacity, month and "…" menus).
struct TimelineWeekCardV3<MonthMenu: View, MoreMenu: View>: View {
  let monthTitle: String
  let days: [TimelineWeekDayV3]
  let selectedDay: Date?
  var stampsVisible: Bool = true
  var detailOpacity: Double = 1
  let onSelectDay: (Date) -> Void
  var onStripFrame: (CGRect) -> Void = { _ in }
  @ViewBuilder let monthMenu: () -> MonthMenu
  @ViewBuilder let moreMenu: () -> MoreMenu

  init(
    monthTitle: String,
    days: [TimelineWeekDayV3],
    selectedDay: Date?,
    stampsVisible: Bool = true,
    detailOpacity: Double = 1,
    onSelectDay: @escaping (Date) -> Void,
    onStripFrame: @escaping (CGRect) -> Void = { _ in },
    @ViewBuilder monthMenu: @escaping () -> MonthMenu,
    @ViewBuilder moreMenu: @escaping () -> MoreMenu
  ) {
    self.monthTitle = monthTitle
    self.days = days
    self.selectedDay = selectedDay
    self.stampsVisible = stampsVisible
    self.detailOpacity = detailOpacity
    self.onSelectDay = onSelectDay
    self.onStripFrame = onStripFrame
    self.monthMenu = monthMenu
    self.moreMenu = moreMenu
  }

  var body: some View {
    SkyCard(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Menu {
            monthMenu()
          } label: {
            HStack(spacing: 6) {
              Text(verbatim: monthTitle)
                .forge(20, .bold)
                .foregroundStyle(Theme.text)
              Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .accessibilityIdentifier("journey.month.coverage")
          .accessibilityLabel("Month, \(monthTitle)")
          .accessibilityHint("Choose a month that has entries")
          Spacer()
          Menu {
            moreMenu()
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 20, weight: .bold))
              .foregroundStyle(Theme.text)
              .frame(width: 36, height: 36)
              .background(Circle().fill(Theme.innerSurface))
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .accessibilityLabel(String(localized: "More timeline options", bundle: L10n.bundle))
          .accessibilityIdentifier("journey.menu")
        }
        .frame(height: 44)
        HStack(spacing: 0) {
          ForEach(days) { day in
            dayColumn(day)
          }
        }
        .padding(.bottom, 7)
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .named(TimelineSpace.name))
        } action: { onStripFrame($0) }
      }
      .padding(.horizontal, 16)
      .padding(.top, 4)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.week")
  }

  private func dayColumn(_ day: TimelineWeekDayV3) -> some View {
    Button {
      onSelectDay(day.date)
    } label: {
      VStack(spacing: 4) {
        Text(verbatim: day.initial)
          .forge(13, day.isToday ? .bold : .semibold)
          .foregroundStyle(day.isToday ? Theme.accentText : Theme.textSecondary)
          .opacity(detailOpacity)
        if stampsVisible {
          TimelineStampV3(
            shape: day.shape, isToday: day.isToday, letter: day.sessionLetter, size: 34)
        } else {
          Color.clear.frame(width: 34, height: 34)
        }
        Text(verbatim: day.number)
          .forge(13, day.isToday ? .bold : .semibold)
          .foregroundStyle(day.isToday ? Theme.accentText : Theme.textSecondary)
          .monospacedDigit()
          .opacity(detailOpacity)
      }
      .frame(maxWidth: .infinity, minHeight: 84)
      .padding(.top, 6)
      .background {
        if day.date == selectedDay {
          Capsule()
            .fill(Theme.innerSurface)
            .frame(width: 44)
            .opacity(detailOpacity)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .disabled(!day.hasEntries)
    .animation(.easeOut(duration: 0.2), value: selectedDay)
    .accessibilityLabel(day.accessibilityLabel)
    .accessibilityAddTraits(day.date == selectedDay ? .isSelected : [])
    .accessibilityIdentifier("journey.week.day.\(day.number)")
  }
}

// MARK: - Docked bar

/// Pinned glass bar with mini day stamps shown while the list is scrolled.
struct TimelineDockedBarV3: View {
  let label: String
  let shortLabel: String
  let days: [TimelineWeekDayV3]
  let selectedDay: Date?
  var stampsVisible: Bool = true
  let onSelectDay: (Date) -> Void
  var onStampsFrame: (CGRect) -> Void = { _ in }

  var body: some View {
    HStack(spacing: 0) {
      ViewThatFits(in: .horizontal) {
        labelText(label, size: 15)
        labelText(label, size: 13)
        labelText(shortLabel, size: 15)
      }
      .layoutPriority(1)
      .padding(.leading, 16)
      Spacer(minLength: 8)
      HStack(spacing: 0) {
        ForEach(days) { day in
          miniStamp(day)
        }
      }
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(TimelineSpace.name))
      } action: { onStampsFrame($0) }
      .padding(.trailing, 6)
      .animation(.easeOut(duration: 0.2), value: selectedDay)
    }
    .frame(height: 52)
    .todayGlass(Capsule())
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.weekbar")
  }

  private func labelText(_ text: String, size: CGFloat) -> some View {
    Text(verbatim: text)
      .forge(size, .semibold)
      .monospacedDigit()
      .foregroundStyle(Theme.text)
      .lineLimit(1)
  }

  /// The docked-bar shape for a day: a check, the planned letter, or the day number with an
  /// accent dot when the day holds entries.
  private func barShape(_ day: TimelineWeekDayV3) -> TimelineStampV3.Shape {
    switch day.shape {
    case .done: return .done
    case .planned: return .planned
    default: return day.hasEntries ? .entryNumber : .quietNumber
    }
  }

  private func miniStamp(_ day: TimelineWeekDayV3) -> some View {
    Button {
      onSelectDay(day.date)
    } label: {
      ZStack {
        if day.date == selectedDay {
          Circle()
            .strokeBorder(Theme.accent, lineWidth: 2)
            .frame(width: 32, height: 32)
        }
        if stampsVisible {
          TimelineStampV3(
            shape: barShape(day), isToday: day.isToday, letter: day.sessionLetter, size: 26,
            number: day.number, haloOpacity: 0)
        } else {
          Color.clear.frame(width: 26, height: 26)
        }
      }
      .frame(width: 33, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .disabled(!day.hasEntries)
    .accessibilityLabel(day.accessibilityLabel)
    .accessibilityAddTraits(day.date == selectedDay ? .isSelected : [])
  }
}

// MARK: - Rail

/// Rail node kinds; each row draws its slice of the 2 pt track line.
enum TimelineNodeV3 {
  case none
  /// Move check stamp for a logged workout (carries the stamp-in animation values on the row).
  case stamp
  /// Dashed ring for the still-planned session.
  case planned
  /// Dashed hollow circle for the composer row.
  case composer
  /// 26 pt icon dot for a quiet one-line entry.
  case quietIcon(symbol: String, tint: Color)
  /// Coach avatar, for changes the coach made.
  case coach
  /// Week boundary hollow dot.
  case boundary
}

/// Row wrapper that draws the rail line and its node beside the content.
struct TimelineRailRowV3<Content: View>: View {
  let node: TimelineNodeV3
  var stampScale: CGFloat = 1
  var stampRotation: Double = 0
  var stampOpacity: Double = 1
  var nodeCenterY: CGFloat = 28
  var bottomSpacing: CGFloat = 12
  var drawsLineBelow: Bool = true
  @ViewBuilder let content: () -> Content

  init(
    node: TimelineNodeV3,
    stampScale: CGFloat = 1,
    stampRotation: Double = 0,
    stampOpacity: Double = 1,
    nodeCenterY: CGFloat = 28,
    bottomSpacing: CGFloat = 12,
    drawsLineBelow: Bool = true,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.node = node
    self.stampScale = stampScale
    self.stampRotation = stampRotation
    self.stampOpacity = stampOpacity
    self.nodeCenterY = nodeCenterY
    self.bottomSpacing = bottomSpacing
    self.drawsLineBelow = drawsLineBelow
    self.content = content
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      nodeColumn
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.bottom, bottomSpacing)
    .background(alignment: .topLeading) {
      Rectangle()
        .fill(Theme.track)
        .frame(width: 2, height: drawsLineBelow ? nil : nodeCenterY)
        .offset(x: 15)
    }
  }

  private var nodeColumn: some View {
    ZStack(alignment: .top) {
      Color.clear
      nodeView
        .frame(width: 32, height: 32)
        .offset(y: nodeCenterY - 16)
    }
    .frame(width: 32)
  }

  @ViewBuilder private var nodeView: some View {
    switch node {
    case .none:
      Color.clear
    case .stamp:
      TimelineStampV3(shape: .done, size: 32)
        .background(Circle().stroke(Theme.pageGrey, lineWidth: 4))
        .scaleEffect(stampScale)
        .rotationEffect(.degrees(stampRotation))
        .opacity(stampOpacity)
    case .planned:
      TimelineStampV3(shape: .planned, size: 32, plannedFill: Theme.pageGrey)
        .background(Circle().stroke(Theme.pageGrey, lineWidth: 4))
    case .composer:
      Circle()
        .fill(Theme.card)
        .frame(width: 14, height: 14)
        .overlay(
          Circle().strokeBorder(
            Theme.textTertiary,
            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
        .frame(width: 32, height: 32)
    case .quietIcon(let symbol, let tint):
      ZStack {
        Circle().fill(Theme.pageGrey)
        Circle().fill(tint.opacity(0.16))
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
      }
      .frame(width: 26, height: 26)
      .background(Circle().stroke(Theme.pageGrey, lineWidth: 4))
    case .coach:
      CoachAvatar(size: 32)
        .background(Circle().stroke(Theme.pageGrey, lineWidth: 4))
    case .boundary:
      Circle()
        .fill(Theme.pageGrey)
        .frame(width: 12, height: 12)
        .overlay(Circle().strokeBorder(Theme.textSecondary.opacity(0.9), lineWidth: 2))
        .background(Circle().stroke(Theme.pageGrey, lineWidth: 4))
    }
  }
}

// MARK: - Day heading

/// "Today · Fri 25 Sep" section heading, optionally tint-highlighted.
struct TimelineDayHeadingV3: View {
  let word: String
  let date: String
  var highlighted: Bool = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text(word).forge(17, .bold).foregroundStyle(Theme.text)
      Text(verbatim: date)
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .background {
      if highlighted {
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(Theme.accentTint)
          .padding(.horizontal, -8)
          .padding(.vertical, -5)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Week boundary row

/// "Week 3 · Sep 21 – 27" + "3 of 3 sessions · 8 records" between day groups.
struct TimelineWeekBoundary: View {
  let title: String
  let detail: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(verbatim: title)
        .forge(13, .semibold)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
      Spacer(minLength: 8)
      if let detail {
        Text(verbatim: detail)
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .lineLimit(1)
      }
    }
    .frame(minHeight: 30)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Quiet one-line entries

/// One quiet line: a sentence on the left, an optional value + time/delta on the right.
struct TimelineQuietLine: View {
  let title: String
  var trailing: String? = nil
  var trailingIcon: String? = nil

  var body: some View {
    HStack(alignment: .center) {
      Text(verbatim: title)
        .forge(15, .regular)
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 12)
      if let trailing {
        HStack(spacing: 3) {
          if let trailingIcon {
            Image(systemName: trailingIcon)
              .font(.system(size: 13, weight: .semibold))
          }
          Text(verbatim: trailing)
            .forge(14, .regular)
            .monospacedDigit()
            .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
      }
    }
    .frame(minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Next session card

/// "<Day> is next" card in the today group; the button wrapper starts Today's flow.
struct TimelineNextSessionCard: View {
  let title: String
  let subtitle: String?

  var body: some View {
    SkyCard(padding: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          if let subtitle {
            Text(verbatim: subtitle)
              .forge(14, .regular)
              .foregroundStyle(Theme.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.leading, 16)
      .padding(.trailing, 14)
      .padding(.vertical, 11)
    }
  }
}

// MARK: - Workout card

/// One lift token on a workout card: art disc, gold record ring when that lift set a record.
struct TimelineLiftToken: Identifiable {
  let exercise: Exercise?
  let record: Bool
  var id: String { (exercise?.id ?? "unknown") + (record ? "-rec" : "") }
}

/// One record row: "Bench Press   82.5 kg × 6".
struct TimelineRecordRow: Identifiable {
  let name: String
  let weight: String
  let unit: String
  let reps: String
  var id: String { "\(name)-\(weight)-\(reps)" }
}

/// Facts a v3 workout card draws.
struct TimelineWorkoutCardFacts {
  let title: String
  let time: String?
  let meta: String
  let tokens: [TimelineLiftToken]
  let extraTokenCount: Int
  let records: [TimelineRecordRow]
}

/// Workout card: lift tokens with record rings, up to three gold record rows.
struct TimelineWorkoutCardV3: View {
  let facts: TimelineWorkoutCardFacts

  var body: some View {
    SkyCard(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline) {
            Text(verbatim: facts.title)
              .forge(20, .bold)
              .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let time = facts.time {
              Text(verbatim: time)
                .forge(15, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            }
            Image(systemName: "chevron.right")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Theme.textSecondary)
          }
          Text(verbatim: facts.meta)
            .forge(14, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
        HStack(spacing: 10) {
          ForEach(facts.tokens.prefix(3)) { token in
            LiftToken(exercise: token.exercise, size: 40, record: token.record)
          }
          if facts.extraTokenCount > 0 {
            Circle()
              .fill(Theme.innerSurface)
              .frame(width: 40, height: 40)
              .overlay(
                Text(verbatim: "+\(facts.extraTokenCount)")
                  .forge(15, .semibold)
                  .foregroundStyle(Theme.textSecondary)
                  .monospacedDigit())
          }
        }
        .padding(.top, 12)
      }
      .padding(.horizontal, 16)
      .padding(.top, 13)
      .padding(.bottom, 14)
    } footer: {
      if !facts.records.isEmpty {
        VStack(spacing: 0) {
          Divider()
          ForEach(facts.records.prefix(3)) { row in
            recordRow(row)
          }
        }
        .padding(.vertical, 3)
      }
    }
  }

  private func recordRow(_ row: TimelineRecordRow) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "trophy.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.recordRing)
      Text(verbatim: row.name)
        .forge(15, .regular)
        .foregroundStyle(Theme.text)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(verbatim: row.weight)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
      Text(verbatim: row.unit)
        .forge(13, .medium)
        .foregroundStyle(Theme.textSecondary)
      Text(verbatim: "× \(row.reps)")
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
    }
    .frame(height: 32)
    .padding(.horizontal, 16)
  }
}

// MARK: - Plan-change card

/// One exercise load change row fact: name plus from → to.
struct TimelineChangeRowV3: Identifiable {
  let id: String
  let exercise: Exercise?
  let name: String
  let from: String?
  let to: String?
  let unit: String?
}

/// Facts a v3 plan-change group card draws.
struct TimelineChangeCardFacts {
  let title: String
  let time: String?
  let rows: [TimelineChangeRowV3]
}

/// Plan-change card: rows "Bench Press 80 → 82.5 kg", header chevron.
struct TimelineChangeCardV3: View {
  let facts: TimelineChangeCardFacts

  var body: some View {
    SkyCard(padding: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: facts.title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        if facts.rows.count <= 3 {
          VStack(spacing: 0) {
            ForEach(facts.rows) { row in
              changeRow(row)
            }
          }
        } else {
          HStack(spacing: 8) {
            ForEach(facts.rows.prefix(4)) { row in
              changeColumn(row)
            }
            if facts.rows.count > 4 {
              Circle()
                .fill(Theme.innerSurface)
                .frame(width: 40, height: 40)
                .overlay(
                  Text(verbatim: "+\(facts.rows.count - 4)")
                    .forge(15, .semibold)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit())
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 13)
      .padding(.bottom, 14)
    }
  }

  private func changeRow(_ row: TimelineChangeRowV3) -> some View {
    HStack(spacing: 10) {
      LiftToken(exercise: row.exercise, size: 32)
      Text(verbatim: row.name)
        .forge(15, .regular)
        .foregroundStyle(Theme.text)
        .lineLimit(1)
      Spacer(minLength: 8)
      if let to = row.to {
        HStack(spacing: 5) {
          if let from = row.from {
            Text(verbatim: from)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
            Text(verbatim: "→")
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
          Text(verbatim: to)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          if let unit = row.unit {
            Text(verbatim: unit)
              .forge(13, .medium)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      }
    }
    .frame(minHeight: 44)
  }

  private func changeColumn(_ row: TimelineChangeRowV3) -> some View {
    VStack(spacing: 4) {
      LiftToken(exercise: row.exercise, size: 32)
      if let to = row.to {
        HStack(spacing: 2) {
          Text(verbatim: to)
            .forge(13, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          if let unit = row.unit {
            Text(verbatim: unit)
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Note

/// Plain-text note with an optional link chip. No card: a note is just writing on the page.
struct TimelineNoteV3: View {
  let text: String
  let link: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: text)
        .forge(16, .regular)
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(6)
      if let link {
        HStack(spacing: 5) {
          Image(systemName: "link")
            .font(.system(size: 13, weight: .semibold))
          Text(verbatim: link)
            .forge(13, .medium)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
            .fill(Theme.card))
        .padding(.top, 8)
      }
    }
    .padding(.top, 2)
  }
}
