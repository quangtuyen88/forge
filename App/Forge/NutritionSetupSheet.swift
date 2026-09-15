import SwiftUI
import SwiftData
import ForgeCore

struct NutritionSetupSheet: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  let existing: NutritionProfile?
  let weightKg: Double
  let weeklySets: Int
  let usesLb: Bool

  @State private var sex: Sex = .male
  @State private var age = 30
  @State private var heightCm = 178.0
  @State private var activity: ActivityLevel = .moderate
  @State private var phase: Phase = .recomp
  @State private var loaded = false

  private var targets: MacroTargets {
    Nutrition.targets(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity, phase: phase, weeklySets: weeklySets)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          row("Sex") {
            Picker("Sex", selection: $sex) {
              ForEach(Sex.allCases, id: \.self) { s in Text(s == .male ? "Male" : "Female").tag(s) }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
          }
          row("Age") {
            Stepper("\(age)", value: $age, in: 14...90)
              .forgeBodyStrong()
              .monospacedDigit()
          }
          row("Height") {
            Stepper(usesLb ? "\(feetInches)" : "\(Int(heightCm)) cm", value: $heightCm, in: 130...220, step: 1)
              .forgeBodyStrong()
              .monospacedDigit()
          }
          row("Activity") {
            Picker("Activity", selection: $activity) {
              ForEach(ActivityLevel.allCases, id: \.self) { level in
                Text(label(for: level)).tag(level)
              }
            }
            .pickerStyle(.menu)
          }
          row("Phase") {
            Picker("Phase", selection: $phase) {
              ForEach(Phase.allCases, id: \.self) { p in Text(p.rawValue.capitalized).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
          }
          Text("Weight \(UnitFormat.weight(weightKg, usesLb: usesLb)) · \(weeklySets) hard sets this week")
            .forgeCaption()
            .monospacedDigit()
          HStack(spacing: 10) {
            StatTile(symbol: "flame.fill", value: Fmt.grouped(Double(targets.kcal)), label: "kcal")
            StatTile(symbol: "fish.fill", value: Fmt.grouped(Double(targets.proteinG)) + " g", label: "protein")
          }
          HStack(spacing: 10) {
            StatTile(symbol: "leaf.fill", value: Fmt.grouped(Double(targets.carbsG)) + " g", label: "carbs")
            StatTile(symbol: "drop.fill", value: Fmt.grouped(Double(targets.fatG)) + " g", label: "fat")
          }
          Button("Save") { save() }
            .buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Fuel targets")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
      .onAppear {
        guard !loaded else { return }
        loaded = true
        if let existing {
          sex = Sex(rawValue: existing.sex) ?? .male
          age = existing.age
          heightCm = existing.heightCm
          activity = ActivityLevel(rawValue: existing.activity) ?? .moderate
          phase = Phase(rawValue: existing.phase) ?? .recomp
        }
      }
    }
    .presentationBackground(Theme.page)
  }

  private var feetInches: String {
    let totalInches = heightCm / 2.54
    return String(format: "%d′%d″", Int(totalInches / 12), Int(totalInches.truncatingRemainder(dividingBy: 12)))
  }

  private func label(for level: ActivityLevel) -> String {
    switch level {
    case .sedentary: return "Sedentary"
    case .light: return "Light"
    case .moderate: return "Moderate"
    case .high: return "High"
    }
  }

  private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
      Text(title).forgeBodyStrong()
      Spacer()
      content()
    }
    .innerSurface()
  }

  private func save() {
    let profile: NutritionProfile
    if let existing {
      profile = existing
      profile.sex = sex.rawValue
      profile.age = age
      profile.heightCm = heightCm
      profile.activity = activity.rawValue
      profile.phase = phase.rawValue
    } else {
      profile = NutritionProfile(sex: sex, age: age, heightCm: heightCm, activity: activity, phase: phase)
      modelContext.insert(profile)
    }
    Macros.recompute(profile: profile, weightKg: weightKg, weeklySets: weeklySets)
    dismiss()
  }
}
