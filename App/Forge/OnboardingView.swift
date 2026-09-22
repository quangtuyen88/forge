import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import ForgeCore

struct OnboardingView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// One enum drives the indicator, the page switch and the CTA label, so adding a step can never leave them disagreeing.
  private enum Step: Int, CaseIterable {
    case welcome, science, coach, goal, experience, loop, days, length, equipment, numbers, workarounds, photo, firstSet, building, summary
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
  @State private var lifts: [String: String] = [:]
  @State private var injuries: Set<InjuryFlag> = []
  @State private var recoveryReduced = false
  @State private var showPromoField = false
  @State private var demoRPE: Int?
  @State private var demoLogged = false
  @State private var buildProgress: Double = 0
  @State private var buildTicks = 0
  @State private var planShown = false
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?
  @FocusState private var focusedField: Field?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("pendingCode") private var pendingCode = ""

  private var coach: Coach { Coach.from(coachID) }

  private enum Question: Hashable { case goal, experience, days, length }
  @State private var answered: Set<Question> = []

  private enum Field: Hashable {
    case bodyweight
    case lift(String)
    case promo
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

  private let presetSymbols: [GymPreset: String] = [
    .commercial: "building.2",
    .home: "house.fill",
    .dumbbellsOnly: "dumbbell.fill",
    .hotel: "bed.double.fill",
    .noMachines: "figure.strengthtraining.traditional",
    .bodyweight: "figure.core.training",
  ]

  private let injurySymbols: [InjuryFlag: String] = [
    .shoulder: "figure.arms.open",
    .knee: "figure.walk",
    .back: "figure.stand",
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

  private var firstSetExercise: PlannedExercise? {
    Program.week(1, profile: input).first?.exercises.first(where: { startingKg($0) > 0 })
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
    let next: Step
    if step == .photo && firstSetExercise == nil {
      next = .building
    } else {
      next = Step(rawValue: step.rawValue + 1) ?? .summary
    }
    withAnimation(.snappy) { step = next }
  }

  private func goBack() {
    goingForward = false
    guard let prev = Step(rawValue: step.rawValue - 1) else { return }
    let target: Step
    switch prev {
    case .building: target = firstSetExercise == nil ? .photo : .firstSet
    default: target = prev
    }
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
      VStack(spacing: 0) {
        topBar
        ZStack {
          switch step {
          case .welcome: welcomePage.transition(pageTransition)
          case .science: sciencePage.transition(pageTransition)
          case .coach: coachPage.transition(pageTransition)
          case .goal: goalPage.transition(pageTransition)
          case .experience: experiencePage.transition(pageTransition)
          case .loop: loopPage.transition(pageTransition)
          case .days: daysPage.transition(pageTransition)
          case .length: lengthPage.transition(pageTransition)
          case .equipment: equipmentPage.transition(pageTransition)
          case .numbers: numbersPage.transition(pageTransition)
          case .workarounds: workaroundsPage.transition(pageTransition)
          case .photo: photoPage.transition(pageTransition)
          case .firstSet: firstSetPage.transition(pageTransition)
          case .building: buildingPage.transition(pageTransition)
          case .summary: summaryPage.transition(pageTransition)
          }
        }
      }
      .background(Theme.page.ignoresSafeArea())
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
      .safeAreaInset(edge: .bottom) {
        if step != .building {
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
            Button {
              advance()
            } label: {
              Text(ctaTitle)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.4)
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
    }
  }

  private var ctaTitle: String {
    switch step {
    case .welcome: return String(localized: "Get started", bundle: L10n.bundle)
    case .summary: return String(localized: "Save this plan", bundle: L10n.bundle)
    default: return String(localized: "Continue", bundle: L10n.bundle)
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
      progressBar
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 4)
    .opacity(topBarHidden ? 0 : 1)
    .disabled(topBarHidden)
    .accessibilityHidden(topBarHidden)
  }

  private var topBarHidden: Bool { step == .welcome || step == .building }

  private var progressBar: some View {
    ProgressView(value: Double(step.rawValue), total: Double(Step.summary.rawValue))
      .progressViewStyle(.linear)
      .tint(Theme.accent)
      .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: step)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
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
        : String(localized: "Enter your bodyweight — it sizes your starting loads.", bundle: L10n.bundle)
    default: return nil
    }
  }

  private func page(
    art: String? = nil,
    artHeight: CGFloat = 150,
    title: String,
    accent: String? = nil,
    subtitle: String? = nil,
    @ViewBuilder content: () -> some View
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          if let art, art.hasPrefix("coach-") || art.hasPrefix("kai-") {
            CoachPhoto(name: art, height: artHeight)
          } else if let art {
            Illustration(name: art, height: artHeight)
          }
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
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private func titleText(_ title: String, accent: String?) -> Text {
    guard let accent else { return Text(title) }
    return Text(title) + Text(" ") + Text(accent).foregroundStyle(Theme.accent)
  }

  /// Lungy pattern: the answer to a question is explained inline by the coach right under the list.
  private func answerBubble(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      CoachAvatar(size: 32)
      SpeechBubble(tint: Theme.innerSurface) {
        Text(text).forgeBody()
      }
    }
    .transition(.opacity)
    .accessibilityIdentifier("onboarding-answer-feedback")
  }

  private var welcomePage: some View {
    VStack(spacing: 16) {
      Spacer(minLength: 0)
      Illustration(name: "art-plan", height: 200)
      Text("Regulift")
        .forge(44, .bold, tracking: -1.5)
        .foregroundStyle(Theme.text)
      Text(String(localized: "They log. We program.", bundle: L10n.bundle))
        .forge(17, .medium)
        .foregroundStyle(Theme.textSecondary)
      Text(String(localized: "Import or start fresh. Your plan adapts to every set you log.", bundle: L10n.bundle))
        .forgeLabel()
        .multilineTextAlignment(.center)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.margin)
  }

  private var sciencePage: some View {
    page(
      art: "art-schedule",
      artHeight: 180,
      title: String(localized: "Built on", bundle: L10n.bundle),
      accent: String(localized: "training science.", bundle: L10n.bundle),
      subtitle: String(localized: "Volume landmarks, effort-based load changes and planned deloads decide every session. Each change comes with its reason.", bundle: L10n.bundle)
    ) {}
  }

  private var coachPage: some View {
    page(art: nil, title: String(localized: "Your coach", bundle: L10n.bundle)) {
      HStack(spacing: 12) {
        ForEach(Coach.allCases) { c in
          CoachPickCard(coach: c, selected: coach == c) {
            withAnimation(.snappy) { coachID = c.rawValue }
          }
        }
      }
      Text("AI coaches for training programming, not medical advice. You can change your coach later in Settings.").forgeCaption()
    }
  }

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
      VStack(spacing: 12) {
        SelectCard(title: String(localized: "Hypertrophy", bundle: L10n.bundle), subtitle: String(localized: "Build muscle", bundle: L10n.bundle), symbol: "figure.strengthtraining.traditional", selected: answered.contains(.goal) && goal == .hypertrophy) {
          withAnimation(.snappy) { goal = .hypertrophy; answered.insert(.goal) }
        }
        SelectCard(title: String(localized: "Strength", bundle: L10n.bundle), subtitle: String(localized: "Move more weight", bundle: L10n.bundle), symbol: "scalemass", selected: answered.contains(.goal) && goal == .strength) {
          withAnimation(.snappy) { goal = .strength; answered.insert(.goal) }
        }
        SelectCard(title: String(localized: "Both", bundle: L10n.bundle), subtitle: String(localized: "Size and strength", bundle: L10n.bundle), symbol: "arrow.triangle.merge", selected: answered.contains(.goal) && goal == .both) {
          withAnimation(.snappy) { goal = .both; answered.insert(.goal) }
        }
        if answered.contains(.goal) {
          answerBubble(goalFeedback)
        }
      }
    }
  }

  private var experienceFeedback: String {
    switch experience {
    case .advanced: return String(localized: "Advanced variations join your exercise pool.", bundle: L10n.bundle)
    default: return String(localized: "Standard variations lead. Advanced ones stay out for now.", bundle: L10n.bundle)
    }
  }

  private var experiencePage: some View {
    page(
      title: String(localized: "How long have you been lifting?", bundle: L10n.bundle),
      subtitle: String(localized: "Picks exercises that match your experience.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 12) {
        SelectCard(title: String(localized: "Post-beginner", bundle: L10n.bundle), subtitle: String(localized: "1–2 years", bundle: L10n.bundle), symbol: "1.circle", selected: answered.contains(.experience) && experience == .postBeginner) {
          withAnimation(.snappy) { experience = .postBeginner; answered.insert(.experience) }
        }
        SelectCard(title: String(localized: "Intermediate", bundle: L10n.bundle), subtitle: String(localized: "2–4 years", bundle: L10n.bundle), symbol: "2.circle", selected: answered.contains(.experience) && experience == .intermediate) {
          withAnimation(.snappy) { experience = .intermediate; answered.insert(.experience) }
        }
        SelectCard(title: String(localized: "Advanced", bundle: L10n.bundle), subtitle: String(localized: "4+ years", bundle: L10n.bundle), symbol: "3.circle", selected: answered.contains(.experience) && experience == .advanced) {
          withAnimation(.snappy) { experience = .advanced; answered.insert(.experience) }
        }
        if answered.contains(.experience) {
          answerBubble(experienceFeedback)
        }
      }
    }
  }

  private var loopPage: some View {
    page(
      art: "art-goal",
      artHeight: 180,
      title: String(localized: "They log.", bundle: L10n.bundle),
      accent: String(localized: "We program.", bundle: L10n.bundle),
      subtitle: String(localized: "You log reps and how hard the set felt. Regulift sets the next load and tells you why.", bundle: L10n.bundle)
    ) {}
  }

  private var daysPage: some View {
    page(
      title: String(localized: "How many days a week can you train?", bundle: L10n.bundle),
      subtitle: String(localized: "Your weekly split follows from this.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 12) {
        ForEach(3...6, id: \.self) { days in
          SelectCard(
            title: String(localized: "\(days) days", bundle: L10n.bundle),
            subtitle: dotList(Program.split(daysPerWeek: days).map(localizedDayName)),
            symbol: "\(days).circle",
            selected: answered.contains(.days) && daysPerWeek == days) {
            withAnimation(.snappy) { daysPerWeek = days; answered.insert(.days) }
          }
        }
      }
    }
  }

  private var lengthPage: some View {
    page(
      title: String(localized: "How long is each session?", bundle: L10n.bundle),
      subtitle: String(localized: "Sets how many exercises and working sets fit in a day.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 12) {
        ForEach(SessionLength.allCases, id: \.self) { length in
          SelectCard(
            title: String(localized: "\(length.rawValue) min", bundle: L10n.bundle),
            subtitle: String(localized: "Up to \(length.maxExercises) exercises · \(Program.setBudget(for: length)) working sets", bundle: L10n.bundle),
            symbol: "clock",
            selected: answered.contains(.length) && sessionLength == length) {
            withAnimation(.snappy) { sessionLength = length; answered.insert(.length) }
          }
        }
      }
    }
  }

  private var equipmentPage: some View {
    page(
      art: "art-equipment",
      artHeight: 120,
      title: String(localized: "Where do you train?", bundle: L10n.bundle),
      subtitle: String(localized: "Exercises are picked from this equipment.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 12) {
        ForEach(GymPreset.allCases, id: \.self) { preset in
          SelectCard(
            title: preset.name,
            subtitle: preset.detail,
            symbol: presetSymbols[preset] ?? "dumbbell",
            selected: gymPreset == preset) {
            withAnimation(.snappy) {
              gymPreset = preset
              equipment = preset.equipment
            }
          }
          .accessibilityIdentifier("gym-preset-\(preset.rawValue)")
        }
        DisclosureGroup(String(localized: "Customise", bundle: L10n.bundle)) {
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
          .padding(.top, 8)
        }
      }
    }
  }

  private var numbersPage: some View {
    page(
      art: "art-numbers",
      artHeight: 120,
      title: String(localized: "Your numbers", bundle: L10n.bundle),
      subtitle: String(localized: "Bodyweight sizes your starting loads. Current lifts are optional.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 8) {
        VStack(spacing: 12) {
          Picker("Units", selection: $usesLb) {
            Text("kg").forge(13, .medium).tag(false)
            Text("lb").forge(13, .medium).tag(true)
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Weights in kilograms or pounds")
          HStack {
            TextField(usesLb ? String(localized: "Bodyweight (lb)", bundle: L10n.bundle) : String(localized: "Bodyweight (kg)", bundle: L10n.bundle), text: $bodyweightText)
              .keyboardType(.decimalPad)
              .focused($focusedField, equals: .bodyweight)
              .accessibilityLabel(usesLb ? String(localized: "Bodyweight in pounds", bundle: L10n.bundle) : String(localized: "Bodyweight in kilograms", bundle: L10n.bundle))
            Text(usesLb ? "lb" : "kg")
              .forgeLabel()
          }
          Text(bodyweightRangeText)
            .forgeCaption()
            .foregroundStyle(bodyweightInvalid ? Theme.negative : Theme.textTertiary)
        }
        .card()
        if liftIDs.isEmpty {
          Text(String(localized: "No starting loads needed for bodyweight training.", bundle: L10n.bundle))
            .forgeBody()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
          VStack(alignment: .leading, spacing: 12) {
            Text("Current lifts (optional)").forgeSection()
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
    }
  }

  /// Referral / promo entry, moved off "Your numbers". A code field is not what a first-run
  /// lifter came here to fill in, and on that step it sat under five optional lift fields where
  /// nobody scrolled to it. Here it is the first row of the last screen — one tap from the
  /// commit, still optional, and attribution is unchanged.
  private var promoCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
          showPromoField.toggle()
        }
        if showPromoField { focusedField = .promo }
      } label: {
        HStack(spacing: 8) {
          Text("Referral or promo code").forgeSection()
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .rotationEffect(.degrees(showPromoField ? 90 : 0))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Referral or promo code")
      .accessibilityHint(showPromoField ? "Hides the code field" : "Opens the code field")
      .accessibilityIdentifier("promo-code-toggle")
      .sensoryFeedback(.selection, trigger: showPromoField)
      if showPromoField {
        TextField("CODE", text: $pendingCode)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .focused($focusedField, equals: .promo)
          .onChange(of: pendingCode) { _, value in
            let capped = String(value.uppercased().prefix(12))
            if capped != value { pendingCode = capped }
          }
          .forgeBody()
          .padding(10)
          .background(
            RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
              .fill(Theme.innerSurface)
          )
          .accessibilityLabel("Referral or promo code")
          .accessibilityIdentifier("promo-code-field")
        Text("Invited by a friend or have a promo? Optional.")
          .forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var workaroundsPage: some View {
    page(
      title: String(localized: "Anything to work around?", bundle: L10n.bundle),
      subtitle: String(localized: "Flag an area and the plan swaps exercises that load it.", bundle: L10n.bundle)
    ) {
      VStack(spacing: 12) {
        ForEach(InjuryFlag.allCases, id: \.self) { flag in
          SelectCard(
            title: flag.name,
            symbol: injurySymbols[flag] ?? "circle",
            selected: injuries.contains(flag)) {
            withAnimation(.snappy) {
              if injuries.contains(flag) { injuries.remove(flag) } else { injuries.insert(flag) }
            }
          }
        }
        SelectCard(title: String(localized: "None", bundle: L10n.bundle), symbol: "minus.circle", selected: injuries.isEmpty) {
          withAnimation(.snappy) { injuries.removeAll() }
        }
        VStack(alignment: .leading, spacing: 4) {
          Toggle("I sleep under 6 h or life stress is high", isOn: $recoveryReduced)
            .accessibilityIdentifier("recovery-reduced-toggle")
          Text(String(localized: "Lowers weekly max sets by 15 %.", bundle: L10n.bundle))
            .forgeCaption()
        }
        .card()
      }
    }
  }

  private var photoPage: some View {
    page(title: String(localized: "A starting photo", bundle: L10n.bundle)) {
      VStack(spacing: 16) {
        if let photoData, let image = UIImage(data: photoData) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                .strokeBorder(Theme.imageOutline, lineWidth: 1)
            )
            .frame(height: 220)
            .accessibilityLabel("Your starting photo")
            .transition(.opacity)
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
          Label("Choose photo", systemImage: "photo.on.rectangle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle())
        Text("Optional front pose. You can add more poses later in Progress.")
          .forgeCaption()
          .multilineTextAlignment(.center)
        Button {
          advance()
        } label: {
          Text("Skip for now")
            .forge(15, .semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
      }
    }
  }

  private var firstSetPage: some View {
    page(
      title: String(localized: "Try your", bundle: L10n.bundle),
      accent: String(localized: "first set.", bundle: L10n.bundle),
      subtitle: String(localized: "One set from your day 1. Nothing is saved.", bundle: L10n.bundle)
    ) {
      if let planned = firstSetExercise {
        firstSetCard(planned)
        answerBubble(firstSetCoachText(planned))
      }
    }
  }

  private func firstSetCard(_ planned: PlannedExercise) -> some View {
    let startKg = startingKg(planned)
    let reps = planned.repRange.lowerBound
    return VStack(alignment: .leading, spacing: 12) {
      Text(planned.exercise.localizedName).forgeSection()
      Text(verbatim: "\(loadText(startKg)) × \(reps)")
        .forge(34, .bold)
        .monospacedDigit()
      if demoLogged {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
          Text(String(localized: "Set logged", bundle: L10n.bundle)).forgeBodyStrong()
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.positiveTint))
        rpeChips
        if let demoRPE {
          let next = demoNext(planned, from: startKg, rpe: Double(demoRPE))
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Next session: \(loadText(next.kg))", bundle: L10n.bundle))
              .forge(17, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.metricLoad)
            Text(next.reason).forgeLabel()
          }
          .transition(.opacity)
        }
      } else {
        Button {
          withAnimation(.snappy(duration: 0.2)) { demoLogged = true }
        } label: {
          Text(String(localized: "Log set", bundle: L10n.bundle))
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityIdentifier("onboarding-log-set")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 16)
    .sensoryFeedback(.success, trigger: demoLogged)
  }

  private var rpeChips: some View {
    HStack(spacing: 8) {
      ForEach(6...10, id: \.self) { rpe in
        Button {
          withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { demoRPE = rpe }
        } label: {
          Text(verbatim: "\(rpe)")
            .forge(15, .semibold)
            .monospacedDigit()
            .foregroundStyle(demoRPE == rpe ? Theme.onAccent : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(demoRPE == rpe ? Theme.metricEffort : Theme.innerSurface))
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(String(localized: "RPE \(String(rpe))", bundle: L10n.bundle))
        .accessibilityAddTraits(demoRPE == rpe ? .isSelected : [])
      }
    }
  }

  private func firstSetCoachText(_ planned: PlannedExercise) -> String {
    if !demoLogged {
      return String(localized: "This is set 1 of your first session. Log it when you are ready.", bundle: L10n.bundle)
    }
    if demoRPE == nil {
      return String(localized: "How hard did that feel? The target is RPE \(Fmt.num(planned.targetRPE)).", bundle: L10n.bundle)
    }
    return String(localized: "That is the whole loop. You log, I program.", bundle: L10n.bundle)
  }

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
        Circle().stroke(Theme.track, lineWidth: 8)
        Circle()
          .trim(from: 0, to: buildProgress)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 96, height: 96)
      Text(String(localized: "Building your plan", bundle: L10n.bundle))
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Building your plan", bundle: L10n.bundle))
  }

  private var summaryPage: some View {
    let week = Program.week(1, profile: input)
    return page(title: String(localized: "Week 1 is ready", bundle: L10n.bundle), subtitle: planBasis) {
      weekCard(week)
      if let day = week.first {
        firstSessionCard(day)
      }
      HStack(alignment: .top, spacing: 10) {
        CoachAvatar(size: 36)
        SpeechBubble(tint: Theme.card) {
          Text(String(localized: "Log reps and RPE; next session's loads adjust.", bundle: L10n.bundle)).forgeBody()
        }
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
      promoCard
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

  private func weekCard(_ week: [PlannedDay]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "Week \(1) of \(Mesocycle.weeks)", bundle: L10n.bundle))
        .forgeSection()
        .padding(.bottom, 4)
      // Positional ids: `Program.split` repeats day names ("Upper", "Lower", "Upper").
      ForEach(Array(week.enumerated()), id: \.offset) { index, day in
        if index > 0 { Divider() }
        sessionRow(index + 1, day)
          .reveal(index, appeared: planShown, stagger: 0.1)
      }
    }
    .card(padding: 16)
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
      VStack(alignment: .trailing, spacing: 2) {
        Text(String(localized: "\(sets) sets", bundle: L10n.bundle))
          .forge(14, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
      .fixedSize()
    }
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }

  private func dayBadge(_ number: Int) -> some View {
    Text(verbatim: "\(number)")
      .forge(15, .bold)
      .monospacedDigit()
      .foregroundStyle(Theme.accent)
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
              .foregroundStyle(Theme.metricLoad)
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

  private func demoNext(_ planned: PlannedExercise, from kg: Double, rpe: Double) -> (kg: Double, reason: String) {
    let next: Double
    let reason: String
    switch Progression.nextLoad(currentKg: kg, targetRPE: planned.targetRPE, actualRPE: rpe) {
    case .increase(let k):
      next = k
      reason = String(localized: "Easier than target, so the load goes up.", bundle: L10n.bundle)
    case .addReps(let k), .repeatLoad(let k):  // whole-number chips never produce .repeatLoad
      next = k
      reason = String(localized: "On target: same load, add reps.", bundle: L10n.bundle)
    case .decrease(let k, _):
      next = k
      reason = String(localized: "Harder than target, so the load comes down.", bundle: L10n.bundle)
    }
    return (Progression.round(next, toIncrement: planned.exercise.smallestIncrementKg), reason)
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
    if !pendingCode.isEmpty { Analytics.track("code_entered") }
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
    savedTick &+= 1
  }
}
