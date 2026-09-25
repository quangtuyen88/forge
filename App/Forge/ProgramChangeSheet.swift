import SwiftUI
import SwiftData
import ForgeCore

/// One program change explained: what changed, why, where it stands, and the two ways to act on it.
/// Everything shown comes from `ProgramChangeDetail`; the sheet invents nothing.
struct ProgramChangeSheet: View {
  let detail: ProgramChangeDetail

  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var showCalculation = false
  @State private var keepTick = 0

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }
  private var exercise: Exercise? { detail.row.exerciseID.flatMap(ExerciseDB.find) }
  private var stateText: String {
    detail.state == .scheduled
      ? String(localized: "Scheduled", bundle: L10n.bundle)
      : String(localized: "Applied", bundle: L10n.bundle)
  }
  private var storedOverride: DecisionOverride? {
    detail.row.exerciseID.flatMap { DecisionOverrides.get($0) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if hasEvidence { whyCard }
          statusCard
          coachCard
          keepSection
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Program change")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  // MARK: - Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(detail.row.name)
            .forge(22, .bold, tracking: -0.8)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          if let context = detail.planContext {
            Text(context)
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          changeLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let exercise {
          ExerciseArt(exercise: exercise, size: 104)
            .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
        }
      }
      HStack(alignment: .center, spacing: 8) {
        StateChip(text: stateText, tint: detail.state == .scheduled ? Theme.metricTime : Theme.positive)
        Text(effectiveText)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.accent.opacity(0.07)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(heroAccessibilityLabel)
  }

  /// The hero follows the live override: a kept load shows as kept, and an engine proposal
  /// shows old → new even when the frozen row no longer carries it.
  @ViewBuilder private var changeLine: some View {
    if detail.state == .scheduled, storedOverride == .keepOriginal, let originalKg = detail.originalKg {
      singleValue(originalKg, label: String(localized: "Kept", bundle: L10n.bundle))
    } else if storedOverride == nil, let originalKg = detail.originalKg, let proposedKg = detail.proposedKg {
      VStack(alignment: .leading, spacing: 2) {
        targetLoadLabel
        // Old → new on one line when it fits; stacked when a long load or large text would wrap it.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            oldValue(originalKg)
            bigValue(proposedKg)
          }
          VStack(alignment: .leading, spacing: 0) {
            oldValue(originalKg)
            bigValue(proposedKg)
          }
        }
      }
    } else {
      rowChangeLine
    }
  }

  @ViewBuilder private var rowChangeLine: some View {
    switch detail.row.change {
    case .increase(let fromKg, let toKg), .decrease(let fromKg, let toKg):
      VStack(alignment: .leading, spacing: 2) {
        targetLoadLabel
        // Old → new on one line when it fits; stacked when a long load or large text would wrap it.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            oldValue(fromKg)
            bigValue(toKg)
          }
          VStack(alignment: .leading, spacing: 0) {
            oldValue(fromKg)
            bigValue(toKg)
          }
        }
      }
    case .unchanged(let kg):
      singleValue(kg, label: detail.row.kept
        ? String(localized: "Kept", bundle: L10n.bundle)
        : String(localized: "Unchanged", bundle: L10n.bundle))
    case .starting(let kg):
      singleValue(kg, label: String(localized: "Starting target", bundle: L10n.bundle))
    case .addReps(let kg):
      singleValue(kg, label: String(localized: "Same load, add a rep", bundle: L10n.bundle))
    case .other(let summary):
      Text(summary)
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
    }
  }

  private var targetLoadLabel: some View {
    Text("Target load")
      .forge(12, .medium)
      .foregroundStyle(Theme.textSecondary)
      .padding(.top, 14)
  }

  private func singleValue(_ kg: Double, label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      targetLoadLabel
      bigValue(kg)
      Text(label)
        .forge(13, .medium)
        .foregroundStyle(Theme.textSecondary)
    }
  }

  private func oldValue(_ kg: Double) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(load(kg))
        .forge(24, .semibold, tracking: -0.6)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .fixedSize()
      Image(systemName: "arrow.right")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .baselineOffset(5)
        .accessibilityHidden(true)
    }
  }

  private func bigValue(_ kg: Double) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(valuePart(kg))
        .forge(40, .bold, tracking: -1.4)
        .foregroundStyle(Theme.accent)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
      Text(unitPart(kg))
        .forge(18, .semibold)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  // MARK: - Why this changed

  private var hasEvidence: Bool {
    !evidenceLines.isEmpty || detail.lastSessionDate != nil || !detail.calculation.isEmpty
  }

  /// The keep line follows the live override, so undoing a keep in the sheet removes it.
  private var evidenceLines: [String] {
    guard detail.state == .scheduled, storedOverride == .keepOriginal, let originalKg = detail.originalKg
    else { return detail.evidence }
    return [String(localized: "You chose to keep \(load(originalKg)) for the next session.", bundle: L10n.bundle)] + detail.evidence
  }

  private var whyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Why this changed")
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      ForEach(Array(evidenceLines.enumerated()), id: \.offset) { index, sentence in
        HStack(alignment: .center, spacing: 12) {
          evidenceTile(index)
          Text(sentence)
            .forge(15)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if let last = detail.lastSessionDate {
        Text(lastSessionText(last))
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .padding(.top, 2)
        if !detail.lastSets.isEmpty {
          SetChipFlow(spacing: 6) {
            ForEach(Array(detail.lastSets.enumerated()), id: \.offset) { _, chip in
              setChip(chip)
            }
          }
        }
      }
      if !detail.calculation.isEmpty {
        calculationToggle
        if showCalculation {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(detail.calculation, id: \.self) { line in
              Text(line)
                .forge(12)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.positive.opacity(0.07)))
  }

  private func evidenceTile(_ index: Int) -> some View {
    let name = index == 0 ? "art-plan" : index == 1 ? "goal-hypertrophy" : "art-numbers"
    return Image(name)
      .resizable()
      .scaledToFit()
      .frame(width: 40, height: 40)
      .frame(width: 52, height: 52)
      .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .accessibilityHidden(true)
  }

  private func setChip(_ chip: ProgramChangeDetail.SetChip) -> some View {
    Text(String(localized: "\(load(chip.weightKg)) × \(chip.reps)", bundle: L10n.bundle))
      .forge(13, .semibold)
      .foregroundStyle(Theme.text)
      .monospacedDigit()
      .padding(.horizontal, 10)
      .frame(minHeight: 28)
      .background(Capsule().fill(Theme.card))
  }

  private var calculationToggle: some View {
    Button {
      withAnimation(.snappy) { showCalculation.toggle() }
    } label: {
      HStack(spacing: 2) {
        Text("Show calculation")
          .forge(15, .medium)
          .foregroundStyle(Theme.accent)
        Image(systemName: "chevron.down")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.accent)
          .rotationEffect(.degrees(showCalculation ? 180 : 0))
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .animation(.snappy, value: showCalculation)
  }

  // MARK: - Status

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Status")
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(detail.steps.enumerated()), id: \.offset) { index, step in
          stepRow(step, connectsDown: index < detail.steps.count - 1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 16)
  }

  /// Same rail idea as the paywall timeline: the 2pt track fills this row's height and the
  /// bottom pad carries it down to the next dot.
  private func stepRow(_ step: ProgramChangeStep, connectsDown: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        ZStack {
          Circle().fill(step.done ? Theme.positive : Theme.card).frame(width: 24, height: 24)
          if step.done {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .accessibilityHidden(true)
          } else {
            Circle().strokeBorder(Theme.metricTime, lineWidth: 2).frame(width: 24, height: 24)
          }
        }
        if connectsDown {
          Rectangle().fill(Theme.track).frame(width: 2).frame(maxHeight: .infinity)
        }
      }
      .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(step.title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
        if let text = step.detail {
          Text(text)
            .forge(12, .medium)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.bottom, connectsDown ? 14 : 0)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(stepAccessibilityLabel(step))
  }

  // MARK: - Coach card

  private var coachCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Questions about this change?")
        .forge(17, .semibold)
        .foregroundStyle(Theme.onAccent)
        .fixedSize(horizontal: false, vertical: true)
      Text(String(localized: "\(coach.name) sees this change and the sets behind it.", bundle: L10n.bundle))
        .forge(13)
        .foregroundStyle(Theme.onAccent.opacity(0.78))
        .fixedSize(horizontal: false, vertical: true)
      Button {
        CoachHandoff.shared.ask(coachQuestion)
        dismiss()
      } label: {
        Text(String(localized: "Ask \(coach.name)", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.accent)
          .padding(.horizontal, 16)
          .frame(minHeight: 36)
          .background(Capsule().fill(Theme.onAccent))
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .padding(.top, 6)
    }
    .padding(16)
    .padding(.trailing, 142)
    .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
    .overlay(alignment: .trailing) {
      Image(coach.point)
        .resizable()
        .scaledToFill()
        .frame(width: 142)
        .frame(maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.shareSurface))
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  // MARK: - Keep the old load

  @ViewBuilder private var keepSection: some View {
    if detail.state == .scheduled, let exerciseID = detail.row.exerciseID,
       detail.canKeepOriginal || storedOverride == .keepOriginal
         || (storedOverride == nil && detail.proposedKg != nil) {
      VStack(spacing: 8) {
        if storedOverride == .keepOriginal {
          if let originalKg = detail.originalKg {
            Text(String(localized: "You'll keep \(load(originalKg)) the next time you train \(detail.row.name).", bundle: L10n.bundle))
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let proposedKg = detail.proposedKg {
            plainButton(String(localized: "Use \(load(proposedKg)) instead", bundle: L10n.bundle)) {
              DecisionOverrides.set(nil, for: exerciseID)
            }
          } else {
            plainButton(String(localized: "Use the new target instead", bundle: L10n.bundle)) {
              DecisionOverrides.set(nil, for: exerciseID)
            }
          }
        } else if let originalKg = detail.originalKg {
          plainButton(String(localized: "Keep \(load(originalKg)) instead", bundle: L10n.bundle)) {
            DecisionOverrides.set(.keepOriginal, for: exerciseID)
            keepTick += 1
          }
        }
      }
      .frame(maxWidth: .infinity)
      .sensoryFeedback(.success, trigger: keepTick)
    }
  }

  private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .forge(16, .semibold)
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
  }

  // MARK: - Text helpers

  private func load(_ kg: Double) -> String {
    ProgramChanges.loadText(kg, exerciseID: detail.row.exerciseID, profile: profile)
  }

  /// `loadText` value without its unit, for the big numeral in the hero.
  private func valuePart(_ kg: Double) -> String {
    let text = load(kg)
    guard let space = text.lastIndex(of: " ") else { return text }
    return String(text[..<space])
  }

  private func unitPart(_ kg: Double) -> String {
    let text = load(kg)
    guard let space = text.lastIndex(of: " ") else { return "" }
    return String(text[text.index(after: space)...])
  }

  private var dayText: String {
    detail.dayName.isEmpty
      ? String(localized: "Workout", bundle: L10n.bundle)
      : localizedDayName(detail.dayName)
  }

  private var effectiveText: String {
    switch detail.state {
    case .scheduled:
      if let date = detail.effectiveDate {
        return String(localized: "From next \(dayText) · \(dateText(date))", bundle: L10n.bundle)
      }
      return String(localized: "From your next \(dayText)", bundle: L10n.bundle)
    case .applied:
      // Only session-start changes carry a day; the rest came from Coach, a plan or an import.
      return detail.dayName.isEmpty
        ? String(localized: "Applied to your plan", bundle: L10n.bundle)
        : String(localized: "Applied when \(dayText) started", bundle: L10n.bundle)
    }
  }

  private func lastSessionText(_ date: Date) -> String {
    let name = detail.lastSessionDayName ?? ""
    let day = name.isEmpty
      ? String(localized: "Workout", bundle: L10n.bundle)
      : localizedDayName(name)
    return String(localized: "\(dateText(date)) · \(day)", bundle: L10n.bundle)
  }

  private func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
  }

  private var coachQuestion: String {
    switch detail.row.change {
    case .other(let summary):
      return String(localized: "Can you explain this change: \(summary)?", bundle: L10n.bundle)
    case .increase(let fromKg, let toKg), .decrease(let fromKg, let toKg):
      if detail.state == .applied, let date = detail.effectiveDate {
        return String(localized: "Why did my \(detail.row.name) target change from \(load(fromKg)) to \(load(toKg)) on \(dateText(date))?", bundle: L10n.bundle)
      }
      return String(localized: "Why did my \(detail.row.name) target change from \(load(fromKg)) to \(load(toKg))?", bundle: L10n.bundle)
    case .unchanged(let kg), .starting(let kg), .addReps(let kg):
      if detail.state == .applied, let date = detail.effectiveDate {
        return String(localized: "Why was my \(detail.row.name) target \(load(kg)) on \(dateText(date))?", bundle: L10n.bundle)
      }
      if detail.state == .applied {
        return String(localized: "Why was my \(detail.row.name) target set to \(load(kg))?", bundle: L10n.bundle)
      }
      return String(localized: "Why is my \(detail.row.name) target \(load(kg)) for my next session?", bundle: L10n.bundle)
    }
  }

  private var heroAccessibilityLabel: String {
    if detail.state == .scheduled, storedOverride == .keepOriginal, let originalKg = detail.originalKg {
      return singleValueAccessibility(originalKg, label: String(localized: "Kept", bundle: L10n.bundle))
    } else if storedOverride == nil, let originalKg = detail.originalKg, let proposedKg = detail.proposedKg {
      return String(localized: "\(detail.row.name), target load \(load(originalKg)) to \(load(proposedKg)), \(stateText), \(effectiveText)", bundle: L10n.bundle)
    }
    switch detail.row.change {
    case .increase(let fromKg, let toKg), .decrease(let fromKg, let toKg):
      return String(localized: "\(detail.row.name), target load \(load(fromKg)) to \(load(toKg)), \(stateText), \(effectiveText)", bundle: L10n.bundle)
    case .unchanged(let kg):
      return singleValueAccessibility(
        kg,
        label: detail.row.kept
          ? String(localized: "Kept", bundle: L10n.bundle)
          : String(localized: "Unchanged", bundle: L10n.bundle))
    case .starting(let kg):
      return singleValueAccessibility(kg, label: String(localized: "Starting target", bundle: L10n.bundle))
    case .addReps(let kg):
      return singleValueAccessibility(kg, label: String(localized: "Same load, add a rep", bundle: L10n.bundle))
    case .other(let summary):
      return String(localized: "\(detail.row.name), \(summary), \(stateText), \(effectiveText)", bundle: L10n.bundle)
    }
  }

  private func singleValueAccessibility(_ kg: Double, label: String) -> String {
    String(localized: "\(detail.row.name), target load \(load(kg)), \(label), \(stateText), \(effectiveText)", bundle: L10n.bundle)
  }

  private func stepAccessibilityLabel(_ step: ProgramChangeStep) -> String {
    let state = step.done
      ? String(localized: "done", bundle: L10n.bundle)
      : String(localized: "pending", bundle: L10n.bundle)
    if let text = step.detail {
      return String(localized: "\(step.title), \(state), \(text)", bundle: L10n.bundle)
    }
    return String(localized: "\(step.title), \(state)", bundle: L10n.bundle)
  }
}

/// Capsule chips that wrap onto a new line when the row runs out of width.
private struct SetChipFlow: Layout {
  var spacing: CGFloat = 6

  private func rows(subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
    var rows: [[(index: Int, size: CGSize)]] = [[]]
    var x: CGFloat = 0
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + spacing + size.width > width {
        rows.append([])
        x = 0
      }
      x = x == 0 ? size.width : x + spacing + size.width
      rows[rows.count - 1].append((index, size))
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard !subviews.isEmpty else { return .zero }
    let width = proposal.width
      ?? subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width + spacing } - spacing
    let rows = rows(subviews: subviews, width: width)
    let height = rows.reduce(CGFloat(0)) {
      $0 + ($1.map(\.size.height).max() ?? 0) + spacing
    } - spacing
    let widest = rows
      .map { $0.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(0, $0.count - 1)) * spacing }
      .max() ?? 0
    return CGSize(width: widest, height: max(0, height))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(subviews: subviews, width: bounds.width) {
      let rowHeight = row.map(\.size.height).max() ?? 0
      var x = bounds.minX
      for item in row {
        subviews[item.index].place(
          at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
          anchor: .topLeading,
          proposal: ProposedViewSize(item.size))
        x += item.size.width + spacing
      }
      y += rowHeight + spacing
    }
  }
}
