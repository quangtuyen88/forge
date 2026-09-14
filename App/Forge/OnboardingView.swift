import SwiftUI
import SwiftData
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
  @FocusState private var fieldFocused: Bool

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
    case 2: return !equipment.isEmpty
    case 3: return bodyweightKg > 0
    default: return true
    }
  }

  private var pageTransition: AnyTransition {
    .push(from: goingForward ? .trailing : .leading)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 8) {
        ProgressView(value: Double(step + 1), total: 6)
          .tint(Theme.accent)
          .frame(height: 4)
          .padding(.horizontal, 16)
        ZStack {
          switch step {
          case 0: goalPage.transition(pageTransition)
          case 1: schedulePage.transition(pageTransition)
          case 2: equipmentPage.transition(pageTransition)
          case 3: numbersPage.transition(pageTransition)
          case 4: workaroundsPage.transition(pageTransition)
          default: summaryPage.transition(pageTransition)
          }
        }
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
      .onChange(of: step) { _, _ in fieldFocused = false }
      .safeAreaInset(edge: .bottom) {
        Button {
          if step < 5 {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
      }
    }
  }

  private func page(art: String, title: String, @ViewBuilder content: () -> some View) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Illustration(name: art, height: 150)
          Text(title).font(.title2.bold())
        }
        content()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private var goalPage: some View {
    page(art: "coach-wave", title: "Your goal") {
      VStack(spacing: 8) {
        SelectCard(title: "Hypertrophy", subtitle: "Build muscle", symbol: "figure.strengthtraining.traditional", selected: goal == .hypertrophy) {
          withAnimation(.snappy) { goal = .hypertrophy }
        }
        SelectCard(title: "Strength", subtitle: "Move more weight", symbol: "scalemass", selected: goal == .strength) {
          withAnimation(.snappy) { goal = .strength }
        }
        SelectCard(title: "Both", subtitle: "Size and strength", symbol: "bolt.heart", selected: goal == .both) {
          withAnimation(.snappy) { goal = .both }
        }
      }
    }
  }

  private var schedulePage: some View {
    page(art: "art-schedule", title: "Your week") {
      VStack(spacing: 8) {
        SelectCard(title: "Post-beginner", subtitle: "1–2 years", symbol: "1.circle", selected: experience == .postBeginner) {
          withAnimation(.snappy) { experience = .postBeginner }
        }
        SelectCard(title: "Intermediate", subtitle: "2–4 years", symbol: "2.circle", selected: experience == .intermediate) {
          withAnimation(.snappy) { experience = .intermediate }
        }
        SelectCard(title: "Advanced", subtitle: "4+ years", symbol: "3.circle", selected: experience == .advanced) {
          withAnimation(.snappy) { experience = .advanced }
        }
        VStack(spacing: 12) {
          Stepper(value: $daysPerWeek, in: 3...6) {
            HStack {
              Text("Days per week")
              Spacer()
              Text("\(daysPerWeek)").font(.headline.monospacedDigit())
            }
          }
          Picker("Session length", selection: $sessionLength) {
            ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").tag($0) }
          }
          .pickerStyle(.segmented)
        }
        .card()
      }
    }
  }

  private var equipmentPage: some View {
    page(art: "art-equipment", title: "Your gym") {
      VStack(spacing: 8) {
        ForEach(Equipment.allCases, id: \.self) { item in
          SelectCard(
            title: item.rawValue.capitalized,
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
    page(art: "art-numbers", title: "Your numbers") {
      VStack(spacing: 8) {
        VStack(spacing: 12) {
          Picker("Units", selection: $usesLb) {
            Text("kg").tag(false)
            Text("lb").tag(true)
          }
          .pickerStyle(.segmented)
          HStack {
            TextField(usesLb ? "Bodyweight (lb)" : "Bodyweight (kg)", text: $bodyweightText)
              .keyboardType(.decimalPad)
              .focused($fieldFocused)
            Text(usesLb ? "lb" : "kg")
              .foregroundStyle(.secondary)
          }
        }
        .card()
        VStack(alignment: .leading, spacing: 12) {
          Text("Current lifts (optional)").font(.headline)
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
            }
          }
          Text("Leave blank and we estimate from bodyweight.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .card()
      }
    }
  }

  private var workaroundsPage: some View {
    page(art: "art-injury", title: "Work around") {
      VStack(spacing: 8) {
        ForEach(InjuryFlag.allCases, id: \.self) { flag in
          SelectCard(
            title: flag.rawValue.capitalized,
            symbol: injurySymbols[flag] ?? "circle",
            selected: injuries.contains(flag)) {
            withAnimation(.snappy) {
              if injuries.contains(flag) { injuries.remove(flag) } else { injuries.insert(flag) }
            }
          }
        }
        SelectCard(title: "None", symbol: "minus.circle", selected: injuries.isEmpty) {
          withAnimation(.snappy) { injuries.removeAll() }
        }
        Toggle("I sleep under 6 h or life stress is high", isOn: $recoveryReduced)
          .card()
      }
    }
  }

  private var summaryPage: some View {
    page(art: "coach-point", title: "Your plan") {
      let day = Program.week(1, profile: input).first
      VStack(alignment: .leading, spacing: 12) {
        Text(Program.split(daysPerWeek: daysPerWeek).joined(separator: " · "))
          .font(.headline)
        LabeledContent("Days per week", value: "\(daysPerWeek)")
        LabeledContent("Session length", value: "\(sessionLength.rawValue) min")
        LabeledContent("Goal", value: goal.rawValue.capitalized)
        if let day {
          Divider()
          Text(day.name).font(.subheadline.weight(.semibold))
          ForEach(day.exercises, id: \.self) { planned in
            Text("\(planned.exercise.name) — \(planned.sets) sets × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .card()
    }
  }

  private func liftBinding(_ id: String) -> Binding<String> {
    Binding(
      get: { lifts[id] ?? "" },
      set: { lifts[id] = $0 })
  }

  private func liftName(_ id: String) -> String {
    let name = ExerciseDB.find(id)?.name ?? id
    return "\(name) (\(usesLb ? "lb" : "kg"))"
  }

  private func number(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: "."))
  }

  private func save() {
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
  }
}
