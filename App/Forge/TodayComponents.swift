import SwiftUI
import ForgeCore

struct TodayButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary }

  var kind: Kind = .primary
  var compact = false
  var fullWidth = false

  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed) {
      configuration.label
        .forge(compact ? 15 : 16, .semibold)
        .foregroundStyle(kind == .primary ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 18)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 42 : 50)
        .background(Capsule().fill(kind == .primary ? Theme.accent : Theme.innerSurface))
    }
  }
}

struct TodayHeader: View {
  let greeting: String
  let date: String
  let coachName: String
  let onCoach: () -> Void
  let onSettings: () -> Void

  var body: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 5) {
            Text(greeting)
              .lineLimit(1)
              .fixedSize()
            Text(verbatim: "·")
              .lineLimit(1)
              .fixedSize()
            Text(date)
              .lineLimit(1)
              .fixedSize()
          }
          VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
            Text(date)
          }
        }
        .forge(15, .medium)
        .foregroundStyle(Theme.text.opacity(0.72))
        Text(String(localized: "Today", bundle: L10n.bundle))
          .forge(34, .bold, tracking: -1.0)
          .foregroundStyle(Theme.text)
      }
      .accessibilityIdentifier("today.header")
      Spacer()
      Button(action: onCoach) {
        CoachAvatar(size: 40)
          .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 2))
          .frame(width: 44, height: 44)
          .contentShape(Circle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(String(localized: "Coach \(coachName)", bundle: L10n.bundle))
      Button(action: onSettings) {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 44, height: 44)
          .todayGlass(Circle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(String(localized: "Settings", bundle: L10n.bundle))
    }
  }
}

struct ExerciseArtCircle: View {
  let exercise: Exercise
  var size: CGFloat
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if UIImage(named: "ex-\(exercise.id)") != nil {
        ZStack {
          Circle().fill(Theme.accentTint)
          Image("ex-\(exercise.id)")
            .resizable()
            .scaledToFill()
            .scaleEffect(1.25)
            .blendMode(colorScheme == .light ? .multiply : .normal)
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
      } else {
        MuscleThumb(exercise: exercise, size: size)
          .clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

struct ExerciseCircles: View {
  let exercises: [Exercise]
  let appeared: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(exercises.prefix(3).enumerated()), id: \.element.id) { index, exercise in
        column(index, label: exercise.localizedName) {
          ExerciseArtCircle(exercise: exercise, size: 52)
        }
      }
      if exercises.count > 3 {
        column(3, label: String(localized: "More", bundle: L10n.bundle)) {
          ZStack {
            Circle().fill(Theme.accentTint)
            Text(verbatim: "+\(exercises.count - 3)")
              .forge(17, .bold)
              .foregroundStyle(Theme.accent)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(exercises.prefix(3).map(\.localizedName).joined(separator: ", "))
  }

  private func column<C: View>(_ index: Int, label: String, @ViewBuilder circle: () -> C) -> some View {
    VStack(spacing: 6) {
      circle()
        .frame(width: 52, height: 52)
      Text(label)
        .forge(11, .semibold)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 2)
    .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
    .opacity(appeared ? 1 : 0)
    .animation(
      reduceMotion
        ? .easeOut(duration: 0.2)
        : .spring(duration: 0.45, bounce: 0.25).delay(0.18 + Double(index) * 0.06),
      value: appeared)
  }
}

struct NextUpAction {
  let title: String
  let kind: TodayButtonStyle.Kind
  let identifier: String
  let action: () -> Void
}

struct NextUpCard: View {
  let badge: String
  let badgeSymbol: String
  var minutes: Int?
  let title: String
  let meta: String
  let exercises: [Exercise]
  let appeared: Bool
  var primary: NextUpAction?
  let onPlan: () -> Void
  let onExercises: () -> Void
  var onPrimaryVisible: (Bool) -> Void = { _ in }

  var body: some View {
    VStack(spacing: 0) {
      cover
      cardBody
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0)
  }

  private var cover: some View {
    Color.clear
      .frame(height: 124)
      .overlay(
        Image("tile-workout")
          .resizable()
          .scaledToFill())
      .clipped()
      .overlay(TodayPhotoScrim())
      .overlay(alignment: .bottomLeading) { chip(symbol: badgeSymbol, text: badge) }
      .overlay(alignment: .bottomTrailing) {
        if let minutes {
          chip(symbol: nil, text: String(localized: "≈ \(minutes) min", bundle: L10n.bundle))
        }
      }
      .accessibilityHidden(true)
  }

  private func chip(symbol: String?, text: String) -> some View {
    HStack(spacing: 5) {
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .bold))
      }
      Text(text)
        .forge(13, .semibold)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 11)
    .frame(height: 28)
    .background(Capsule().fill(Color.black.opacity(0.42)))
    .padding(12)
  }

  private var cardBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        Text(title)
          .forge(28, .bold, tracking: -0.9)
          .foregroundStyle(Theme.text)
        Text(meta)
          .forge(15, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .padding(.top, 2)
      }
      .accessibilityElement(children: .combine)
      Button(action: onExercises) {
        ExerciseCircles(exercises: exercises, appeared: appeared)
      }
      .buttonStyle(RowPressStyle())
      .padding(.top, 14)
      .accessibilityLabel(String(localized: "Planned emphasis", bundle: L10n.bundle))
      HStack(spacing: 10) {
        Button(action: onPlan) {
          Label(String(localized: "View plan", bundle: L10n.bundle), systemImage: "list.bullet")
        }
        .buttonStyle(TodayButtonStyle(kind: .secondary))
        .fixedSize()
        if let primary {
          Button(action: primary.action) {
            Text(primary.title)
          }
          .buttonStyle(TodayButtonStyle(kind: primary.kind, fullWidth: true))
          .accessibilityIdentifier(primary.identifier)
          .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY > 110 } action: { onPrimaryVisible($0) }
        }
      }
      .padding(.top, 16)
    }
    .padding(16)
  }
}

struct ReadinessPill: View {
  enum Kind {
    case checkedIn(sleepHours: Double?)
    case checkInFirst(dayName: String)
    case overlap(String)
  }

  let kind: Kind
  var action: (() -> Void)? = nil

  var body: some View {
    Group {
      if let action {
        Button(action: action) {
          label
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
      } else {
        label
      }
    }
  }

  private var label: some View {
    HStack(spacing: 7) {
      switch kind {
      case .checkedIn(let sleepHours):
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.positive)
        if let sleepHours, sleepHours > 0 {
          Text(String(localized: "Checked in · slept \(Fmt.num(sleepHours)) h", bundle: L10n.bundle))
            .forge(14, .semibold)
            .foregroundStyle(Theme.text)
        } else {
          Text(String(localized: "Checked in", bundle: L10n.bundle))
            .forge(14, .semibold)
            .foregroundStyle(Theme.text)
        }
      case .checkInFirst(let dayName):
        Image(systemName: "moon.zzz.fill")
          .font(.system(size: 15, weight: .semibold))
        Text(String(localized: "Check in before \(dayName)", bundle: L10n.bundle))
          .forge(14, .semibold)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .bold))
      case .overlap(let text):
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.metricEffort)
        Text(text)
          .forge(14, .semibold)
          .foregroundStyle(Theme.text)
      }
    }
    .foregroundStyle(kindLabelTint)
    .padding(.horizontal, 12)
    .frame(height: 34)
    .todayGlass(Capsule())
  }

  private var kindLabelTint: Color {
    if case .checkInFirst = kind { return Theme.accent }
    return Theme.text
  }
}

struct CoachCallDecision {
  let exercise: Exercise
  var badge: String? = nil
  var badgeTint: Color
  let value: String
  var valueTint: Color
  var reason: String? = nil
  let overridable: Bool
  let selection: DecisionOverride
  let whyTitle: String
}

struct CoachCallCard: View {
  let coachName: String
  var changesText: String?
  var note: String?
  var decision: CoachCallDecision?
  let onChanges: () -> Void
  let onSelect: (DecisionOverride) -> Void
  let onWhy: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      headerRow
        .padding(.horizontal, 4)
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          if let note {
            Text(note)
              .forge(15)
              .foregroundStyle(Theme.text)
          }
          if let decision {
            decisionRow(decision)
            if decision.overridable {
              overridePicker(decision)
            }
          }
        }
        .padding(16)
        if let decision {
          Button(action: onWhy) {
            HStack(spacing: 8) {
              Image(systemName: "lightbulb")
              Text(decision.whyTitle)
              Spacer()
              Image(systemName: "chevron.right")
            }
            .forge(15, .semibold)
            .foregroundStyle(Theme.accent)
            .todayFooterStrip()
          }
          .buttonStyle(RowPressStyle())
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
      .todayCard(padding: 0)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("today.coachCall")
    }
  }

  private var headerRow: some View {
    HStack(spacing: 9) {
      CoachAvatar(size: 28)
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
      Text(String(localized: "\(coachName)'s call", bundle: L10n.bundle))
        .forge(22, .bold, tracking: -0.6)
        .foregroundStyle(Theme.text)
      Spacer()
      if let changesText {
        Button(action: onChanges) {
          HStack(spacing: 1) {
            Text(changesText)
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .bold))
          }
          .forge(15, .semibold)
          .foregroundStyle(Theme.accent)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
      }
    }
  }

  private func decisionRow(_ decision: CoachCallDecision) -> some View {
    HStack(spacing: 14) {
      ExerciseArtCircle(exercise: decision.exercise, size: 60)
      VStack(alignment: .leading, spacing: 4) {
        Text(decision.exercise.localizedName)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
        HStack(spacing: 8) {
          if let badge = decision.badge {
            Text(badge)
              .forge(12, .bold)
              .foregroundStyle(decision.badgeTint)
              .padding(.horizontal, 9)
              .frame(height: 22)
              .background(Capsule().fill(decision.badgeTint.opacity(0.12)))
          }
          Text(decision.value)
            .forge(15, .medium)
            .monospacedDigit()
            .foregroundStyle(decision.valueTint)
        }
        if let reason = decision.reason {
          Text(reason)
            .forge(13, .medium)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
        }
      }
    }
  }

  private func overridePicker(_ decision: CoachCallDecision) -> some View {
    Picker(
      String(localized: "\(coachName)'s call", bundle: L10n.bundle),
      selection: Binding(
        get: { decision.selection },
        set: { onSelect($0) })
    ) {
      Text(String(localized: "Easier", bundle: L10n.bundle)).tag(DecisionOverride.easier)
      Text(String(localized: "Keep", bundle: L10n.bundle)).tag(DecisionOverride.keepOriginal)
      Text(String(localized: "Harder", bundle: L10n.bundle)).tag(DecisionOverride.harder)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .sensoryFeedback(.selection, trigger: decision.selection)
  }
}

struct TodaySessionSummary {
  let title: String
  let detail: String
  var percent: Int? = nil
}

struct WeekStampCard: View {
  let done: Int
  let target: Int
  var streakWeeks: Int
  let sessions: [WorkoutSession]
  var todayProgress: Double?
  let appeared: Bool
  var summary: TodaySessionSummary?
  var footerTitle: String?
  var onFooter: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Cell: Identifiable {
    let id: Date
    let initial: String
    let isToday: Bool
    let isDone: Bool
    let isFuture: Bool
  }

  private var weekCells: [Cell] {
    let cal = TrainingMetrics.reportingCalendar()
    var symbolCal = Calendar(identifier: .gregorian)
    symbolCal.locale = L10n.locale
    let week = TrainingMetrics.reportingWeek(containing: .now, calendar: cal)
    let today = cal.startOfDay(for: .now)
    let doneDays = Set(sessions.filter(\.completed).map { cal.startOfDay(for: $0.date) })
    return (0..<7).map { offset in
      let date = cal.date(byAdding: .day, value: offset, to: week.start) ?? week.start
      let symbol = symbolCal.veryShortWeekdaySymbols[max(0, cal.component(.weekday, from: date) - 1)]
      return Cell(
        id: cal.startOfDay(for: date),
        initial: symbol.uppercased(),
        isToday: cal.isDateInToday(date),
        isDone: doneDays.contains(cal.startOfDay(for: date)),
        isFuture: cal.startOfDay(for: date) > today)
    }
  }

  private static func cellLabel(_ cell: Cell) -> String {
    let day = cell.id.formatted(.dateTime.weekday(.wide).locale(L10n.locale))
    if cell.isDone { return String(localized: "\(day), workout done", bundle: L10n.bundle) }
    if cell.isToday { return String(localized: "\(day), today, no workout yet", bundle: L10n.bundle) }
    if cell.isFuture { return String(localized: "\(day), upcoming", bundle: L10n.bundle) }
    return String(localized: "\(day), no workout", bundle: L10n.bundle)
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        topRow
        bigNumber
          .padding(.top, 2)
        HStack(spacing: 0) {
          ForEach(weekCells) { cell in
            stampCell(cell)
          }
        }
        .padding(.top, 14)
        if let summary {
          Rectangle()
            .fill(Theme.ring)
            .frame(height: 1)
            .padding(.vertical, 16)
          summaryRow(summary)
        }
      }
      .padding(16)
      if let footerTitle {
        Button(action: onFooter) {
          HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text(footerTitle)
              .foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundStyle(Theme.accent)
          }
          .forge(15, .semibold)
          .todayFooterStrip()
        }
        .buttonStyle(RowPressStyle())
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.week")
  }

  private var topRow: some View {
    HStack {
      Text(String(localized: "This week", bundle: L10n.bundle))
        .forge(15, .semibold)
        .foregroundStyle(Theme.textSecondary)
      Spacer()
      if streakWeeks > 0 {
        HStack(spacing: 5) {
          Image(systemName: "flame.fill")
            .font(.system(size: 11, weight: .bold))
          Text(String(localized: "\(streakWeeks)-week streak", bundle: L10n.bundle))
            .forge(12, .bold)
        }
        .foregroundStyle(Theme.metricEffort)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Theme.metricEffort.opacity(0.12)))
      }
    }
  }

  private var bigNumber: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text(verbatim: "\(done)")
        .forge(52, .bold, tracking: -1.6)
        .monospacedDigit()
        .foregroundStyle(Theme.metricEffort)
      Text(String(localized: "of \(target) sessions done", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.textSecondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func stampCell(_ cell: Cell) -> some View {
    VStack(spacing: 7) {
      Text(cell.initial)
        .forge(11, .bold)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(cell.isToday ? Theme.metricEffort : Theme.textTertiary)
      stampCircle(cell)
        .frame(width: 36, height: 36)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.cellLabel(cell))
  }

  @ViewBuilder
  private func stampCircle(_ cell: Cell) -> some View {
    if cell.isDone {
      ZStack {
        Circle().stroke(Theme.metricEffort.opacity(0.18), lineWidth: 6)
        if cell.isToday {
          stamp(
            ZStack {
              Circle().fill(Theme.metricEffort)
              checkmark
            })
        } else {
          ZStack {
            Circle().fill(Theme.metricEffort)
            checkmark
          }
        }
      }
    } else if cell.isToday {
      todayRing(progress: todayProgress ?? 0)
    } else if cell.isFuture {
      Circle().strokeBorder(Theme.textTertiary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    } else {
      Circle().fill(Theme.innerSurface)
    }
  }

  private var checkmark: some View {
    Image(systemName: "checkmark")
      .font(.system(size: 14, weight: .heavy))
      .foregroundStyle(Theme.onAccent)
  }

  private func stamp<V: View>(_ content: V) -> some View {
    content
      .scaleEffect(appeared || reduceMotion ? 1 : 0.35)
      .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -14))
      .opacity(appeared ? 1 : 0)
      .animation(
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.4).delay(0.35),
        value: appeared)
  }

  private func todayRing(progress: Double) -> some View {
    ZStack {
      Circle().stroke(Theme.track, lineWidth: 3)
      if progress > 0 {
        Circle()
          .trim(from: 0, to: progress)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
      } else {
        Circle().stroke(Theme.accent, lineWidth: 2)
      }
    }
  }

  private func summaryRow(_ summary: TodaySessionSummary) -> some View {
    HStack(spacing: 14) {
      if let percent = summary.percent {
        ZStack {
          Circle().stroke(Theme.track, lineWidth: 4)
          Circle()
            .trim(from: 0, to: appeared ? min(1, Double(percent) / 100) : 0)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(
              reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.4),
              value: appeared)
          Text(verbatim: "\(percent)%")
            .forge(12, .semibold)
            .foregroundStyle(Theme.text)
        }
        .frame(width: 44, height: 44)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.title)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
        Text(summary.detail)
          .forge(15)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.goalDone")
  }
}

struct LogFoodRow: View {
  var detail: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: "fork.knife")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.accent)
          .frame(width: 42, height: 42)
          .background(Circle().fill(Theme.accentTint))
        VStack(alignment: .leading, spacing: 1) {
          Text(String(localized: "Log food", bundle: L10n.bundle))
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          if let detail {
            Text(detail)
              .forge(15)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Theme.textTertiary)
      }
      .todayCard(padding: 14)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("today.logFood")
  }
}

struct StartAccessoryBar: View {
  let title: String
  let subtitle: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 11) {
      Image("tile-workout")
        .resizable()
        .scaledToFill()
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .strokeBorder(Theme.imageOutline, lineWidth: 1))
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Text(subtitle)
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
      }
      Spacer()
      Button(action: action) {
        Label(actionTitle, systemImage: "play.fill")
      }
      .buttonStyle(TodayButtonStyle(kind: .primary, compact: true))
    }
    .padding(.horizontal, 9)
    .frame(height: 60)
    .todayGlass(Capsule())
    .padding(.horizontal, 16)
    .accessibilityIdentifier("today.startBar")
  }
}

struct TodayInlineTitle: View {
  var visible: Bool

  var body: some View {
    Text(String(localized: "Today", bundle: L10n.bundle))
      .forge(17, .semibold)
      .frame(height: 44)
      .frame(maxWidth: .infinity)
      .background(Rectangle().fill(.bar).ignoresSafeArea(edges: .top))
      .opacity(visible ? 1 : 0)
      .animation(.easeOut(duration: 0.2), value: visible)
      .allowsHitTesting(false)
      .accessibilityHidden(!visible)
  }
}
