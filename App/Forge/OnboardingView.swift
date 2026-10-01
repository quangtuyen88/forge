import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import ForgeCore

struct OnboardingView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(AuthClient.self) private var auth

  /// One enum drives the stage bar, the page switch and the CTA label, so adding a step can never leave them disagreeing.
  private enum Step: Int, CaseIterable {
    case welcome, coach, name, science, goal, experience, loop, days, length, equipment, numbers, workarounds, photo, building, summary
  }

  @State private var step: Step = .welcome
  @State private var savedTick = 0
  @State private var goingForward = true
  @State private var goal: Goal = .hypertrophy
  @State private var experience: Experience = .intermediate
  @State private var daysPerWeek = 3
  @State private var sessionLength: SessionLength = .m60
  @State private var equipment: Set<Equipment> = []
  @State private var gymPreset: GymPreset? = nil
  @State private var usesLb = false
  @State private var bodyweightText = ""
  @State private var rulerTick = 0
  @State private var lifts: [String: String] = [:]
  @State private var injuries: Set<InjuryFlag> = []
  @State private var recoveryReduced = false
  @State private var buildProgress: Double = 0
  @State private var buildTicks = 0
  @State private var planShown = false
  @State private var customiseOpen = false
  @State private var liftsOpen = false
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?
  @State private var displayName = ""
  @State private var showSignIn = false
  @State private var welcomePhotoShown = false
  @State private var welcomeSheetShown = false
  @State private var welcomeTextShown = false
  @State private var loopCardShown = false
  @State private var rpeBarsFilled = 0
  @State private var buildShown = false
  @FocusState private var focusedField: Field?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  private enum Question: Hashable { case goal, experience, days, length }
  @State private var answered: Set<Question> = []

  private enum Field: Hashable {
    case name
    case bodyweight
    case lift(String)
  }

  private var liftIDs: [String] {
    // Week 1 with injury flags cleared keeps this list stable through the Work around step;
    // bodyweight and bands carry no load, so they never get a current-lift field.
    let profile = ProfileInput(
      goal: goal, experience: experience, daysPerWeek: daysPerWeek,
      sessionLength: sessionLength, equipment: equipment, injuryFlags: [])
    let planned = Program.week(1, profile: profile).flatMap(\.exercises).map(\.exercise)
    let fill = ExerciseDB.matching(equipment: equipment)
    var seen = Set<String>()
    var ids: [String] = []
    for exercise in planned + fill {
      guard exercise.isCompound,
            exercise.equipment != .bodyweight,
            exercise.equipment != .bands,
            !seen.contains(exercise.id) else { continue }
      seen.insert(exercise.id)
      ids.append(exercise.id)
      if ids.count == 5 { break }
    }
    return ids
  }

  private let equipmentSymbols: [Equipment: String] = [
    .barbell: "dumbbell",
    .dumbbell: "dumbbell.fill",
    .machine: "gearshape.2",
    .cable: "cable.connector",
    .bodyweight: "figure.core.training",
    .bands: "circle.dashed",
  ]

  private var bodyweightKg: Double {
    guard let v = number(bodyweightText) else { return 0 }
    let kg = usesLb ? Plates.lbToKg(v) : v
    return (25...350).contains(kg) ? kg : 0
  }

  private var bodyweightValid: Bool {
    guard let v = number(bodyweightText) else { return false }
    let kg = usesLb ? Plates.lbToKg(v) : v
    return (25...350).contains(kg)
  }

  private var bodyweightInvalid: Bool {
    !bodyweightText.trimmingCharacters(in: .whitespaces).isEmpty && !bodyweightValid
  }

  private var bodyweightRangeText: String {
    if usesLb {
      let lo = Int(Plates.kgToLb(25).rounded())
      let hi = Int(Plates.kgToLb(350).rounded())
      return "\(lo)–\(hi) lb"
    }
    return "25–350 kg"
  }

  /// Where the ruler rests until the lifter moves it or types a value.
  private var rulerStart: Double { usesLb ? 155 : 70 }

  /// The ruler reads the typed value; a drag writes back inside the valid bodyweight range.
  private var bodyweightRulerBinding: Binding<Double> {
    let lo = usesLb ? Plates.kgToLb(25).rounded() : 25
    let hi = usesLb ? Plates.kgToLb(350).rounded() : 350
    return Binding(
      get: { number(bodyweightText) ?? rulerStart },
      set: { bodyweightText = Fmt.num(min(max($0, lo), hi)) })
  }

  private var input: ProfileInput {
    ProfileInput(
      goal: goal,
      experience: experience,
      daysPerWeek: daysPerWeek,
      sessionLength: sessionLength,
      equipment: equipment,
      injuryFlags: injuries,
      recoveryReduced: recoveryReduced)
  }

  private var canContinue: Bool {
    switch step {
    case .goal: return answered.contains(.goal)
    case .experience: return answered.contains(.experience)
    case .days: return answered.contains(.days)
    case .length: return answered.contains(.length)
    case .equipment: return !equipment.isEmpty
    case .numbers: return bodyweightValid
    default: return true
    }
  }

  private func advance() {
    goingForward = true
    if step == .summary { save(); return }
    let next = Step(rawValue: step.rawValue + 1) ?? .summary
    withAnimation(.snappy) { step = next }
  }

  private func goBack() {
    goingForward = false
    guard let prev = Step(rawValue: step.rawValue - 1) else { return }
    // Building always runs forward into the summary; going back from it means the photo.
    let target = step == .summary && prev == .building ? Step.photo : prev
    withAnimation(.snappy) { step = target }
  }

  private func trackStep(_ step: Step) {
    Analytics.track("onboarding_step", ["step": "\(step.rawValue)", "name": "\(step)"])
  }

  private var pageTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .push(from: goingForward ? .trailing : .leading),
        removal: .opacity.animation(.easeOut(duration: 0.15)))
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        ZStack {
          switch step {
          case .welcome: welcomePage.transition(pageTransition)
          case .coach: coachPage.transition(pageTransition)
          case .name: namePage.transition(pageTransition)
          case .science: sciencePage.transition(pageTransition)
          case .goal: goalPage.transition(pageTransition)
          case .experience: experiencePage.transition(pageTransition)
          case .loop: loopPage.transition(pageTransition)
          case .days: daysPage.transition(pageTransition)
          case .length: lengthPage.transition(pageTransition)
          case .equipment: equipmentPage.transition(pageTransition)
          case .numbers: numbersPage.transition(pageTransition)
          case .workarounds: workaroundsPage.transition(pageTransition)
          case .photo: photoPage.transition(pageTransition)
          case .building: buildingPage.transition(pageTransition)
          case .summary: summaryPage.transition(pageTransition)
          }
        }
        header
      }
      .background(Theme.page.ignoresSafeArea())
      .statusBarHidden(step == .welcome)
      .toolbar(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focusedField = nil }
        }
      }
      .sensoryFeedback(.selection, trigger: step)
      .sensoryFeedback(.success, trigger: savedTick)
      .onAppear { trackStep(.welcome) }
      .onChange(of: step) { _, new in
        focusedField = nil
        trackStep(new)
      }
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self) { photoData = data }
        }
      }
      .onChange(of: showSignIn) { _, showing in
        // A synced profile makes the root leave onboarding by itself.
        guard !showing, auth.user != nil else { return }
        Task { await SyncEngine.shared.sync() }
      }
      .sheet(isPresented: $showSignIn) { AccountView() }
      .safeAreaInset(edge: .bottom) { ctaBar }
    }
  }

  @ViewBuilder private var ctaBar: some View {
    if step != .name && step != .building {
      VStack(spacing: 8) {
        if let blockedReason {
          Text(blockedReason)
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboarding-blocked-reason")
        }
        if step == .photo && photoData == nil {
          PhotosPicker(selection: $photoItem, matching: .images) {
            Text(String(localized: "Choose photo", bundle: L10n.bundle))
          }
          .buttonStyle(PillButtonStyle())
        } else {
          Button {
            advance()
          } label: {
            Text(ctaTitle)
          }
          .buttonStyle(PillButtonStyle())
          .disabled(!canContinue)
        }
        if step == .welcome {
          Button {
            showSignIn = true
          } label: {
            Text(String(localized: "I already have an account", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.textSecondary)
              .frame(height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
          .accessibilityIdentifier("onboarding-sign-in")
        }
        if step == .summary {
          Text(String(localized: "Next: choose a subscription", bundle: L10n.bundle))
            .forgeCaption()
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: blockedReason)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
  }

  private var ctaTitle: String {
    switch step {
    case .welcome: return String(localized: "Build my plan", bundle: L10n.bundle)
    case .science, .loop: return String(localized: "Got it", bundle: L10n.bundle)
    case .summary: return String(localized: "Save this plan", bundle: L10n.bundle)
    default: return String(localized: "Continue", bundle: L10n.bundle)
    }
  }

  /// The Finch pattern: the back button, the stage bar and the coach's face stay put while pages push in and out.
  /// The header is opaque so long pages scroll under it unseen.
  private var header: some View {
    VStack(spacing: 10) {
      topBar
      if anchorVisible {
        anchor
          .transition(.opacity)
      }
    }
    .padding(.bottom, 4)
    .background(topBarHidden ? Color.clear : Theme.page)
    .animation(reduceMotion ? nil : .snappy, value: anchorVisible)
  }

  /// The chosen coach anchoring every question; the reply below speaks with this face.
  private var anchor: some View {
    Image(coach.face).resizable().scaledToFill()
      .frame(width: 56, height: 56)
      .clipShape(Circle())
      .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var anchorVisible: Bool {
    switch step {
    case .name, .goal, .experience, .days, .length, .equipment, .numbers, .workarounds, .photo, .summary: return true
    default: return false
    }
  }

  /// Back and progress share one row; the bar keeps its height when hidden so content does not jump.
  private var topBar: some View {
    HStack(spacing: 12) {
      Button {
        goBack()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(String(localized: "Go back", bundle: L10n.bundle))
      .opacity(step == .welcome ? 0 : 1)
      .disabled(step == .welcome)
      .accessibilityHidden(step == .welcome)
      stageBar
      if step == .photo {
        Button {
          advance()
        } label: {
          Text(String(localized: "Skip", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("onboarding-skip")
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 4)
    .opacity(topBarHidden ? 0 : 1)
    .disabled(topBarHidden)
    .accessibilityHidden(topBarHidden)
  }

  private var topBarHidden: Bool { step == .welcome || step == .building }

  /// Three stages (About you 1–5 · Your week 6–12 · Your plan 13–14), widths proportional to their step counts.
  private var stageBar: some View {
    GeometryReader { geo in
      let usable = max(0, geo.size.width - 8)
      HStack(spacing: 4) {
        stageSegment(width: usable * 5 / 14, range: 1...5)
        stageSegment(width: usable * 7 / 14, range: 6...12)
        stageSegment(width: usable * 2 / 14, range: 13...14)
      }
    }
    .frame(height: 4)
    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: step)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
  }

  private func stageSegment(width: CGFloat, range: ClosedRange<Int>) -> some View {
    let done = min(1, max(0, Double(step.rawValue - range.lowerBound + 1) / Double(range.count)))
    return Capsule()
      .fill(Theme.track)
      .frame(width: max(0, width))
      .overlay(alignment: .leading) {
        if done > 0 {
          Capsule()
            .fill(Theme.accent)
            .frame(width: max(0, width * done))
        }
      }
  }

  /// Why Continue is off, said next to the button.
  private var blockedReason: String? {
    guard !canContinue else { return nil }
    switch step {
    case .goal, .experience, .days, .length:
      return String(localized: "Choose one to continue.", bundle: L10n.bundle)
    case .equipment:
      return String(localized: "Pick a gym, or choose at least one piece of equipment.", bundle: L10n.bundle)
    case .numbers:
      return bodyweightInvalid
        ? String(localized: "Bodyweight must be between \(bodyweightRangeText).", bundle: L10n.bundle)
        : String(localized: "Drag the ruler or tap the number.", bundle: L10n.bundle)
    default: return nil
    }
  }

  /// Question pages start ~10 pt under the face; pages without it start under the top bar.
  private var pageTopPadding: CGFloat { anchorVisible ? 122 : 56 }

  private func page(
    title: String,
    accent: String? = nil,
    subtitle: String? = nil,
    @ViewBuilder content: () -> some View
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          titleText(title, accent: accent)
            .forgeGreeting()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          if let subtitle {
            Text(subtitle)
              .forge(15)
              .foregroundStyle(Theme.textSecondary)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        VStack(alignment: .leading, spacing: 16) {
          content()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, pageTopPadding)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  /// Statement pages: one photo card under the top bar, the copy 22 pt under it.
  private func statementPage(
    photo: String,
    title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> some View
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        PhotoCard(name: photo)
        VStack(alignment: .leading, spacing: 8) {
          titleText(title, accent: nil)
            .forgeGreeting()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          if let subtitle {
            Text(subtitle)
              .forge(15)
              .foregroundStyle(Theme.textSecondary)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, Theme.margin)
        content()
          .padding(.horizontal, Theme.margin)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.top, 60)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private func titleText(_ title: String, accent: String?) -> Text {
    guard let accent else { return Text(title) }
    return Text(title) + Text(" ") + Text(accent).foregroundStyle(Theme.accentText)
  }

  /// The coach's one-line answer under a choice; no avatar, the face above the question is the coach.
  private func coachReply(_ line: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Rectangle().fill(Theme.accent).frame(width: 2)
      VStack(alignment: .leading, spacing: 2) {
        Text(coach.name).forge(13, .semibold).foregroundStyle(Theme.textSecondary)
        Text(line).forgeBody()
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .transition(.opacity)
    .accessibilityIdentifier("onboarding-answer-feedback")
  }

  // MARK: Welcome

  private var welcomePage: some View {
    VStack(spacing: -24) {
      Color.clear
        .overlay(alignment: .top) {
          Image("onb-welcome").resizable().scaledToFill()
            .scaleEffect(reduceMotion ? 1 : (welcomePhotoShown ? 1 : 1.06))
            .opacity(welcomePhotoShown ? 1 : 0)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      welcomeSheet
        .frame(height: 308)
        .offset(y: reduceMotion ? 0 : (welcomeSheetShown ? 0 : 40))
    }
    .ignoresSafeArea()
    .task {
      guard !welcomePhotoShown else { return }
      if reduceMotion {
        withAnimation(.easeOut(duration: 0.3)) {
          welcomePhotoShown = true
          welcomeSheetShown = true
          welcomeTextShown = true
        }
        return
      }
      withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.7)) { welcomePhotoShown = true }
      withAnimation(.easeOut(duration: 0.5)) { welcomeSheetShown = true }
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.35)) { welcomeTextShown = true }
    }
  }

  /// A page-colored sheet overlapping the photo's lower edge; the wordmark sits centered above the CTA bar.
  private var welcomeSheet: some View {
    UnevenRoundedRectangle(topLeadingRadius: Theme.radiusCard, topTrailingRadius: Theme.radiusCard, style: .continuous)
      .fill(Theme.page)
      .overlay {
        VStack(spacing: 8) {
          Text("Regulift")
            .forge(44, .bold, tracking: -1.5)
            .foregroundStyle(Theme.text)
          Text(String(localized: "Your plan adapts to every set you log.", bundle: L10n.bundle))
            .forge(17, .medium)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
        }
        .opacity(welcomeTextShown ? 1 : 0)
        .offset(y: welcomeTextShown || reduceMotion ? 0 : 12)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 160)
        .fixedSize(horizontal: false, vertical: true)
      }
  }

  // MARK: Coach

  private var coachPage: some View {
    page(
      title: String(localized: "Who should coach you?", bundle: L10n.bundle),
      subtitle: String(localized: "Nova and Kai plan the same way. Pick the voice you like.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 16) {
        HStack(spacing: 12) {
          ForEach(Coach.allCases) { c in
            CoachPickCard(coach: c, selected: coach == c) {
              withAnimation(.snappy) { coachID = c.rawValue }
            }
          }
        }
        coachReply(String(localized: "Hi, I'm \(coach.name). I plan every session and tell you why each load changes.", bundle: L10n.bundle))
          .id(coach)
        Text("AI coaches for training programming, not medical advice. You can change your coach later in Settings.")
          .forgeCaption()
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
      }
    }
  }

  // MARK: Name

  private var namePage: some View {
    page(
      title: String(localized: "What should \(coach.name) call you?", bundle: L10n.bundle),
      subtitle: String(localized: "\(coach.name) uses it when talking to you.", bundle: L10n.bundle)
    ) {
      HStack(spacing: 0) {
        TextField(String(localized: "Your name", bundle: L10n.bundle), text: $displayName)
          .textContentType(.givenName)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .submitLabel(.continue)
          .onSubmit(advance)
          .focused($focusedField, equals: .name)
          .forge(20, .semibold)
          .padding(.leading, 16)
          .accessibilityIdentifier("onboarding-name-field")
        if !displayName.isEmpty {
          Button {
            displayName = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(Theme.textTertiary)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
          .padding(.trailing, 6)
        }
      }
      .frame(height: 56)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
      .onChange(of: displayName) { _, value in
        let capped = String(value.prefix(40))
        if capped != value { displayName = capped }
      }
      Button {
        advance()
      } label: {
        Text(String(localized: "Continue", bundle: L10n.bundle))
      }
      .buttonStyle(PillButtonStyle())
      .padding(.top, 14)
    }
    .task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      focusedField = .name
    }
  }

  // MARK: Science

  private var sciencePage: some View {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return statementPage(
      photo: coach.onboardingHello,
      title: trimmed.isEmpty
        ? String(localized: "Nice to meet you.", bundle: L10n.bundle)
        : String(localized: "Nice to meet you, \(trimmed).", bundle: L10n.bundle),
      subtitle: String(localized: "Here is how I plan: sets grow week by week, then week \(Mesocycle.deloadWeek) is an easy week so you recover.", bundle: L10n.bundle)
    ) {}
  }

  // MARK: Goal

  private var goalFeedback: String {
    switch goal {
    case .hypertrophy: return String(localized: "Compound lifts run 8–12 reps, isolation work 12–15.", bundle: L10n.bundle)
    case .strength: return String(localized: "Compound lifts run 4–6 reps, isolation work 8–12.", bundle: L10n.bundle)
    case .both: return String(localized: "Compound lifts run 6–10 reps, isolation work 10–15.", bundle: L10n.bundle)
    }
  }

  private var goalPage: some View {
    page(
      title: String(localized: "What are you training for?", bundle: L10n.bundle),
      subtitle: String(localized: "This sets your rep ranges. You can change it later in Settings.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 6) {
        SelectCard(title: String(localized: "Hypertrophy", bundle: L10n.bundle), subtitle: String(localized: "Build muscle", bundle: L10n.bundle), symbol: "", selected: answered.contains(.goal) && goal == .hypertrophy, art: ["onb-goal-hypertrophy-\(coach.rawValue)"], artFill: true) {
          withAnimation(.snappy) { goal = .hypertrophy; answered.insert(.goal) }
        }
        SelectCard(title: String(localized: "Strength", bundle: L10n.bundle), subtitle: String(localized: "Move more weight", bundle: L10n.bundle), symbol: "", selected: answered.contains(.goal) && goal == .strength, art: ["onb-goal-strength-\(coach.rawValue)"], artFill: true) {
          withAnimation(.snappy) { goal = .strength; answered.insert(.goal) }
        }
        SelectCard(title: String(localized: "Both", bundle: L10n.bundle), subtitle: String(localized: "Size and strength", bundle: L10n.bundle), symbol: "", selected: answered.contains(.goal) && goal == .both, art: ["onb-goal-both-\(coach.rawValue)"], artFill: true) {
          withAnimation(.snappy) { goal = .both; answered.insert(.goal) }
        }
        if answered.contains(.goal) {
          coachReply(goalFeedback)
        }
      }
    }
  }

  // MARK: Experience

  private var experienceFeedback: String {
    switch experience {
    case .advanced: return String(localized: "Advanced variations join your exercise pool.", bundle: L10n.bundle)
    default: return String(localized: "Standard variations lead. Advanced ones stay out for now.", bundle: L10n.bundle)
    }
  }

  /// Three bars rising with the level, sitting in the SelectCard's tint circle.
  private func levelBars(_ level: Int) -> some View {
    HStack(alignment: .bottom, spacing: 3) {
      Capsule().fill(Theme.accent).frame(width: 4, height: 8)
      Capsule().fill(level >= 2 ? Theme.accent : Theme.accent.opacity(0.28)).frame(width: 4, height: 12)
      Capsule().fill(level >= 3 ? Theme.accent : Theme.accent.opacity(0.28)).frame(width: 4, height: 16)
    }
  }

  private var experiencePage: some View {
    page(
      title: String(localized: "How long have you been lifting?", bundle: L10n.bundle),
      subtitle: String(localized: "Picks exercises that match your experience.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 10) {
        SelectCard(title: String(localized: "Post-beginner", bundle: L10n.bundle), subtitle: String(localized: "1–2 years", bundle: L10n.bundle), symbol: "", selected: answered.contains(.experience) && experience == .postBeginner, glyph: AnyView(levelBars(1))) {
          withAnimation(.snappy) { experience = .postBeginner; answered.insert(.experience) }
        }
        SelectCard(title: String(localized: "Intermediate", bundle: L10n.bundle), subtitle: String(localized: "2–4 years", bundle: L10n.bundle), symbol: "", selected: answered.contains(.experience) && experience == .intermediate, glyph: AnyView(levelBars(2))) {
          withAnimation(.snappy) { experience = .intermediate; answered.insert(.experience) }
        }
        SelectCard(title: String(localized: "Advanced", bundle: L10n.bundle), subtitle: String(localized: "4+ years", bundle: L10n.bundle), symbol: "", selected: answered.contains(.experience) && experience == .advanced, glyph: AnyView(levelBars(3))) {
          withAnimation(.snappy) { experience = .advanced; answered.insert(.experience) }
        }
        if answered.contains(.experience) {
          coachReply(experienceFeedback)
        }
      }
    }
  }

  // MARK: Loop

  private var loopPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        PhotoCard(name: "onb-loop")
          .opacity(loopCardShown ? 1 : 0)
          .offset(y: loopCardShown || reduceMotion ? 0 : 16)
        VStack(alignment: .leading, spacing: 8) {
          titleText(String(localized: "You log. \(coach.name) programs.", bundle: L10n.bundle), accent: nil)
            .forgeGreeting()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          Text(String(localized: "Log reps and how hard the set felt.", bundle: L10n.bundle))
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.margin)
        VStack(spacing: 12) {
          proofCard
          rpeTipRow
        }
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.top, 60)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .task {
      guard !loopCardShown else { return }
      withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.4)) { loopCardShown = true }
    }
    .task {
      guard rpeBarsFilled == 0 else { return }
      if reduceMotion {
        rpeBarsFilled = 8
        return
      }
      for _ in 0..<8 {
        withAnimation(.easeOut(duration: 0.25)) { rpeBarsFilled += 1 }
        try? await Task.sleep(for: .milliseconds(35))
      }
    }
  }

  private var squatName: String {
    ExerciseDB.find("back_squat")?.localizedName ?? "Back Squat"
  }

  /// The demo's arithmetic through the real engine: 64 kg at RPE 7 against a target of 8.
  private var loopNextLoad: (kg: Double, gain: Double) {
    if case .increase(let k) = Progression.nextLoad(currentKg: 64, targetRPE: 8, actualRPE: 7) {
      let next = Progression.round(k, toIncrement: 2.5)
      return (next, next - 64)
    }
    return (64, 0)
  }

  private var proofCard: some View {
    let next = loopNextLoad
    return HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "\(squatName) today", bundle: L10n.bundle))
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(verbatim: Fmt.num(64)).forge(24, .bold).monospacedDigit()
          Text(verbatim: "kg").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
          Text(verbatim: "×").forge(18, .medium).foregroundStyle(Theme.textSecondary)
          Text(verbatim: "8").forge(24, .bold).monospacedDigit()
        }
        Text(String(localized: "Felt RPE \(7), target \(8)", bundle: L10n.bundle))
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
      }
      Spacer(minLength: 12)
      Image(systemName: "arrow.right")
        .foregroundStyle(Theme.textTertiary)
      Spacer(minLength: 12)
      VStack(alignment: .trailing, spacing: 2) {
        Text(String(localized: "Next session", bundle: L10n.bundle))
          .forge(13, .medium)
          .foregroundStyle(Theme.textSecondary)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(verbatim: Fmt.num(next.kg)).forge(24, .bold).monospacedDigit()
          Text(verbatim: "kg").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
        }
        Text(verbatim: "+\(Fmt.num(next.gain)) kg")
          .forge(13, .semibold)
          .foregroundStyle(Theme.positiveText)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.innerSurface))
  }

  /// Ten effort bars, eight filled: RPE 8 leaves about two reps in the tank.
  private var rpeTipRow: some View {
    HStack(spacing: 14) {
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(0..<10, id: \.self) { bar in
          Capsule()
            .fill(bar < 8 ? Theme.accent : Theme.track)
            .frame(width: 6, height: 10 + 2 * CGFloat(bar))
            .scaleEffect(y: bar < rpeBarsFilled || reduceMotion ? 1 : 0.15, anchor: .bottom)
        }
      }
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(String(localized: "RPE \(8): about \(2) reps left", bundle: L10n.bundle))
          .forge(15, .semibold)
        Text(String(localized: "Stop when you could do \(2) more.", bundle: L10n.bundle))
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.innerSurface))
    .accessibilityElement(children: .combine)
  }

  // MARK: Days

  private var daysFeedback: String {
    switch daysPerWeek {
    case 3: return String(localized: "Three full-body sessions. Each one trains legs, push and pull.", bundle: L10n.bundle)
    case 4: return String(localized: "Two upper and two lower sessions. Each muscle trains twice a week.", bundle: L10n.bundle)
    case 5: return String(localized: "Upper, lower, push, pull and legs: five focused sessions.", bundle: L10n.bundle)
    default: return String(localized: "Push, pull and legs, twice through. Each muscle trains twice a week.", bundle: L10n.bundle)
    }
  }

  private var daysPage: some View {
    page(
      title: String(localized: "How many days a week can you train?", bundle: L10n.bundle),
      subtitle: String(localized: "Your weekly split follows from this.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 16) {
        HStack(spacing: 8) {
          ForEach(3...6, id: \.self) { days in
            Button {
              withAnimation(.snappy) { daysPerWeek = days; answered.insert(.days) }
            } label: {
              Text(verbatim: "\(days)")
                .forge(26, .bold)
                .monospacedDigit()
                .foregroundStyle(answered.contains(.days) && daysPerWeek == days ? Theme.onAccent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                  RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                    .fill(answered.contains(.days) && daysPerWeek == days ? Theme.accentStrong : Theme.innerSurface))
                .contentShape(Rectangle())
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(String(localized: "\(days) days", bundle: L10n.bundle))
            .accessibilityAddTraits(answered.contains(.days) && daysPerWeek == days ? .isSelected : [])
          }
        }
        if answered.contains(.days) {
          Text(String(localized: "Your week", bundle: L10n.bundle))
            .forge(15, .semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(Program.week(1, profile: input).enumerated()), id: \.offset) { index, day in
              let sets = day.exercises.reduce(0) { $0 + $1.sets }
              VStack(alignment: .leading, spacing: 8) {
                dayBadge(index + 1)
                Text(localizedDayName(day.name))
                  .forge(15, .semibold)
                  .foregroundStyle(Theme.text)
                Text(String(localized: "\(sets) sets", bundle: L10n.bundle))
                  .forgeLabel()
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
            }
          }
          coachReply(daysFeedback)
        }
      }
    }
  }

  // MARK: Length

  /// A 22 pt ring filling with the session length, up to the 90 min option.
  private func lengthRing(minutes: Int) -> some View {
    Circle()
      .stroke(Theme.accent.opacity(0.25), lineWidth: 4)
      .overlay {
        Circle()
          .trim(from: 0, to: Double(minutes) / 90)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 22, height: 22)
  }

  private var lengthPage: some View {
    page(
      title: String(localized: "How long is each session?", bundle: L10n.bundle),
      subtitle: String(localized: "Sets how many exercises and working sets fit in a day.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 10) {
        ForEach(SessionLength.allCases, id: \.self) { length in
          SelectCard(
            title: String(localized: "\(length.rawValue) min", bundle: L10n.bundle),
            subtitle: String(localized: "Up to \(length.maxExercises) exercises · \(Program.setBudget(for: length)) working sets", bundle: L10n.bundle),
            symbol: "",
            selected: answered.contains(.length) && sessionLength == length,
            glyph: AnyView(lengthRing(minutes: length.rawValue))) {
            withAnimation(.snappy) { sessionLength = length; answered.insert(.length) }
          }
        }
      }
    }
  }

  // MARK: Equipment

  private var equipmentPage: some View {
    page(
      title: String(localized: "Where do you train?", bundle: L10n.bundle),
      subtitle: String(localized: "Exercises are picked from this equipment.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 6) {
        ForEach(GymPreset.allCases, id: \.self) { preset in
          SelectCard(
            title: preset.name,
            subtitle: preset.detail,
            symbol: "",
            selected: gymPreset == preset,
            art: ["onb-place-\(preset.rawValue)"],
            artFill: true) {
            withAnimation(.snappy) {
              gymPreset = preset
              equipment = preset.equipment
            }
          }
          .accessibilityIdentifier("gym-preset-\(preset.rawValue)")
        }
        Button {
          withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { customiseOpen.toggle() }
        } label: {
          HStack(spacing: 2) {
            Text(String(localized: "Pick single items instead", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.accentText)
            Image(systemName: "chevron.right")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(Theme.accentText)
              .rotationEffect(.degrees(customiseOpen ? 90 : 0))
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .sensoryFeedback(.selection, trigger: customiseOpen)
        if customiseOpen {
          VStack(spacing: 8) {
            ForEach(Equipment.allCases, id: \.self) { item in
              SelectCard(
                title: item.name,
                symbol: equipmentSymbols[item] ?? "circle",
                selected: equipment.contains(item)) {
                withAnimation(.snappy) {
                  if equipment.contains(item) { equipment.remove(item) } else { equipment.insert(item) }
                  gymPreset = nil
                }
              }
            }
          }
        }
      }
    }
  }

  // MARK: Numbers

  /// Week 1's first lift with a real load; the coach's "starts at" line quotes it.
  private var firstLoadedLift: (name: String, load: String)? {
    guard bodyweightValid,
          let planned = Program.week(1, profile: input).first?.exercises.first(where: { startingKg($0) > 0 })
    else { return nil }
    return (planned.exercise.localizedName, loadText(startingKg(planned)))
  }

  private var numbersPage: some View {
    page(
      title: String(localized: "Your numbers", bundle: L10n.bundle),
      subtitle: String(localized: "Bodyweight sizes your starting loads. Current lifts are optional.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 14) {
        HStack {
          Text(String(localized: "Bodyweight", bundle: L10n.bundle))
            .forge(15, .semibold)
          Spacer()
          Picker("Units", selection: $usesLb) {
            Text("kg").forge(13, .medium).tag(false)
            Text("lb").forge(13, .medium).tag(true)
          }
          .pickerStyle(.segmented)
          .frame(width: 116)
          .accessibilityLabel("Weights in kilograms or pounds")
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          TextField("", text: $bodyweightText, prompt: Text(verbatim: Fmt.num(rulerStart)).foregroundStyle(Theme.textTertiary))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .bodyweight)
            .forge(56, .bold)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .fixedSize()
            .accessibilityLabel(usesLb ? String(localized: "Bodyweight in pounds", bundle: L10n.bundle) : String(localized: "Bodyweight in kilograms", bundle: L10n.bundle))
          Text(usesLb ? "lb" : "kg")
            .forge(22, .semibold)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        WeightRuler(value: bodyweightRulerBinding, step: usesLb ? 1 : 0.5, unit: usesLb ? "lb" : "kg") {
          rulerTick &+= 1
        }
        .sensoryFeedback(.selection, trigger: rulerTick)
        .accessibilityLabel(String(localized: "Bodyweight", bundle: L10n.bundle))
        Text(bodyweightRangeText)
          .forgeCaption()
          .foregroundStyle(bodyweightInvalid ? Theme.negative : Theme.textTertiary)
          .frame(maxWidth: .infinity)
          .opacity(bodyweightInvalid ? 1 : 0)
          .accessibilityHidden(!bodyweightInvalid)
        if liftIDs.isEmpty {
          Text(String(localized: "No starting loads needed for bodyweight training.", bundle: L10n.bundle))
            .forgeBody()
        } else {
          Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { liftsOpen.toggle() }
          } label: {
            HStack(spacing: 8) {
              VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Current lifts", bundle: L10n.bundle))
                  .forge(16, .semibold)
                  .foregroundStyle(Theme.text)
                Text(String(localized: "Optional. Leave blank and we estimate.", bundle: L10n.bundle))
                  .forgeLabel()
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(liftsOpen ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
          .sensoryFeedback(.selection, trigger: liftsOpen)
          .accessibilityIdentifier("onboarding-current-lifts")
          if liftsOpen {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(liftIDs, id: \.self) { id in
                HStack {
                  Text(liftName(id))
                    .accessibilityHidden(true)
                  Spacer()
                  TextField("—", text: liftBinding(id))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .lift(id))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 96)
                    .accessibilityLabel(liftName(id))
                }
              }
              Text("Leave blank and we estimate from bodyweight.")
                .forgeCaption()
            }
            .card()
          }
        }
        if let first = firstLoadedLift {
          coachReply(String(localized: "I size your first loads from this. \(first.name) starts at \(first.load).", bundle: L10n.bundle))
        }
      }
    }
  }

  // MARK: Workarounds

  private var workaroundsPage: some View {
    page(
      title: String(localized: "Anything to work around?", bundle: L10n.bundle),
      subtitle: String(localized: "Flag an area and the plan swaps exercises that load it.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 8) {
        ForEach(InjuryFlag.allCases, id: \.self) { flag in
          SelectCard(
            title: flag.name,
            symbol: "",
            selected: injuries.contains(flag),
            multiSelect: true) {
            withAnimation(.snappy) {
              if injuries.contains(flag) { injuries.remove(flag) } else { injuries.insert(flag) }
            }
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Toggle("I sleep under 6 h or life stress is high", isOn: $recoveryReduced)
            .accessibilityIdentifier("recovery-reduced-toggle")
          Text(String(localized: "Lowers weekly max sets by 15 %.", bundle: L10n.bundle))
            .forgeCaption()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
        coachReply(
          injuries.isEmpty
            ? String(localized: "Nothing flagged. You can flag an area later in Settings.", bundle: L10n.bundle)
            : String(localized: "I'll swap out exercises that load the areas you flagged.", bundle: L10n.bundle))
      }
    }
  }

  // MARK: Photo

  private var photoPage: some View {
    page(
      title: String(localized: "A starting photo", bundle: L10n.bundle),
      subtitle: String(localized: "Optional front pose. You can add more poses later in Progress.", bundle: L10n.bundle)
    ) {
      if let photoData, let image = UIImage(data: photoData) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
              .strokeBorder(Theme.imageOutline, lineWidth: 1))
          .frame(height: 220)
          .accessibilityLabel("Your starting photo")
          .transition(.opacity)
      } else {
        poseGuide
      }
    }
  }

  /// A framing guide: four brackets around where a front pose should stand.
  private var poseGuide: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .fill(Theme.innerSurface)
      VStack(spacing: 6) {
        Circle()
          .fill(Theme.track)
          .frame(width: 30, height: 30)
        RoundedRectangle(cornerRadius: 16)
          .fill(Theme.track)
          .frame(width: 46, height: 70)
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 7)
            .fill(Theme.track)
            .frame(width: 14, height: 54)
          RoundedRectangle(cornerRadius: 7)
            .fill(Theme.track)
            .frame(width: 14, height: 54)
        }
      }
      .frame(width: 150, height: 160)
      .overlay(alignment: .topLeading) { bracket(.topLeading) }
      .overlay(alignment: .topTrailing) { bracket(.topTrailing) }
      .overlay(alignment: .bottomLeading) { bracket(.bottomLeading) }
      .overlay(alignment: .bottomTrailing) { bracket(.bottomTrailing) }
    }
    .frame(height: 233)
    .accessibilityHidden(true)
  }

  private func bracket(_ corner: BracketCorner) -> some View {
    BracketShape(corner: corner)
      .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      .frame(width: 20, height: 20)
  }

  // MARK: Building

  private var buildLines: [String] {
    [
      String(localized: "Sizing your starting loads", bundle: L10n.bundle),
      String(localized: "Fitting \(Program.setBudget(for: sessionLength)) working sets into \(sessionLength.rawValue) min", bundle: L10n.bundle),
      String(localized: "Planning week 1 of \(Mesocycle.weeks)", bundle: L10n.bundle),
    ]
  }

  private var buildingPage: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 0)
      ZStack {
        Circle().stroke(Theme.track, lineWidth: 6)
        Circle()
          .trim(from: 0, to: buildProgress)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Image(coach.onboardingBuild)
          .resizable()
          .scaledToFill()
          .frame(width: 184, height: 184)
          .clipShape(Circle())
          .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
          .scaleEffect(buildShown || reduceMotion ? 1 : 0.94)
          .opacity(buildShown ? 1 : 0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .frame(width: 212, height: 212)
      Text(String(localized: "\(coach.name) is building your plan", bundle: L10n.bundle))
        .forgeTitle()
        .multilineTextAlignment(.center)
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(buildLines.enumerated()), id: \.offset) { index, line in
          HStack(spacing: 10) {
            Image(systemName: index < buildTicks ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(index < buildTicks ? Theme.positive : Theme.textTertiary)
            Text(line).forgeBody()
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.margin)
    .task(id: step) {
      guard step == .building else { return }
      buildProgress = 0
      buildTicks = 0
      for tick in 1...3 {
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
          buildTicks = tick
          buildProgress = Double(tick) / 3
        }
      }
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      advance()
    }
    .task {
      guard !buildShown else { return }
      withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.5)) { buildShown = true }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "\(coach.name) is building your plan", bundle: L10n.bundle))
  }

  // MARK: Summary

  private var summaryPage: some View {
    let week = Program.week(1, profile: input)
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return page(
      title: trimmed.isEmpty
        ? String(localized: "Week 1 is ready", bundle: L10n.bundle)
        : String(localized: "Week 1 is ready, \(trimmed)", bundle: L10n.bundle),
      subtitle: planBasis
    ) {
      VStack(spacing: 8) {
        Text(String(localized: "\(week.count) sessions this week", bundle: L10n.bundle))
          .forgeSection()
        ForEach(Array(week.enumerated()), id: \.offset) { index, day in
          sessionRow(index + 1, day)
            .reveal(index, appeared: planShown, stagger: 0.1)
        }
      }
      if let day = week.first {
        firstSessionCard(day)
      }
      if !callouts.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Built for you").forgeSection()
          ForEach(callouts, id: \.self) { line in
            HStack(spacing: 10) {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
              Text(line).forgeBody()
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
      }
    }
    .onAppear { planShown = true }
  }

  /// Wraps only between items: no-break spaces inside items and before each dot.
  private func dotList(_ items: [String]) -> String {
    items.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: "\u{00A0}· ")
  }

  /// The answers this preview was built from.
  private var planBasis: String {
    dotList([goal.name,
             experience.name,
             String(localized: "\(daysPerWeek) days a week", bundle: L10n.bundle),
             String(localized: "\(sessionLength.rawValue) min", bundle: L10n.bundle)])
  }

  private func sessionRow(_ number: Int, _ day: PlannedDay) -> some View {
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    return HStack(alignment: .top, spacing: 12) {
      dayBadge(number)
      VStack(alignment: .leading, spacing: 2) {
        Text(localizedDayName(day.name))
          .forge(16, .semibold)
          .foregroundStyle(Theme.text)
        Text(dotList(topMuscles(day).map(\.a11yName)))
          .forgeLabel()
      }
      Spacer(minLength: 8)
      Text(String(localized: "\(sets) sets", bundle: L10n.bundle))
        .forge(14, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .fixedSize()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    .accessibilityElement(children: .combine)
  }

  private func dayBadge(_ number: Int) -> some View {
    Text(verbatim: "\(number)")
      .forge(15, .bold)
      .monospacedDigit()
      .foregroundStyle(Theme.accentText)
      .frame(width: 32, height: 32)
      .background(Circle().fill(Theme.accentTint))
      .accessibilityHidden(true)
  }

  /// First three muscles in plan order; the main lifts lead.
  private func topMuscles(_ day: PlannedDay) -> [Muscle] {
    var seen = Set<Muscle>()
    return Array(day.exercises.map(\.exercise.primary).filter { seen.insert($0).inserted }.prefix(3))
  }

  private func firstSessionCard(_ day: PlannedDay) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        dayBadge(1)
        Text(localizedDayName(day.name)).forgeSection()
      }
      Text(loadLine).forgeCaption()
      ForEach(day.exercises) { planned in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(planned.exercise.localizedName).forgeBodyStrong()
            Text(String(localized: "\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)", bundle: L10n.bundle))
              .forgeLabel()
              .monospacedDigit()
          }
          Spacer(minLength: 8)
          if let load = startingLoadText(planned) {
            Text(verbatim: load)
              .forge(15, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
    .card(padding: 16)
  }

  private func startingKg(_ planned: PlannedExercise) -> Double {
    if let entered = number(lifts[planned.exercise.id] ?? "") {
      return usesLb ? Plates.lbToKg(entered) : entered
    }
    return Strength.estimatedStartingLoad(exercise: planned.exercise, bodyweightKg: bodyweightKg)
  }

  private func startingLoadText(_ planned: PlannedExercise) -> String? {
    let kg = startingKg(planned)
    return kg > 0 ? loadText(kg) : nil
  }

  private func loadText(_ kg: Double) -> String {
    Fmt.kg(usesLb ? Plates.kgToLb(kg) : kg, lb: usesLb)
  }

  /// The one load fact that matters under the session title: what the estimates come from.
  private var loadLine: String {
    if liftIDs.isEmpty {
      return String(localized: "No starting loads needed for bodyweight training.", bundle: L10n.bundle)
    }
    let n = liftIDs.filter { number(lifts[$0] ?? "") != nil }.count
    if n > 0 {
      return String(localized: "Starting loads from your \(n) entered lifts", bundle: L10n.bundle)
    }
    let bw = number(bodyweightText) ?? 0
    let weight = "\(bw.formatted(.number.precision(.fractionLength(0...1))))\u{00A0}\(usesLb ? "lb" : "kg")"
    return String(localized: "Starting loads estimated from \(weight) bodyweight", bundle: L10n.bundle)
  }

  private var callouts: [String] {
    Array(Personalization.lines(for: input).prefix(4))
  }

  private func liftBinding(_ id: String) -> Binding<String> {
    Binding(
      get: { lifts[id] ?? "" },
      set: { lifts[id] = $0 })
  }

  private func liftName(_ id: String) -> String {
    let name = ExerciseDB.find(id)?.localizedName ?? id
    return String(localized: "\(name) (\(usesLb ? "lb" : "kg"))", bundle: L10n.bundle)
  }

  private func number(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
          value.isFinite, value > 0 else { return nil }
    return value
  }

  private func save() {
    Analytics.track("onboarding_done")
    if let photoData {
      ProgressPhoto.insert(photoData, date: .now, pose: "front", context: modelContext)
    }
    var starting: [String: Double] = [:]
    for id in liftIDs {
      if let entered = number(lifts[id] ?? "") {
        starting[id] = usesLb ? Plates.lbToKg(entered) : entered
      } else if let exercise = ExerciseDB.find(id) {
        let estimate = Strength.estimatedStartingLoad(exercise: exercise, bodyweightKg: bodyweightKg)
        if estimate > 0 { starting[id] = estimate }
      }
    }
    let profile = UserProfile(
      goal: goal,
      experience: experience,
      daysPerWeek: daysPerWeek,
      sessionMinutes: sessionLength.rawValue,
      equipment: equipment,
      injuryFlags: injuries,
      recoveryReduced: recoveryReduced,
      bodyweightKg: bodyweightKg,
      usesLb: usesLb,
      startingLoads: starting)
    profile.gymPreset = gymPreset?.rawValue ?? "custom"
    modelContext.insert(profile)
    try? modelContext.save()
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty {
      _ = try? JourneyRepository(context: modelContext, profile: profile, accountID: auth.user?.id)
        .savePrivateProfile(displayName: name, trainingStartDate: nil)
    }
    savedTick &+= 1
  }
}

/// A statement page's photo: full-width card with the 1 pt outline, inert to touches.
private struct PhotoCard: View {
  let name: String

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .containerRelativeFrame(.vertical) { length, _ in min(300, length * 0.44) }
      .overlay {
        Image(name).resizable().scaledToFill()
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .padding(.horizontal, Theme.margin)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private enum BracketCorner {
  case topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// One L-shaped corner bracket of the photo pose guide.
private struct BracketShape: Shape {
  let corner: BracketCorner
  var arm: CGFloat = 20

  func path(in rect: CGRect) -> Path {
    let arm = min(arm, min(rect.width, rect.height))
    var path = Path()
    switch corner {
    case .topLeading:
      path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
    case .topTrailing:
      path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
    case .bottomLeading:
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
    case .bottomTrailing:
      path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
    }
    return path
  }
}
