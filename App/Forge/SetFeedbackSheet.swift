import SwiftUI
import ForgeCore

/// Optional, editable feedback about one logged set.
///
/// Two branches live here on purpose. Ordinary limiter reasons stay a plain choice list; pain or
/// discomfort takes the separate safety route in `DiscomfortSafetyCopy`, which never diagnoses and
/// never turns discomfort into a reason to continue. Nothing in this sheet is required, nothing
/// here changes the program, and dismissal saves nothing.
struct SetFeedbackSheet: View {
  let set: LoggedSet
  let exerciseName: String
  let usesLb: Bool
  var onSaved: () -> Void = {}

  @Environment(\.dismiss) private var dismiss
  @State private var branch: Branch = .limiter
  @State private var reason: SetLimiterReason?
  @State private var signal: DiscomfortSignal?
  @State private var note = ""
  @State private var showDeleteConfirm = false

  private enum Branch: String, Hashable {
    case limiter
    case discomfort
  }

  private var existing: SetLimiterEvent? { self.set.setFeedback }
  private var isEditingExisting: Bool { existing != nil }

  /// The set was recorded differently after this feedback was written.
  private var isStale: Bool {
    guard let existing else { return false }
    return existing.isStale(against: set.feedbackRevision)
  }

  private var draftKind: SetLimiterKind? {
    switch branch {
    case .limiter:
      return reason.map(SetLimiterKind.limiter)
    case .discomfort:
      return signal.map { SetLimiterKind.discomfort(DiscomfortFeedback(signal: $0, note: note)) }
    }
  }

  private var draftEvent: SetLimiterEvent? {
    guard let draftKind else { return nil }
    return SetLimiterEvent.record(
      identity: set.feedbackIdentity, kind: draftKind, note: note,
      provenance: SetFeedbackProvenance(
        source: .lifter, actorID: nil, appVersion: Bundle.main.forgeVersion, capturedAt: .now),
      at: .now)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          header
          if isStale { staleNote }
          reasonList
          discomfortRoute
          if branch == .discomfort { safetyCard }
          noteField
          exclusionCard
          if isEditingExisting { removeButton }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Set feedback")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") { save() }
            .bold()
            .disabled(draftEvent == nil)
        }
      }
      .confirmationDialog("Remove this feedback?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
        Button("Remove", role: .destructive) {
          set.storeFeedback(nil)
          onSaved()
          dismiss()
        }
      } message: {
        Text("Your logged set stays exactly as recorded. It simply counts in every analysis again.")
      }
      .onAppear(perform: loadExisting)
    }
  }

  // MARK: sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(exerciseName).forgeTitle()
      Text(String(localized: "Set \(set.setIndex + 1) · \(summaryLine)", bundle: L10n.bundle))
        .forgeLabel()
        .foregroundStyle(Theme.textSecondary)
      Text("Optional. Say what ended this set so the app stops reading it as a clean performance.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var summaryLine: String {
    let weight = usesLb ? Plates.kgToLb(set.weightKg) : set.weightKg
    return "\(Fmt.num(weight)) \(usesLb ? "lb" : "kg") × \(set.reps)"
  }

  private var staleNote: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
      Text("This set was edited after you wrote this note. Saving reattaches it to the current set; your text is kept either way.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 10)
  }

  private var reasonList: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("What ended the set?").forgeSection().padding(.bottom, 6)
      ForEach(SetLimiterReason.allCases, id: \.rawValue) { candidate in
        Button {
          branch = .limiter
          reason = candidate
          signal = nil
        } label: {
          choiceRow(
            symbol: candidate.symbol,
            title: candidate.label,
            detail: candidate.detail,
            isSelected: branch == .limiter && reason == candidate)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(String(localized: "\(candidate.label). \(candidate.detail)", bundle: L10n.bundle))
        .accessibilityAddTraits(branch == .limiter && reason == candidate ? [.isSelected] : [])
        if candidate != SetLimiterReason.allCases.last {
          Rectangle().fill(Theme.ring).frame(height: 1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var discomfortRoute: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Something hurt").forgeSection()
      Button {
        branch = .discomfort
        reason = nil
        if signal == nil { signal = .noticed }
      } label: {
        choiceRow(
          symbol: "exclamationmark.triangle",
          title: "Pain or discomfort",
          detail: "Takes the separate safety route — no optimisation, no diagnosis",
          isSelected: branch == .discomfort)
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Pain or discomfort. Takes the separate safety route, no diagnosis.")
      .accessibilityAddTraits(branch == .discomfort ? [.isSelected] : [])
      if branch == .discomfort {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(DiscomfortSignal.allCases, id: \.rawValue) { candidate in
            Button {
              signal = candidate
            } label: {
              HStack(spacing: 10) {
                Image(systemName: signal == candidate ? "largecircle.fill.circle" : "circle")
                  .font(.system(size: 15, weight: .medium))
                  .foregroundStyle(signal == candidate ? Theme.accent : Theme.textTertiary)
                  .contentTransition(.symbolEffect(.replace))
                  .animation(.spring(duration: 0.3, bounce: 0), value: signal)
                  .accessibilityHidden(true)
                Text(candidate.label).forgeBody()
                Spacer(minLength: 0)
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(candidate.label)
            .accessibilityAddTraits(signal == candidate ? [.isSelected] : [])
          }
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var safetyCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "cross.case.fill")
          .foregroundStyle(Theme.accent)
          .accessibilityHidden(true)
        Text(DiscomfortSafetyCopy.headline).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
      }
      Text(DiscomfortSafetyCopy.guidance)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      Rectangle().fill(Theme.ring).frame(height: 1)
      Text(DiscomfortSafetyCopy.nextSteps)
        .forgeCaption()
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
    .accessibilityElement(children: .contain)
  }

  private var noteField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Note (optional)").forgeSection()
      TextField("Anything worth remembering about this set", text: $note, axis: .vertical)
        .lineLimit(1...3)
        .forgeBody()
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface)
        )
      Text("Notes are for you. They stay with this set and you can delete them whenever you like.")
        .forgeCaption()
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  /// One clear explanation of what this feedback keeps out of the analysis — or an honest "nothing".
  private var exclusionCard: some View {
    let scopes = draftKind.map(SetFeedbackAnalysisPolicy.excludedScopes(forKind:)) ?? []
    let explanation = SetFeedbackAnalysisPolicy.scopeExplanation(scopes)
    return VStack(alignment: .leading, spacing: 8) {
      Text("What this affects").forgeSection()
      Text(explanation ?? String(localized: "Nothing is left out — this set still counts in every analysis.", bundle: L10n.bundle))
        .forgeBody()
        .fixedSize(horizontal: false, vertical: true)
      Text("Your set is never deleted and never edited. Adherence, readiness and your program stay exactly as they are.")
        .forgeCaption()
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var removeButton: some View {
    Button(role: .destructive) {
      showDeleteConfirm = true
    } label: {
      Text("Remove feedback")
        .forgeBody()
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    }
    .foregroundStyle(Theme.negative)
    .buttonStyle(RowPressStyle())
    .accessibilityHint("Deletes only this note")
  }

  private func choiceRow(symbol: String, title: String, detail: String, isSelected: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        Text(detail).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
        .contentTransition(.symbolEffect(.replace))
        .animation(.spring(duration: 0.3, bounce: 0), value: isSelected)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 52)
    .contentShape(Rectangle())
  }

  // MARK: actions

  private func loadExisting() {
    guard let existing else { return }
    note = existing.note ?? ""
    switch existing.kind {
    case .limiter(let stored):
      branch = .limiter
      reason = stored
    case .discomfort(let stored):
      branch = .discomfort
      signal = stored.signal
    }
  }

  private func save() {
    guard let draftEvent else { return }
    // Re-attach to the current revision when the set changed under the note; the statement and
    // its creation time survive, so a derived summary is invalidated rather than rewritten.
    let toStore: SetLimiterEvent
    if let existing {
      let rebound = existing.rebinding(to: draftEvent.identity, at: .now)
      var edited = rebound
      edited.edit(kind: draftEvent.kind, note: note, at: .now)
      toStore = edited
    } else {
      toStore = draftEvent
    }
    set.storeFeedback(toStore)
    onSaved()
    dismiss()
  }
}

extension Bundle {
  /// Short marketing version for provenance. Never a device or user identifier.
  var forgeVersion: String? {
    object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }
}
