import ForgeCore
import SwiftData
import SwiftUI

/// Which plan input a sentence chip edits.
enum PlanChoice: String, Identifiable {
  case days, minutes, goal
  var id: String { rawValue }
}

/// The sheet behind one plan chip: each option's week and weekly sets; the check applies the pick.
struct PlanChoiceSheet: View {
  let choice: PlanChoice
  let profile: UserProfile
  let sessions: [WorkoutSession]
  let advice: String?
  @Binding var pending: String?
  let onConfirm: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var options: [PlanOption] = []
  @State private var selected = ""

  init(choice: PlanChoice, profile: UserProfile, sessions: [WorkoutSession], advice: String?,
       pending: Binding<String?>, onConfirm: @escaping (String) -> Void) {
    self.choice = choice
    self.profile = profile
    self.sessions = sessions
    self.advice = advice
    self._pending = pending
    self.onConfirm = onConfirm
  }

  private var title: String {
    switch choice {
    case .days: return String(localized: "Days a week", bundle: L10n.bundle)
    case .minutes: return String(localized: "Session length", bundle: L10n.bundle)
    case .goal: return String(localized: "Goal", bundle: L10n.bundle)
    }
  }

  private var currentSets: Int { options.first(where: \.isCurrent)?.weeklySets ?? 0 }
  private var isCurrentSelected: Bool { options.first { $0.id == selected }?.isCurrent ?? true }

  private var footer: String {
    if isCurrentSelected {
      return String(localized: "Your plan now. Pick another to see what changes.", bundle: L10n.bundle)
    }
    return String(
      localized: "Applies from today. Workouts you finished stay saved, and you stay in week \(profile.currentWeek(sessions: sessions)) of \(Mesocycle.weeks).",
      bundle: L10n.bundle)
  }

  var body: some View {
    PlanChoiceSheetScaffold(title: title, footer: footer, advice: isCurrentSelected ? nil : advice, onConfirm: confirm) {
      ForEach(options) { option in
        PlanOptionRow(
          title: option.title, detail: option.detail, sets: option.weeklySets,
          delta: option.weeklySets - currentSets, isCurrent: option.isCurrent,
          selected: option.id == selected) {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { selected = option.id }
          pending = option.id
        }
        .accessibilityIdentifier("settings.option.\(choice.rawValue).\(option.id)")
      }
    }
    .onAppear {
      guard options.isEmpty else { return }
      let input = profile.profileInput
      let week = profile.currentWeek(sessions: sessions)
      switch choice {
      case .days: options = PlanPreview.dayOptions(input: input, week: week)
      case .minutes: options = PlanPreview.minuteOptions(input: input, week: week)
      case .goal: options = PlanPreview.goalOptions(input: input, week: week)
      }
      selected = options.first(where: \.isCurrent)?.id ?? options.first?.id ?? ""
    }
  }

  private func confirm() {
    if !selected.isEmpty { onConfirm(selected) }
    dismiss()
  }
}

/// Plan facts under the sentence: experience, split, the program routes, and the coach's exercise swaps.
struct PlanDetailsPage: View {
  @Bindable var profile: UserProfile
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext
  @State private var confirmRestart = false

  init(profile: UserProfile) { self.profile = profile }

  private var week: Int { profile.currentWeek(sessions: sessions) }
  private var split: SplitStyle { SplitStyle(rawValue: profile.split) ?? .auto }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Plan details", bundle: L10n.bundle)) {
      SettingsHero(
        title: String(localized: "Week \(week) of \(Mesocycle.weeks).", bundle: L10n.bundle),
        subtitle: String(localized: "Changes apply from today. Finished workouts stay saved.", bundle: L10n.bundle),
        art: "art-plan")
    } content: {
      SettingsSectionLabel(String(localized: "Experience", bundle: L10n.bundle))
      Picker(String(localized: "Experience", bundle: L10n.bundle), selection: experienceBinding) {
        ForEach(Experience.allCases, id: \.self) { Text($0.name).tag($0) }
      }
      .pickerStyle(.segmented)
      .padding(.top, 8)
      .accessibilityIdentifier("settings.plan.experience")

      SettingsSectionLabel(String(localized: "Split", bundle: L10n.bundle))
      ForEach(Array(SplitStyle.allCases.enumerated()), id: \.element) { index, style in
        if index > 0 { SettingsHairline(inset: false) }
        splitRow(style)
      }

      SettingsSectionLabel(String(localized: "Program", bundle: L10n.bundle))
      NavigationLink {
        ProgramRoadmapView()
      } label: {
        SettingsRow(title: String(localized: "Program & data", bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("settings.plan.roadmap")
      .accessibilityValue(
        String(localized: "Program roadmap, week designer, goals and program import", bundle: L10n.bundle))
      SettingsHairline(inset: false)
      NavigationLink {
        TrainingConstraintsView()
      } label: {
        SettingsRow(title: String(localized: "Training setup & modes", bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("settings.plan.constraints")
      SettingsHairline(inset: false)
      Button {
        confirmRestart = true
      } label: {
        SettingsRow(
          title: String(localized: "Restart training block", bundle: L10n.bundle),
          titleColor: Theme.negative, accessory: .none)
      }
      .buttonStyle(RowPressStyle())

      if !profile.exerciseOverrides.isEmpty {
        SettingsSectionLabel(String(localized: "Exercise swaps", bundle: L10n.bundle))
        ForEach(Array(profile.exerciseOverrides.sorted { $0.key < $1.key }.enumerated()), id: \.element.key) {
          index, override in
          if index > 0 { SettingsHairline(inset: false) }
          SettingsRow(title: "\(name(override.key)) → \(name(override.value))", accessory: .none) {
            Button {
              profile.exerciseOverrides.removeValue(forKey: override.key)
              touch()
            } label: {
              Image(systemName: "minus.circle.fill")
                .scaledSystemFont(20)
                .foregroundStyle(Theme.negative)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(
              String(
                localized: "Remove swap: \(name(override.key)) to \(name(override.value))",
                bundle: L10n.bundle))
          }
        }
      }
    }
    .confirmationDialog(
      String(localized: "Start a fresh 6-week block?", bundle: L10n.bundle),
      isPresented: $confirmRestart, titleVisibility: .visible
    ) {
      Button(String(localized: "Restart training block", bundle: L10n.bundle), role: .destructive) {
        profile.startNewBlock()
        touch()
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized: "Applied routines, block start, next day, deload, and set and rep-range adjustments reset. Workouts you've logged stay saved.",
          bundle: L10n.bundle))
    }
  }

  private var experienceBinding: Binding<Experience> {
    Binding(
      get: { Experience(rawValue: profile.experience) ?? .intermediate },
      set: {
        profile.experience = $0.rawValue
        touch()
      })
  }

  private func splitRow(_ style: SplitStyle) -> some View {
    Button {
      profile.split = style.rawValue
      profile.reviseWeekPlan(sessions: sessions)
      touch()
    } label: {
      SettingsRow(
        title: style.name,
        subtitle: PlanPreview.splitDescription(days: profile.daysPerWeek, style: style),
        accessory: .none) {
        if split == style {
          Image(systemName: "checkmark")
            .scaledSystemFont(17, weight: .semibold)
            .foregroundStyle(Theme.accentText)
        } else {
          Color.clear.frame(width: 17)
        }
      }
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(split == style ? .isSelected : [])
    .accessibilityIdentifier("settings.plan.split.\(style.rawValue)")
  }

  private func name(_ id: String) -> String {
    ExerciseDB.find(id)?.localizedName ?? id
  }
}

/// Rest between sets: the defaults for big and small lifts, with per-exercise overrides listed below.
struct RestTimerPage: View {
  @Bindable var profile: UserProfile
  @Environment(\.modelContext) private var modelContext
  @State private var confirmResetTimers = false

  init(profile: UserProfile) { self.profile = profile }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Rest timer", bundle: L10n.bundle)) {
      SettingsHero(
        title: String(
          localized: "Big lifts rest \(SettingsFormat.mmss(profile.restCompoundSeconds)).", bundle: L10n.bundle),
        subtitle: String(
          localized: "Others rest \(SettingsFormat.mmss(profile.restIsolationSeconds)). A lift’s own timer, set during a workout, wins.",
          bundle: L10n.bundle),
        art: "art-rest")
    } content: {
      Spacer().frame(height: 10)
      Stepper(value: restBinding(\.restCompoundSeconds), in: 60...300, step: 15) {
        stepperLabel(
          title: String(localized: "Big lifts", bundle: L10n.bundle),
          caption: String(localized: "Squats, presses, rows, pull-ups", bundle: L10n.bundle),
          seconds: profile.restCompoundSeconds)
      }
      SettingsHairline(inset: false)
      Stepper(value: restBinding(\.restIsolationSeconds), in: 30...180, step: 15) {
        stepperLabel(
          title: String(localized: "Other lifts", bundle: L10n.bundle),
          caption: String(localized: "Curls, raises, calves, core", bundle: L10n.bundle),
          seconds: profile.restIsolationSeconds)
      }
      if !profile.restOverrides.isEmpty {
        SettingsHairline(inset: false)
        Text(
          String(
            localized: "\(profile.restOverrides.count) lift\(L10n.pluralSuffix(profile.restOverrides.count)) keep their own timer.",
            bundle: L10n.bundle)
        )
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 12)
        .fixedSize(horizontal: false, vertical: true)
        Button {
          confirmResetTimers = true
        } label: {
          SettingsRow(
            title: String(localized: "Reset per-exercise timers", bundle: L10n.bundle),
            titleColor: Theme.negative, accessory: .none)
        }
        .buttonStyle(RowPressStyle())
      }
    }
    .confirmationDialog(
      String(localized: "Reset every exercise's rest time?", bundle: L10n.bundle),
      isPresented: $confirmResetTimers, titleVisibility: .visible
    ) {
      Button(String(localized: "Reset", bundle: L10n.bundle), role: .destructive) {
        profile.restOverrides = [:]
        touch()
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    }
  }

  private func stepperLabel(title: String, caption: String, seconds: Int) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forge(17).foregroundStyle(Theme.text)
        Text(caption).forge(15).foregroundStyle(Theme.textSecondary)
      }
      Spacer()
      Text(SettingsFormat.mmss(seconds))
        .forge(17, .medium)
        .monospacedDigit()
        .foregroundStyle(Theme.text)
    }
    .padding(.vertical, 8)
    .frame(minHeight: 52)
  }

  private func restBinding(_ kp: ReferenceWritableKeyPath<UserProfile, Int>) -> Binding<Int> {
    Binding(
      get: { profile[keyPath: kp] },
      set: {
        profile[keyPath: kp] = $0
        touch()
      })
  }
}

/// Injury flags: each one swaps the lifts that load it, and bad sleep or stress trims the week.
struct InjuriesPage: View {
  @Bindable var profile: UserProfile
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  init(profile: UserProfile) { self.profile = profile }

  private var coach: Coach { Coach.from(coachID) }
  private var flags: [InjuryFlag] { InjuryFlag.allCases.filter { profile.injuryFlags.contains($0.rawValue) } }
  private var swaps: [ExerciseSwap] {
    var noFlags = profile.profileInput
    noFlags.injuryFlags = []
    return Personalization.exerciseSwapDetails(before: noFlags, after: profile.profileInput)
  }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  private var heroTitle: String {
    flags.isEmpty
      ? String(localized: "No injuries flagged.", bundle: L10n.bundle)
      : String(
        localized: "\(ListFormatter.localizedString(byJoining: flags.map(\.name))) flagged.",
        bundle: L10n.bundle)
  }

  private var heroSubtitle: String {
    if flags.isEmpty {
      return String(localized: "Flag one and \(coach.name) swaps the lifts that load it.", bundle: L10n.bundle)
    }
    if swaps.isEmpty {
      return String(localized: "No lift in your plan loads it.", bundle: L10n.bundle)
    }
    return String(
      localized: "\(swaps.count) lift\(L10n.pluralSuffix(swaps.count)) swapped for safer ones.",
      bundle: L10n.bundle)
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Injuries & recovery", bundle: L10n.bundle)) {
      SettingsHero(title: heroTitle, subtitle: heroSubtitle, art: "art-injury")
    } content: {
      SettingsSectionLabel(String(localized: "Injuries", bundle: L10n.bundle))
      ForEach(Array(InjuryFlag.allCases.enumerated()), id: \.element) { index, flag in
        if index > 0 { SettingsHairline(inset: false) }
        SettingsToggleRow(title: flag.name, isOn: injuryBinding(flag))
          .accessibilityIdentifier("settings.injury.\(flag.rawValue)")
      }

      if !swaps.isEmpty {
        SettingsSectionLabel(String(localized: "What changes", bundle: L10n.bundle))
        ForEach(Array(swaps.enumerated()), id: \.offset) { index, swap in
          if index > 0 { SettingsHairline(inset: false) }
          SettingsRow(title: swap.toName ?? swap.fromName ?? "", subtitle: swap.detail, accessory: .none)
        }
      }

      SettingsSectionLabel(String(localized: "Recovery", bundle: L10n.bundle))
      SettingsToggleRow(
        title: String(localized: "I sleep under 6 h or life stress is high", bundle: L10n.bundle),
        subtitle: recoveryLine,
        isOn: Binding(
          get: { profile.recoveryReduced },
          set: {
            profile.recoveryReduced = $0
            touch()
          }))
        .accessibilityIdentifier("recovery-reduced-toggle")
    }
  }

  private func injuryBinding(_ flag: InjuryFlag) -> Binding<Bool> {
    Binding(
      get: { profile.injuryFlags.contains(flag.rawValue) },
      set: { on in
        var set = Set(profile.injuryFlags)
        if on { set.insert(flag.rawValue) } else { set.remove(flag.rawValue) }
        profile.injuryFlags = set.sorted()
        touch()
      })
  }

  /// Truthful at all times: the sets this week's plan actually loses when recovery is limited.
  private var recoveryLine: String {
    let week = profile.currentWeek(sessions: sessions)
    var on = profile.profileInput
    on.recoveryReduced = true
    var off = profile.profileInput
    off.recoveryReduced = false
    let cut = PlanPreview.weeklySets(Program.week(week, profile: off))
      - PlanPreview.weeklySets(Program.week(week, profile: on))
    return cut > 0
      ? String(localized: "Takes \(cut) sets off your week.", bundle: L10n.bundle)
      : String(localized: "No change to this week’s sets.", bundle: L10n.bundle)
  }
}
