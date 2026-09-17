import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import ForgeCore

struct OnboardingView: View {
  @Environment(\.modelContext) private var modelContext

  @State private var step = 0
  @State private var goingForward = true
  @State private var goal: Goal = .hypertrophy
  @State private var experience: Experience = .intermediate
  @State private var daysPerWeek = 3
  @State private var sessionLength: SessionLength = .m60
  @State private var equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable]
  @State private var usesLb = false
  @State private var bodyweightText = ""
  @State private var lifts: [String: String] = [:]
  @State private var injuries: Set<InjuryFlag> = []
  @State private var recoveryReduced = false
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?
  @FocusState private var fieldFocused: Bool
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("pendingCode") private var pendingCode = ""

  private var coach: Coach { Coach.from(coachID) }

  private let liftIDs = ["barbell_bench", "back_squat", "deadlift", "overhead_press", "bent_row"]

  private let equipmentSymbols: [Equipment: String] = [
    .barbell: "dumbbell",
    .dumbbell: "dumbbell.fill",
    .machine: "gearshape.2",
    .cable: "cable.connector",
    .bodyweight: "figure.core.training",
    .bands: "circle.dashed",
  ]

  private let injurySymbols: [InjuryFlag: String] = [
    .shoulder: "figure.arms.open",
    .knee: "figure.walk",
    .back: "figure.stand",
  ]

  private var bodyweightKg: Double {
    guard let v = number(bodyweightText) else { return 0 }
    return usesLb ? Plates.lbToKg(v) : v
  }

  private var input: ProfileInput {
    ProfileInput(
      goal: goal,
      daysPerWeek: daysPerWeek,
      sessionLength: sessionLength,
      equipment: equipment,
      injuryFlags: injuries,
      recoveryReduced: recoveryReduced)
  }

  private var canContinue: Bool {
    switch step {
    case 3: return !equipment.isEmpty
    case 4: return bodyweightKg > 0
    default: return true
    }
  }

  private var pageTransition: AnyTransition {
    .push(from: goingForward ? .trailing : .leading)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 8) {
        ProgressView(value: Double(step + 1), total: 8)
          .tint(Theme.accent)
          .frame(height: 4)
          .padding(.horizontal, Theme.margin)
          .accessibilityLabel("Step \(step + 1) of 8")
        ZStack {
          switch step {
          case 0: coachPage.transition(pageTransition)
          case 1: goalPage.transition(pageTransition)
          case 2: schedulePage.transition(pageTransition)
          case 3: equipmentPage.transition(pageTransition)
          case 4: numbersPage.transition(pageTransition)
          case 5: workaroundsPage.transition(pageTransition)
          case 6: photoPage.transition(pageTransition)
          default: summaryPage.transition(pageTransition)
          }
        }
      }
      .background(Theme.page.ignoresSafeArea())
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        if step > 0 {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              goingForward = false
              withAnimation(.snappy) { step -= 1 }
            } label: {
              Image(systemName: "chevron.left")
            }
          }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { fieldFocused = false }
        }
      }
      .onAppear { Analytics.track("onboarding_step", ["step": "0"]) }
      .onChange(of: step) { _, new in
        fieldFocused = false
        Analytics.track("onboarding_step", ["step": "\(new)"])
      }
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self) { photoData = data }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          if step < 7 {
            goingForward = true
            withAnimation(.snappy) { step += 1 }
          } else {
            save()
          }
        } label: {
          Text("Continue")
        }
        .buttonStyle(PillButtonStyle())
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.4)
        .padding(.horizontal, Theme.barMargin)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.page.opacity(0.92))
        .background(.ultraThinMaterial)
      }
    }
  }

  private func page(art: String?, title: String, @ViewBuilder content: () -> some View) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          if let art, art.hasPrefix("coach-") || art.hasPrefix("kai-") {
            CoachPhoto(name: art, height: 180)
          } else if let art {
            Illustration(name: art, height: 150)
          }
          Text(title).forgeTitle()
        }
        content()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(Theme.margin)
    }
    .scrollBounceBehavior(.basedOnSize)
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

  private var goalPage: some View {
    page(art: coach.wave, title: String(localized: "Your goal", bundle: L10n.bundle)) {
      VStack(spacing: 8) {
        SelectCard(title: String(localized: "Hypertrophy", bundle: L10n.bundle), subtitle: String(localized: "Build muscle", bundle: L10n.bundle), symbol: "figure.strengthtraining.traditional", selected: goal == .hypertrophy) {
          withAnimation(.snappy) { goal = .hypertrophy }
        }
        SelectCard(title: String(localized: "Strength", bundle: L10n.bundle), subtitle: String(localized: "Move more weight", bundle: L10n.bundle), symbol: "scalemass", selected: goal == .strength) {
          withAnimation(.snappy) { goal = .strength }
        }
        SelectCard(title: String(localized: "Both", bundle: L10n.bundle), subtitle: String(localized: "Size and strength", bundle: L10n.bundle), symbol: "bolt.heart", selected: goal == .both) {
          withAnimation(.snappy) { goal = .both }
        }
      }
    }
  }

  private var schedulePage: some View {
    page(art: "art-schedule", title: String(localized: "Your week", bundle: L10n.bundle)) {
      VStack(spacing: 8) {
        SelectCard(title: String(localized: "Post-beginner", bundle: L10n.bundle), subtitle: String(localized: "1–2 years", bundle: L10n.bundle), symbol: "1.circle", selected: experience == .postBeginner) {
          withAnimation(.snappy) { experience = .postBeginner }
        }
        SelectCard(title: String(localized: "Intermediate", bundle: L10n.bundle), subtitle: String(localized: "2–4 years", bundle: L10n.bundle), symbol: "2.circle", selected: experience == .intermediate) {
          withAnimation(.snappy) { experience = .intermediate }
        }
        SelectCard(title: String(localized: "Advanced", bundle: L10n.bundle), subtitle: String(localized: "4+ years", bundle: L10n.bundle), symbol: "3.circle", selected: experience == .advanced) {
          withAnimation(.snappy) { experience = .advanced }
        }
        VStack(spacing: 12) {
          Stepper(value: $daysPerWeek, in: 3...6) {
            HStack {
              Text("Days per week").forgeBody()
              Spacer()
              Text("\(daysPerWeek)").forge(15, .semibold).monospacedDigit()
            }
          }
          Picker("Session length", selection: $sessionLength) {
            ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").forge(13, .medium).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        .card()
      }
    }
  }

  private var equipmentPage: some View {
    page(art: "art-equipment", title: String(localized: "Your gym", bundle: L10n.bundle)) {
      VStack(spacing: 8) {
        ForEach(Equipment.allCases, id: \.self) { item in
          SelectCard(
            title: item.name,
            symbol: equipmentSymbols[item] ?? "circle",
            selected: equipment.contains(item)) {
            withAnimation(.snappy) {
              if equipment.contains(item) { equipment.remove(item) } else { equipment.insert(item) }
            }
          }
        }
      }
    }
  }

  private var numbersPage: some View {
    page(art: "art-numbers", title: String(localized: "Your numbers", bundle: L10n.bundle)) {
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
              .focused($fieldFocused)
              .accessibilityLabel(usesLb ? String(localized: "Bodyweight in pounds", bundle: L10n.bundle) : String(localized: "Bodyweight in kilograms", bundle: L10n.bundle))
            Text(usesLb ? "lb" : "kg")
              .forgeLabel()
          }
        }
        .card()
        VStack(alignment: .leading, spacing: 12) {
          Text("Current lifts (optional)").forgeSection()
          ForEach(liftIDs, id: \.self) { id in
            HStack {
              Text(liftName(id))
              Spacer()
              TextField("—", text: liftBinding(id))
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
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
        VStack(alignment: .leading, spacing: 12) {
          Text("Referral or promo code").forgeSection()
          TextField("CODE", text: $pendingCode)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .onChange(of: pendingCode) { _, value in
              let capped = String(value.uppercased().prefix(12))
              if capped != value { pendingCode = capped }
            }
            .forgeBody()
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
            .accessibilityLabel("Referral or promo code")
          Text("Invited by a friend or have a promo? Optional.")
            .forgeCaption()
        }
        .card()
      }
    }
  }

  private var workaroundsPage: some View {
    page(art: "art-injury", title: String(localized: "Work around", bundle: L10n.bundle)) {
      VStack(spacing: 8) {
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
        Toggle("I sleep under 6 h or life stress is high", isOn: $recoveryReduced)
          .card()
      }
    }
  }

  private var photoPage: some View {
    page(art: "art-numbers", title: String(localized: "A starting photo", bundle: L10n.bundle)) {
      VStack(spacing: 16) {
        if let photoData, let image = UIImage(data: photoData) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
            .accessibilityLabel("Your starting photo")
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
          Label("Choose photo", systemImage: "photo.on.rectangle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle())
        Text("Optional front pose. You can add more poses later in Progress.")
          .forgeCaption()
          .multilineTextAlignment(.center)
        Button("Skip for now") {
          goingForward = true
          withAnimation(.snappy) { step += 1 }
        }
        .forgeCaption()
      }
    }
  }

  private var summaryPage: some View {
    let week = Program.week(1, profile: input)
    return page(art: coach.point, title: String(localized: "Week 1 is ready", bundle: L10n.bundle)) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          CoachAvatar(size: 36)
          SpeechBubble { Text("Built around your gym and your flags. Log RPE and I adjust from set one.").forgeBody() }
        }
        Text(Program.split(daysPerWeek: daysPerWeek).joined(separator: " · "))
          .forgeBodyStrong()
        LabeledContent("Days per week", value: "\(daysPerWeek)")
        LabeledContent("Session length", value: "\(sessionLength.rawValue) min")
        LabeledContent("Goal", value: goal.name)
        if let day = week.first {
          Divider()
          Text(localizedDayName(day.name)).forgeSection()
          ForEach(day.exercises, id: \.self) { planned in
            Text(summaryRowText(planned))
              .forgeLabel()
          }
        }
      }
      .card()
      VStack(alignment: .leading, spacing: 12) {
        Text("Built for you").forgeSection()
        ForEach(callouts, id: \.self) { line in
          HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent)
            Text(line).forgeBody()
          }
        }
      }
      .card()
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(week.enumerated()), id: \.offset) { _, day in
            summaryDayCard(day)
          }
        }
      }
    }
  }

  private var callouts: [String] {
    var lines = Personalization.lines(for: input)
    let n = liftIDs.filter { number(lifts[$0] ?? "") != nil }.count
    if n > 0 {
      lines.append(String(localized: "Starting loads from your \(n) entered lifts", bundle: L10n.bundle))
    } else {
      let bw = number(bodyweightText) ?? 0
      lines.append(String(localized: "Starting loads estimated from \(bw.formatted(.number.precision(.fractionLength(0...1)))) \(usesLb ? "lb" : "kg") bodyweight", bundle: L10n.bundle))
    }
    return Array(lines.prefix(5))
  }

  private func summaryRowText(_ planned: PlannedExercise) -> String {
    let base = String(localized: "\(planned.exercise.localizedName) — \(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)", bundle: L10n.bundle)
    let kg: Double
    if let entered = number(lifts[planned.exercise.id] ?? "") {
      kg = usesLb ? Plates.lbToKg(entered) : entered
    } else {
      kg = Strength.estimatedStartingLoad(exercise: planned.exercise, bodyweightKg: bodyweightKg)
    }
    let display = usesLb ? Plates.kgToLb(kg) : kg
    guard display > 0 else { return base }
    return String(localized: "\(base) · \(Int(display.rounded())) \(usesLb ? "lb" : "kg")", bundle: L10n.bundle)
  }

  private func summaryDayCard(_ day: PlannedDay) -> some View {
    let totalSets = day.exercises.reduce(0) { $0 + $1.sets }
    let minutes = Int((Double(totalSets) * 2.5 / 5).rounded() * 5)
    return VStack(alignment: .leading, spacing: 8) {
      Text(localizedDayName(day.name)).forgeBodyStrong()
      MuscleMapView(intensity: dayIntensity(day))
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
      Text(String(localized: "\(day.exercises.count) exercises · ≈ \(minutes) min", bundle: L10n.bundle))
        .forgeCaption()
    }
    .frame(width: 220, alignment: .leading)
    .card()
  }

  private func dayIntensity(_ day: PlannedDay) -> [Muscle: Double] {
    var sets: [Muscle: Int] = [:]
    for planned in day.exercises {
      sets[planned.exercise.primary, default: 0] += planned.sets
    }
    return sets.mapValues { min(Double($0) / 6, 1) }
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
    Double(text.replacingOccurrences(of: ",", with: "."))
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
      } else if let estimate = Strength.estimatedStartingLoad(exerciseID: id, bodyweightKg: bodyweightKg) {
        starting[id] = estimate
      }
    }
    modelContext.insert(UserProfile(
      goal: goal,
      experience: experience,
      daysPerWeek: daysPerWeek,
      sessionMinutes: sessionLength.rawValue,
      equipment: equipment,
      injuryFlags: injuries,
      recoveryReduced: recoveryReduced,
      bodyweightKg: bodyweightKg,
      usesLb: usesLb,
      startingLoads: starting))
    try? modelContext.save()
  }
}
