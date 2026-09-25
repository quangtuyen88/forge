import SwiftUI
import ForgeCore

/// Day shape shown in the week strip, the docked bar and the rail.
enum TimelineDayState: Equatable { case done, rest, restWithEntries, today, future }

/// Round day stamp; sizes are proportional to `size` (listed values assume 36).
struct TimelineDayStamp: View {
  let state: TimelineDayState
  var size: CGFloat = 36
  /// Shown inside every non-done state (docked bar); nil in the week card.
  var number: String? = nil
  var numberOpacity: Double = 1
  /// 0...1, scales the soft ring around a done stamp (the bar uses 0).
  var haloOpacity: Double = 1

  private var k: CGFloat { size / 36 }

  private var numberView: some View {
    Text(verbatim: number ?? "")
      .forge(12 * size / 26, .semibold)
      .foregroundStyle(Theme.textSecondary)
      .monospacedDigit()
      .opacity(numberOpacity)
  }

  var body: some View {
    ZStack {
      switch state {
      case .done:
        Circle()
          .fill(Theme.metricEffort)
          .frame(width: size, height: size)
          .background(
            Circle().stroke(Theme.metricEffort.opacity(0.18 * haloOpacity), lineWidth: 6 * k))
          .overlay(
            Image(systemName: "checkmark")
              .font(.system(size: 14 * k, weight: .heavy))
              .foregroundStyle(Theme.onAccent))
      case .rest:
        Circle().fill(Theme.innerSurface)
          .frame(width: size, height: size)
        numberView
      case .restWithEntries:
        Circle().fill(Theme.innerSurface)
          .frame(width: size, height: size)
        if number != nil {
          numberView.offset(y: -2 * k)
          Circle().fill(Theme.accent)
            .frame(width: 4 * k, height: 4 * k)
            .offset(y: 8 * k)
        } else {
          Circle().fill(Theme.accent)
            .frame(width: 6 * k, height: 6 * k)
        }
      case .today:
        Circle().stroke(Theme.track, lineWidth: 3 * k)
          .frame(width: size, height: size)
        Circle().stroke(Theme.accent, lineWidth: 2 * k)
          .frame(width: size, height: size)
        numberView
      case .future:
        Circle()
          .strokeBorder(
            Theme.textTertiary.opacity(0.45),
            style: StrokeStyle(lineWidth: 1.5 * k, dash: [3 * k, 3 * k]))
          .frame(width: size, height: size)
        numberView
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// One day of the week strip.
struct TimelineWeekDay: Identifiable, Equatable {
  let date: Date        // start of day
  let initial: String   // very short weekday symbol, e.g. "M"
  let number: String    // day of month, e.g. "21"
  let state: TimelineDayState
  let isToday: Bool
  /// True when the list has a section for this day, so a tap can scroll to it.
  let hasEntries: Bool
  /// Full VoiceOver label for the cell, built by the caller.
  let accessibilityLabel: String
  var id: Date { date }
}

/// Named coordinate space the week card and docked bar report frames in.
enum TimelineSpace { static let name = "timeline" }

/// Month + week strip card at the top of the timeline list.
struct TimelineWeekCard<MonthMenu: View, MoreMenu: View>: View {
  let monthTitle: String
  let days: [TimelineWeekDay]
  let selectedDay: Date?
  /// False while the list is docking: the stamps are drawn by a travelling overlay instead.
  var stampsVisible: Bool = true
  /// 1 at rest; fades letters, numbers and the highlight while docking.
  var detailOpacity: Double = 1
  let onSelectDay: (Date) -> Void
  /// Reports the frame of the 7-stamp row in the coordinate space named `TimelineSpace.name`.
  var onStripFrame: (CGRect) -> Void = { _ in }
  @ViewBuilder let monthMenu: () -> MonthMenu
  @ViewBuilder let moreMenu: () -> MoreMenu

  init(
    monthTitle: String,
    days: [TimelineWeekDay],
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
    SkyCard(padding: 16) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Menu {
            monthMenu()
          } label: {
            HStack(spacing: 6) {
              Text(verbatim: monthTitle)
                .forge(20, .bold)
                .foregroundStyle(Theme.text)
              Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
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
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(Theme.text)
              .frame(width: 36, height: 36)
              .background(Circle().fill(Theme.innerSurface))
              .frame(width: 44, height: 44)
              .contentShape(Circle())
          }
          .accessibilityLabel(String(localized: "More timeline options", bundle: L10n.bundle))
          .accessibilityIdentifier("journey.menu")
        }
        .frame(height: 36)
        HStack(spacing: 0) {
          ForEach(days) { day in
            dayColumn(day)
          }
        }
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .named(TimelineSpace.name))
        } action: { onStripFrame($0) }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.week")
  }

  private func dayColumn(_ day: TimelineWeekDay) -> some View {
    Button {
      onSelectDay(day.date)
    } label: {
      VStack(spacing: 5) {
        Text(verbatim: day.initial)
          .forge(13, day.isToday ? .bold : .semibold)
          .foregroundStyle(day.isToday ? Theme.metricEffort : Theme.textSecondary)
          .opacity(detailOpacity)
        if stampsVisible {
          TimelineDayStamp(state: day.state)
        } else {
          Color.clear.frame(width: 36, height: 36)
        }
        Text(verbatim: day.number)
          .forge(13, day.isToday ? .bold : .semibold)
          .foregroundStyle(day.isToday ? Theme.metricEffort : Theme.textSecondary)
          .monospacedDigit()
          .opacity(detailOpacity)
      }
      .frame(maxWidth: .infinity, minHeight: 84)
      .background {
        if day.date == selectedDay {
          Capsule()
            .fill(Theme.todayFooter)
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

/// Pinned glass bar with mini day stamps shown while the list is scrolled.
struct TimelineDockedBar: View {
  let label: String                    // "21 – 27 Sep"
  let shortLabel: String               // "Sep"
  let days: [TimelineWeekDay]
  let selectedDay: Date?
  var stampsVisible: Bool = true
  let onSelectDay: (Date) -> Void
  /// Reports the frame of the 7 mini stamps' HStack in `TimelineSpace.name`.
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
      .padding(.trailing, 10)
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

  private func miniStamp(_ day: TimelineWeekDay) -> some View {
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
          TimelineDayStamp(state: day.state, size: 26, number: day.number, haloOpacity: 0)
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

/// Horizontal category filter chips under the week card.
struct TimelineFilterChips: View {
  let filter: JourneyFilter
  let onChange: (JourneyFilter) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip(String(localized: "All", bundle: L10n.bundle),
             id: "journey.filter.all",
             selected: filter.isAll) {
          onChange(.all)
        }
        chip(String(localized: "Workouts", bundle: L10n.bundle),
             id: "journey.filter.workout",
             selected: filter.categories.contains(.workout)) {
          onChange(filter.toggling(.workout))
        }
        chip(String(localized: "Plan changes", bundle: L10n.bundle),
             id: "journey.filter.programChange",
             selected: filter.categories.contains(.programChange)) {
          onChange(filter.toggling(.programChange))
        }
        chip(String(localized: "Body", bundle: L10n.bundle),
             id: "journey.filter.body",
             selected: filter.categories.contains(.body)) {
          onChange(filter.toggling(.body))
        }
        chip(String(localized: "Notes", bundle: L10n.bundle),
             id: "journey.filter.note",
             selected: filter.categories.contains(.note)) {
          onChange(filter.toggling(.note))
        }
      }
    }
    .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
  }

  private func chip(_ title: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .forge(15, selected ? .semibold : .medium)
        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 15)
        .frame(height: 36)
        .background(Capsule().fill(selected ? Theme.accent : Theme.card))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(id)
  }
}

/// Rail node kinds; each row draws its slice of the 2pt timeline line.
enum TimelineNode: Equatable { case none, stamp, composer, body, photo, note, coach, change }

/// Row wrapper that draws the timeline rail line and its node beside the content.
struct TimelineRailRow<Content: View>: View {
  let node: TimelineNode
  /// Stamp-in animation for a brand-new workout: 0.35→1 scale, -14°→0, 0→1 opacity.
  var stampScale: CGFloat = 1
  var stampRotation: Double = 0
  var stampOpacity: Double = 1
  /// Vertical offset of the node's center from the row's top (level with the card title).
  var nodeCenterY: CGFloat = 28
  /// Space under the row that still carries the rail line.
  var bottomSpacing: CGFloat = 12
  /// False on the last row of the list (the month-end footer draws its own end dot).
  var drawsLineBelow: Bool = true
  @ViewBuilder let content: () -> Content

  init(
    node: TimelineNode,
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
        .fill(Theme.accent.opacity(0.18))
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
      TimelineDayStamp(state: .done, size: 32)
        .scaleEffect(stampScale)
        .rotationEffect(.degrees(stampRotation))
        .opacity(stampOpacity)
    case .composer:
      Circle()
        .fill(Theme.card)
        .frame(width: 14, height: 14)
        .overlay(
          Circle().strokeBorder(
            Theme.textTertiary,
            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
    case .body:
      ZStack {
        Circle().fill(Theme.card)
        Circle().fill(Theme.accent.opacity(0.14))
        Image(systemName: "figure.stand")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.accent)
      }
    case .photo:
      ZStack {
        Circle().fill(Theme.card)
        Circle().fill(Theme.metricTime.opacity(0.14))
        Image(systemName: "camera.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.metricTime)
      }
    case .note:
      ZStack {
        Circle().fill(Theme.card)
        Circle().fill(Theme.accent.opacity(0.14))
        Image(systemName: "pencil")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.accent)
      }
    case .coach:
      ZStack {
        Circle().fill(Theme.card)
        CoachAvatar(size: 28)
      }
    case .change:
      ZStack {
        Circle().fill(Theme.card)
        Circle().fill(Theme.accent.opacity(0.14))
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.accent)
      }
    }
  }
}

/// "Today · Fri 25 Sep" section heading, optionally tint-highlighted.
struct TimelineDayHeading: View {
  let word: String     // "Today", "Yesterday", "Wednesday"
  let date: String     // "Fri 25 Sep" or "23 Sep"
  var highlighted: Bool = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(word).forge(20, .bold).foregroundStyle(Theme.text)
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

/// Full-width "Add a note about today" capsule button.
struct TimelineComposerRow: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "pencil")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.accent)
        Text(String(localized: "Add a note about today", bundle: L10n.bundle))
          .forge(17, .regular)
          .foregroundStyle(Theme.textSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.leading, 16)
      .background(Capsule().fill(Theme.card))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("journey.addNote")
  }
}

/// Plain-value facts for one workout card.
struct TimelineWorkoutFacts: Equatable {
  let title: String            // "Full B"
  let time: String?            // "6:10 PM"
  let meta: String             // "Week 3 · 18 sets · 58 min"
  let exercises: [Exercise]    // in logged order; first 3 shown
  let heaviestLift: String?    // "Deadlift"
  let heaviestWeight: String?  // "150"
  let heaviestUnit: String?    // "kg"
  let heaviestReps: String?    // "5"
}

/// Workout summary card with art circles and a heaviest-set footer.
struct TimelineWorkoutCard: View {
  let facts: TimelineWorkoutFacts

  var body: some View {
    SkyCard(padding: 16) {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(verbatim: facts.title)
              .forge(22, .bold)
              .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let time = facts.time {
              Text(verbatim: time)
                .forge(15, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            }
          }
          Text(verbatim: facts.meta)
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
        HStack(spacing: 8) {
          ForEach(facts.exercises.prefix(3)) { exercise in
            ExerciseArtCircle(exercise: exercise, size: 48)
          }
          if facts.exercises.count > 3 {
            Circle()
              .fill(Theme.accentTint)
              .frame(width: 48, height: 48)
              .overlay(
                Text(verbatim: "+\(facts.exercises.count - 3)")
                  .forge(17, .bold)
                  .foregroundStyle(Theme.accent))
          }
        }
      }
    } footer: {
      if let lift = facts.heaviestLift {
        heaviestFooter(lift)
      }
    }
  }

  private func heaviestFooter(_ lift: String) -> some View {
    HStack(spacing: 6) {
      Text(String(localized: "Heaviest set", bundle: L10n.bundle))
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
      Text(verbatim: lift)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
      if let weight = facts.heaviestWeight {
        Text(verbatim: weight)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
      }
      if let unit = facts.heaviestUnit {
        Text(verbatim: unit)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
      }
      Text(verbatim: "×")
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
      if let reps = facts.heaviestReps {
        Text(verbatim: reps)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.accent)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .todayFooterStrip()
    .contentShape(Rectangle())
  }
}

/// One exercise load change: name plus from → to.
struct TimelineChangeRowFacts: Identifiable, Equatable {
  let id: String
  let exercise: Exercise?
  let name: String             // "Bench Press"
  let from: String?            // "80"
  let to: String?              // "82.5"
  let unit: String?            // "kg"
}

/// Plain-value facts for a program-change group card.
struct TimelineChangeGroupFacts: Equatable {
  let title: String            // "3 loads changed" / "6 starting loads" / "Deload scheduled"
  let time: String?
  let reason: String?          // "Two easy sessions in a row"
  let rows: [TimelineChangeRowFacts]
  let footer: String           // "View changes" / "View all 6" / "View change"
}

/// Program-change card: rows up to 3, equal columns above that.
struct TimelineChangeGroupCard: View {
  let facts: TimelineChangeGroupFacts

  var body: some View {
    SkyCard(padding: 16) {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(verbatim: facts.title)
              .forge(17, .semibold)
              .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let time = facts.time {
              Text(verbatim: time)
                .forge(15, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            }
          }
          if let reason = facts.reason {
            Text(verbatim: reason)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
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
                .fill(Theme.accentTint)
                .frame(width: 40, height: 40)
                .overlay(
                  Text(verbatim: "+\(facts.rows.count - 4)")
                    .forge(17, .bold)
                    .foregroundStyle(Theme.accent))
            }
          }
        }
      }
    } footer: {
      HStack(spacing: 8) {
        Text(verbatim: facts.footer)
          .forge(17, .regular)
          .foregroundStyle(Theme.accent)
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.accent)
      }
      .todayFooterStrip()
      .contentShape(Rectangle())
    }
  }

  private func changeRow(_ row: TimelineChangeRowFacts) -> some View {
    HStack(spacing: 10) {
      LiftToken(exercise: row.exercise, size: 36)
      Text(verbatim: row.name)
        .forge(15, .regular)
        .foregroundStyle(Theme.text)
      Spacer(minLength: 8)
      if let to = row.to {
        HStack(spacing: 2) {
          if let from = row.from {
            Text(verbatim: from)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
            Text(verbatim: " → ")
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
          Text(verbatim: to)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          if let unit = row.unit {
            Text(verbatim: unit)
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
        }
      }
    }
    .frame(minHeight: 44)
  }

  private func changeColumn(_ row: TimelineChangeRowFacts) -> some View {
    VStack(spacing: 4) {
      LiftToken(exercise: row.exercise, size: 40)
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

/// Free-text note card with an optional link chip.
struct TimelineNoteCard: View {
  let text: String
  let link: String?

  var body: some View {
    SkyCard(padding: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Text(verbatim: text)
          .forge(17, .regular)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
          .lineLimit(6)
        if let link {
          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.system(size: 11, weight: .semibold))
            Text(verbatim: link)
              .forge(13, .medium)
          }
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(Capsule().fill(Theme.innerSurface))
        }
      }
    }
  }
}

/// Body-metrics card with wrapping metric pills.
struct TimelineBodyCard: View {
  let title: String
  let metrics: [String]

  var body: some View {
    SkyCard(padding: 16) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(verbatim: title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        pills
      }
    }
  }

  private var pills: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) {
        ForEach(metrics, id: \.self) { pill($0) }
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          ForEach(metrics.prefix((metrics.count + 1) / 2), id: \.self) { pill($0) }
        }
        HStack(spacing: 6) {
          ForEach(metrics.dropFirst((metrics.count + 1) / 2), id: \.self) { pill($0) }
        }
      }
    }
  }

  private func pill(_ metric: String) -> some View {
    Text(verbatim: metric)
      .forge(13, .medium)
      .foregroundStyle(Theme.textSecondary)
      .monospacedDigit()
      .padding(.horizontal, 10)
      .frame(height: 28)
      .background(Capsule().fill(Theme.innerSurface))
  }
}

/// Locked/revealed progress-photo card tile.
struct TimelinePhotoCard: View {
  let title: String
  let subtitle: String
  let revealed: Bool

  var body: some View {
    SkyCard(padding: 16) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(Theme.metricTime.opacity(0.14))
          .frame(width: 56, height: 56)
          .overlay(
            Image(systemName: revealed ? "eye" : "lock.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Theme.metricTime))
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          Text(verbatim: subtitle)
            .forge(15, .regular)
            .foregroundStyle(Theme.textSecondary)
        }
        Spacer(minLength: 8)
        if revealed {
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
      }
    }
  }
}

/// End-of-month footer with the rail's end dot and an optional continue button.
struct TimelineMonthEnd: View {
  let title: String            // "Start of September"
  let caption: String          // "Only your own records appear here. Works offline."
  let continueTitle: String?   // "Continue to August", nil when there is no earlier month
  let onContinue: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        Rectangle()
          .fill(Theme.accent.opacity(0.18))
          .frame(width: 2, height: 8)
        Circle()
          .fill(Theme.accent.opacity(0.18))
          .frame(width: 8, height: 8)
      }
      .frame(width: 32)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: title)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
        Text(verbatim: caption)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        if let continueTitle {
          Button(action: onContinue) {
            HStack(spacing: 6) {
              Text(verbatim: continueTitle)
                .forge(17, .semibold)
                .foregroundStyle(Theme.text)
              Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.card))
          }
          .buttonStyle(RowPressStyle())
          .accessibilityIdentifier("journey.month.continue")
          .padding(.top, 10)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.monthEnd")
  }
}

#Preview("Timeline components") {
  let cal = Calendar.current
  let base = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!
  let states: [TimelineDayState] = [.done, .restWithEntries, .done, .rest, .done, .future, .future]
  let initials = ["M", "T", "W", "T", "F", "S", "S"]
  let days = (0..<7).map { i in
    TimelineWeekDay(
      date: cal.date(byAdding: .day, value: i, to: base)!,
      initial: initials[i],
      number: "\(21 + i)",
      state: states[i],
      isToday: i == 4,
      hasEntries: i < 5,
      accessibilityLabel: "\(initials[i]) \(21 + i)")
  }
  let ex = ["deadlift", "overhead_press", "pull_up"].compactMap(ExerciseDB.find)
  let six = ["deadlift", "overhead_press", "pull_up", "romanian_deadlift", "front_squat", "seated_cable_row"]
    .compactMap(ExerciseDB.find)
  ScrollView {
    VStack(spacing: 12) {
      TimelineWeekCard(
        monthTitle: "September 2026",
        days: days,
        selectedDay: days[4].date,
        onSelectDay: { _ in },
        monthMenu: { Button("September 2026") {} },
        moreMenu: { Button("Settings") {} })
        .padding(.horizontal, Theme.margin)
      TimelineDockedBar(
        label: "21 – 27 Sep",
        shortLabel: "Sep",
        days: days,
        selectedDay: days[4].date,
        onSelectDay: { _ in })
        .padding(.horizontal, Theme.margin)
      TimelineFilterChips(filter: .all, onChange: { _ in })
      TimelineWorkoutCard(
        facts: TimelineWorkoutFacts(
          title: "Full B",
          time: "6:10 PM",
          meta: "Week 3 · 18 sets · 58 min",
          exercises: ex,
          heaviestLift: "Deadlift",
          heaviestWeight: "150",
          heaviestUnit: "kg",
          heaviestReps: "5"))
        .padding(.horizontal, Theme.margin)
      TimelineChangeGroupCard(
        facts: TimelineChangeGroupFacts(
          title: "3 loads changed",
          time: "6:12 PM",
          reason: "Two easy sessions in a row",
          rows: [
            TimelineChangeRowFacts(id: "1", exercise: ex.first, name: "Deadlift", from: "80", to: "82.5", unit: "kg"),
            TimelineChangeRowFacts(id: "2", exercise: ex.count > 1 ? ex[1] : nil, name: "Overhead Press", from: "45", to: "47.5", unit: "kg"),
            TimelineChangeRowFacts(id: "3", exercise: ex.count > 2 ? ex[2] : nil, name: "Pull-Up", from: nil, to: "10", unit: "kg"),
          ],
          footer: "View changes"))
        .padding(.horizontal, Theme.margin)
      TimelineChangeGroupCard(
        facts: TimelineChangeGroupFacts(
          title: "6 starting loads",
          time: "6:30 PM",
          reason: nil,
          rows: six.enumerated().map { i, exercise in
            TimelineChangeRowFacts(
              id: "\(i)",
              exercise: exercise,
              name: exercise.name,
              from: nil,
              to: "\(40 + i * 5)",
              unit: "kg")
          },
          footer: "View all 6"))
        .padding(.horizontal, Theme.margin)
      TimelineNoteCard(
        text: "Felt strong today. Bar speed was crisp on every set and the last deadlift moved fast.",
        link: "regulift.app")
        .padding(.horizontal, Theme.margin)
      TimelineBodyCard(
        title: "Body",
        metrics: ["Weight 82.5 kg", "Sleep 7 h 20 m", "Steps 9,340", "Waist 84 cm"])
        .padding(.horizontal, Theme.margin)
      TimelinePhotoCard(title: "Progress photo", subtitle: "Fri 25 Sep", revealed: false)
        .padding(.horizontal, Theme.margin)
      TimelineMonthEnd(
        title: "Start of September",
        caption: "Only your own records appear here. Works offline.",
        continueTitle: "Continue to August",
        onContinue: {})
        .padding(.horizontal, Theme.margin)
    }
  }
  .background(TodaySkyPage())
}
