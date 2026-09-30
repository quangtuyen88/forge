import ForgeCore
import SwiftData
import SwiftUI

/// Gym & equipment: preset chips that swap the whole setup, tiles for single pieces,
/// and the lifts those changes actually swap in the plan.
struct GymPage: View {
  @Bindable var profile: UserProfile
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var snapshot: (constraints: TrainingConstraints, equipment: Set<Equipment>)?

  private var owned: Set<Equipment> { Set(profile.equipment.compactMap(Equipment.init(rawValue:))) }
  private var matched: GymPreset? { GymPreset.matching(owned) }
  private var gymName: String { SettingsFormat.gymName(equipment: profile.equipment) }

  private var changed: Bool {
    guard let snapshot else { return false }
    return profile.profileInput.equipment != snapshot.equipment
  }

  /// What lifting with the current setup changes versus the setup the page opened with.
  private var swaps: [ExerciseSwap] {
    guard changed, let snapshot else { return [] }
    var before = profile.profileInput
    before.equipment = snapshot.equipment
    return Personalization.exerciseSwapDetails(before: before, after: profile.profileInput)
  }

  private func hero(_ swaps: [ExerciseSwap]) -> (title: String, subtitle: String) {
    if !changed {
      return (
        String(localized: "\(gymName).", bundle: L10n.bundle),
        matched?.detail ?? String(localized: "Your own mix of equipment.", bundle: L10n.bundle)
      )
    }
    let title = swaps.isEmpty
      ? String(localized: "\(gymName): no lifts change.", bundle: L10n.bundle)
      : String(localized: "\(gymName): \(swaps.count) lift\(L10n.pluralSuffix(swaps.count)) change.", bundle: L10n.bundle)
    return (title, String(localized: "The rest of your plan stays the same.", bundle: L10n.bundle))
  }

  var body: some View {
    let changes = swaps
    return SettingsFieldPage(title: String(localized: "Gym & equipment", bundle: L10n.bundle)) {
      SettingsHero(title: hero(changes).title, subtitle: hero(changes).subtitle)
      SettingsSectionLabel(String(localized: "Gym presets", bundle: L10n.bundle))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(GymPreset.allCases, id: \.self) { preset in
            SettingsChip(title: preset.name, selected: matched == preset) { apply(preset) }
              .accessibilityIdentifier("settings.gym.preset.\(preset.rawValue)")
          }
          if matched == nil {
            SettingsChip(title: String(localized: "Custom", bundle: L10n.bundle), selected: true) {}
              .disabled(true)
          }
        }
        .padding(.horizontal, Theme.margin)
      }
      .padding(.horizontal, -Theme.margin)
      if changed {
        ApprovalPill(kind: .updated, onTap: {}, onUndo: undo)
      }
    } content: {
      SettingsSectionLabel(String(localized: "Equipment", bundle: L10n.bundle))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
        ForEach(Equipment.allCases, id: \.self) { e in
          EquipmentTile(equipment: e, owned: owned.contains(e)) { toggle(e) }
            .accessibilityIdentifier("settings.gym.equipment.\(e.rawValue)")
        }
      }
      .padding(.top, 8)
      if !changes.isEmpty {
        SettingsSectionLabel(String(localized: "What changes", bundle: L10n.bundle))
        ForEach(changes.indices, id: \.self) { index in
          if index > 0 { SettingsHairline(inset: false) }
          SettingsRow(
            title: changes[index].toName ?? changes[index].fromName ?? "",
            subtitle: changes[index].detail,
            accessory: .none)
        }
      }
    }
    .onAppear {
      if snapshot == nil { snapshot = (profile.trainingConstraints, profile.profileInput.equipment) }
    }
  }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  /// The pill appears and the hero rewords; both are animated so the change reads as one move.
  private func animate(_ change: () -> Void) {
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25)) { change() }
  }

  private func apply(_ preset: GymPreset) {
    animate {
      var constraints = profile.trainingConstraints
      let gym = GymProfileConfig(id: preset.rawValue, name: preset.name, equipment: preset.equipment)
      if let index = constraints.gymProfiles.firstIndex(where: { $0.id == gym.id }) {
        constraints.gymProfiles[index] = gym
      } else {
        constraints.gymProfiles.append(gym)
      }
      constraints.activeGymProfileID = gym.id
      profile.trainingConstraints = constraints
    }
    Analytics.track("gym_preset", ["preset": preset.rawValue])
    touch()
  }

  private func toggle(_ item: Equipment) {
    animate {
      var equipment = owned
      if equipment.contains(item) { equipment.remove(item) } else { equipment.insert(item) }
      var constraints = profile.trainingConstraints
      let custom = GymProfileConfig(id: "custom", name: "Custom", equipment: equipment)
      if let index = constraints.gymProfiles.firstIndex(where: { $0.id == custom.id }) {
        constraints.gymProfiles[index] = custom
      } else {
        constraints.gymProfiles.append(custom)
      }
      constraints.activeGymProfileID = custom.id
      profile.trainingConstraints = constraints
    }
    touch()
  }

  private func undo() {
    guard let snapshot else { return }
    animate { profile.trainingConstraints = snapshot.constraints }
    touch()
  }
}

/// Plates & bar: the discs you own, the bar you load, and the smallest jump that allows.
struct PlatesPage: View {
  @Bindable var profile: UserProfile
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.modelContext) private var modelContext

  private var usesLb: Bool { profile.usesLb }
  private var owned: [Double] { usesLb ? profile.platesLb : profile.platesKg }
  private var jump: Double? { PlateMath.smallestJump(owned: owned) }
  private var lightest: Double? { owned.filter { $0 > 0 }.min() }
  private var finer: Double? { PlateMath.missingFinerPlate(owned: owned, usesLb: usesLb) }
  private var example: BarbellExample? {
    SettingsExamples.barbellExample(profile: profile, sessions: sessions)
  }

  private var heroTitle: String {
    if let jump {
      return String(localized: "Smallest jump: \(Fmt.kg(jump, lb: usesLb)).", bundle: L10n.bundle)
    }
    return String(localized: "No plates yet.", bundle: L10n.bundle)
  }

  private var heroSubtitle: String {
    guard let lightest else {
      return String(localized: "Tap the plates you own below.", bundle: L10n.bundle)
    }
    var text = String(localized: "One \(plateText(lightest)) plate on each side.", bundle: L10n.bundle)
    if let finer {
      text += " "
        + String(
          localized: "Add \(plateText(finer)) plates for \(Fmt.kg(finer * 2, lb: usesLb)) jumps.",
          bundle: L10n.bundle)
    }
    return text
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Plates & bar", bundle: L10n.bundle)) {
      SettingsHero(title: heroTitle, subtitle: heroSubtitle)
      if let example {
        VStack(alignment: .leading, spacing: 0) {
          BarbellDiagram(perSide: example.perSide, usesLb: example.usesLb, highlight: lightest)
          Text(
            example.isToday
              ? String(
                localized: "\(example.liftName) today · \(loadText(example))", bundle: L10n.bundle)
              : String(
                localized: "Next \(example.liftName) · \(loadText(example))", bundle: L10n.bundle)
          )
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
          .padding(.top, 8)
        }
      }
    } content: {
      SettingsSectionLabel(String(localized: "Bar", bundle: L10n.bundle))
      Picker(String(localized: "Bar", bundle: L10n.bundle), selection: barBinding) {
        ForEach(
          PlateMath.barChoices(usesLb: usesLb, current: usesLb ? profile.barLb : profile.barKg),
          id: \.self
        ) { w in
          Text(plateText(w)).tag(w)
        }
      }
      .pickerStyle(.segmented)
      .padding(.top, 8)
      .accessibilityIdentifier("settings.plates.bar")

      SettingsSectionLabel(String(localized: "Plates you own", bundle: L10n.bundle))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 21) {
        ForEach(PlateMath.catalogue(usesLb: usesLb), id: \.self) { w in
          PlateDisc(weight: w, usesLb: usesLb, owned: owned.contains(w)) { togglePlate(w) }
            .accessibilityIdentifier("settings.plates.plate.\(Fmt.num(w, max: 2))")
        }
      }
      .padding(.top, 12)
    }
  }

  /// Plate weights keep two decimals: 1.25 must read "1.25 kg", not a rounded "1.3 kg".
  private func plateText(_ w: Double) -> String {
    Fmt.num(w, max: 2) + (usesLb ? " lb" : " kg")
  }

  private func loadText(_ example: BarbellExample) -> String {
    Fmt.num(example.load, max: 2) + (example.usesLb ? " lb" : " kg")
  }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  private var barBinding: Binding<Double> {
    Binding(
      get: { usesLb ? profile.barLb : profile.barKg },
      set: { w in
        if usesLb { profile.barLb = w } else { profile.barKg = w }
        touch()
      })
  }

  private func togglePlate(_ plate: Double) {
    var plates = owned
    if plates.contains(plate) {
      plates.removeAll { $0 == plate }
    } else {
      plates.append(plate)
    }
    let sorted = plates.sorted(by: >)
    if usesLb { profile.platesLb = sorted } else { profile.platesKg = sorted }
    touch()
  }
}
