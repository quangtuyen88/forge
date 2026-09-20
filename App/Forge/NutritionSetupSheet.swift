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
          row(String(localized: "Sex", bundle: L10n.bundle)) {
            Picker("Sex", selection: $sex) {
              ForEach(Sex.allCases, id: \.self) { s in Text(s.name).tag(s) }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
          }
          row(String(localized: "Age", bundle: L10n.bundle)) {
            Stepper("\(age)", value: $age, in: 14...90)
              .forgeBodyStrong()
              .monospacedDigit()
          }
          row(String(localized: "Height", bundle: L10n.bundle)) {
            Stepper(usesLb ? String(localized: "\(feetInches)", bundle: L10n.bundle) : String(localized: "\(Int(heightCm)) cm", bundle: L10n.bundle), value: $heightCm, in: 130...220, step: 1)
              .forgeBodyStrong()
              .monospacedDigit()
          }
          row(String(localized: "Activity", bundle: L10n.bundle)) {
            Picker("Activity", selection: $activity) {
              ForEach(ActivityLevel.allCases, id: \.self) { level in
                Text(level.name).tag(level)
              }
            }
            .pickerStyle(.menu)
          }
          row(String(localized: "Phase", bundle: L10n.bundle)) {
            Picker("Phase", selection: $phase) {
              ForEach(Phase.allCases, id: \.self) { p in Text(p.name).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
          }
          Text("Weight \(UnitFormat.weight(weightKg, usesLb: usesLb)) · \(weeklySets) hard sets this week")
            .forgeCaption()
            .monospacedDigit()
          HStack(spacing: 10) {
            StatTile(symbol: "flame.fill", value: Fmt.grouped(Double(targets.kcal)), label: String(localized: "kcal", bundle: L10n.bundle))
            StatTile(symbol: "fish.fill", value: Fmt.grouped(Double(targets.proteinG)) + " g", label: String(localized: "protein", bundle: L10n.bundle))
          }
          HStack(spacing: 10) {
            StatTile(symbol: "leaf.fill", value: Fmt.grouped(Double(targets.carbsG)) + " g", label: String(localized: "carbs", bundle: L10n.bundle))
            StatTile(symbol: "drop.fill", value: Fmt.grouped(Double(targets.fatG)) + " g", label: String(localized: "fat", bundle: L10n.bundle))
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
    try? modelContext.save()
    dismiss()
  }
}
