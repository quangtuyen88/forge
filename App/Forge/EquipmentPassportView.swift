import ForgeCore
import Foundation
import SwiftData
import SwiftUI

// MARK: - Display vocabulary
//
// Every user-facing string in this file goes through `String(localized:)` or a SwiftUI
// `Text` literal so it can be extracted. Nothing here is built from concatenated fragments.

/// Presented in the order a lifter thinks about their gym, not in enum order.
private let equipmentKindOrder: [EquipmentKind] = [
  .barbell, .dumbbell, .machine, .cable, .plateLoaded, .bodyweight, .bands, .unknown,
]

/// `LoadingConvention` is not `CaseIterable`, so the picker order lives here.
private let loadingConventionOrder: [LoadingConvention] = [
  .totalIncludingBar, .platesOnly, .perHand, .perSide, .combined, .assistanceDisplayed,
  .notApplicable, .unknown,
]

private func kindLabel(_ kind: EquipmentKind) -> String {
  switch kind {
  case .barbell: return String(localized: "Barbell")
  case .dumbbell: return String(localized: "Dumbbells")
  case .machine: return String(localized: "Selectorized machine")
  case .cable: return String(localized: "Cable stack")
  case .plateLoaded: return String(localized: "Plate-loaded machine")
  case .bodyweight: return String(localized: "Bodyweight")
  case .bands: return String(localized: "Bands")
  case .unknown: return String(localized: "Not sure yet")
  }
}

private func conventionLabel(_ convention: LoadingConvention) -> String {
  switch convention {
  case .perHand: return String(localized: "Per hand")
  case .combined: return String(localized: "Whole stack value")
  case .totalIncludingBar: return String(localized: "Total including bar")
  case .platesOnly: return String(localized: "Plates only")
  case .perSide: return String(localized: "Per side")
  case .assistanceDisplayed: return String(localized: "Assistance shown")
  case .notApplicable: return String(localized: "No numeric load")
  case .unknown: return String(localized: "Not confirmed")
  }
}

/// Plain words for what the number means. Shown under the convention picker so nobody has
/// to guess what "per hand" or "plates only" implies.
private func conventionExplanation(_ convention: LoadingConvention) -> String {
  switch convention {
  case .perHand:
    return String(localized: "The number is the weight of one dumbbell, not the pair.")
  case .combined:
    return String(localized: "The number is the whole stack value the machine prints.")
  case .totalIncludingBar:
    return String(localized: "The number includes the bar, for example a 20 kg bar plus the plates.")
  case .platesOnly:
    return String(localized: "The number is the plates alone. The bar is added on top.")
  case .perSide:
    return String(localized: "The number is one side of the bar, not both sides.")
  case .assistanceDisplayed:
    return String(localized: "The number is how much the machine helps you, not the weight you lift.")
  case .notApplicable:
    return String(localized: "This equipment has no number to record and no load step.")
  case .unknown:
    return String(localized: "We do not know what the number counts, so its loads stay unverified.")
  }
}

private func unitLabel(_ unit: LoadUnit) -> String {
  switch unit {
  case .kilograms: return String(localized: "Kilograms (kg)")
  case .pounds: return String(localized: "Pounds (lb)")
  case .unspecified: return String(localized: "Not set")
  }
}

private func statusLabel(_ status: LoadNormalizationStatus) -> String {
  status == .verified ? String(localized: "Verified") : String(localized: "Needs review")
}

private func statusColor(_ status: LoadNormalizationStatus) -> Color {
  status == .verified ? Theme.positive : Theme.plateGold
}

/// Renders a magnitude without a trailing `.0`.
private func quantity(_ value: Double) -> String {
  if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
  return String(format: "%g", value)
}

/// Comparison key for "these two rows carry the same label". Deliberately separate from
/// `EquipmentPassport.slug` (which is internal to ForgeCore): this is display-only and never
/// becomes an identity.
private func normalizeName(_ value: String) -> String {
  var out = ""
  for character in value.lowercased() where character.isLetter || character.isNumber {
    out.append(character)
  }
  return out
}

// MARK: - Equipment passport

/// Equipment Passport editor.
///
/// One job: let a lifter say what a number on a specific piece of equipment actually means.
/// The passport stores a versioned `LoadModel` per physical unit, so a recorded load is only
/// ever compared against another when the unit identity, load model revision, unit, and
/// loading convention all agree.
///
/// Two things this screen refuses to do:
///
///   * it never promotes an imported / legacy load model to verified on its own — only an
///     explicit Save that fills in the unit and convention does that, and the resulting model
///     is stated in words before saving;
///   * it never treats two similarly named machines as the same machine. Identity is the
///     instance ID plus `loadModel.revision`; the comparability card says that in plain words
///     and calls out name collisions in the data itself.
struct EquipmentPassportView: View {
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext

  @State private var passport = EquipmentPassport()
  @State private var savedPassport = EquipmentPassport()
  @State private var loaded = false
  @State private var hasSaved = false
  /// `nil` shows every location.
  @State private var filterGymID: String?
  @State private var editorTarget: EditorTarget?
  @State private var retiredToConfirm: EquipmentInstance?

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        activeGymCard
        if reviewCount > 0 { reviewWarningCard }
        if !importableInstances.isEmpty { importCard }
        if passport.instances.isEmpty { emptyCard }
        comparabilityCard
        if !passport.instances.isEmpty { locationFilterCard }
        equipmentSections
        if !retiredInstances.isEmpty { retiredSection }
        addButton
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(Theme.page)
    .navigationTitle(Text("Equipment passport"))
    .safeAreaInset(edge: .bottom) { saveBar }
    .onAppear(perform: load)
    .sheet(item: $editorTarget) { target in
      EquipmentInstanceEditor(
        gymProfiles: gymProfiles,
        existing: target.instance,
        siblings: passport.instances.filter { !$0.isRetired },
        activeGymProfileID: activeGym?.id ?? "",
        defaultUnit: defaultUnit,
        onSave: apply
      )
    }
    .confirmationDialog(
      "Retire this equipment?",
      isPresented: retireConfirmation,
      titleVisibility: .visible
    ) {
      Button("Retire", role: .destructive) {
        if let instance = retiredToConfirm { retire(instance) }
        retiredToConfirm = nil
      }
      Button("Cancel", role: .cancel) { retiredToConfirm = nil }
    } message: {
      Text("Retired equipment keeps every load already recorded against it, but is never picked for a workout again. You can restore it later.")
    }
  }

  // MARK: Model reads

  private var constraints: TrainingConstraints {
    profiles.first?.trainingConstraints ?? TrainingConstraints()
  }

  private var gymProfiles: [GymProfileConfig] { constraints.gymProfiles }

  private var activeGym: GymProfileConfig? { constraints.activeGymProfile }

  private var defaultUnit: LoadUnit { (profiles.first?.usesLb ?? false) ? .pounds : .kilograms }

  private func gymName(_ id: String?) -> String {
    guard let id else { return String(localized: "Travels with you") }
    return gymProfiles.first { $0.id == id }?.name ?? id
  }

  private func locationLabel(_ id: String?) -> String {
    id == nil ? String(localized: "Travels with you") : gymName(id)
  }

  private var allGymNames: [String: String] {
    var names: [String: String] = [:]
    for profile in gymProfiles { names[profile.id] = profile.name }
    return names
  }

  /// Instances usable at the active gym: the ones recorded there plus the location-less ones.
  private var activeGymInstances: [EquipmentInstance] {
    let live = passport.instances.filter { !$0.isRetired }
    guard let activeGymID = activeGym?.id else { return live.filter { $0.gymProfileID == nil } }
    return live.filter { $0.gymProfileID == activeGymID || $0.gymProfileID == nil }
  }

  private var verifiedCount: Int {
    activeGymInstances.filter { $0.loadModel.normalizationStatus == .verified }.count
  }

  private var reviewCount: Int {
    activeGymInstances.filter { $0.loadModel.normalizationStatus != .verified }.count
  }

  private var hasUnsavedChanges: Bool { passport != savedPassport }

  private func scoped(_ instances: [EquipmentInstance]) -> [EquipmentInstance] {
    guard let filterGymID else { return instances }
    return instances.filter { $0.gymProfileID == filterGymID || $0.gymProfileID == nil }
  }

  private var visibleInstances: [EquipmentInstance] {
    scoped(passport.instances.filter { !$0.isRetired }).sorted(by: rowOrder)
  }

  private var retiredInstances: [EquipmentInstance] {
    scoped(passport.instances.filter { $0.isRetired }).sorted(by: rowOrder)
  }

  private func rowOrder(_ a: EquipmentInstance, _ b: EquipmentInstance) -> Bool {
    if a.name != b.name {
      return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
    return a.id < b.id
  }

  private struct KindGroup: Identifiable {
    let kind: EquipmentKind
    let instances: [EquipmentInstance]
    var id: String { kind.rawValue }
  }

  private var kindGroups: [KindGroup] {
    let live = visibleInstances
    return equipmentKindOrder.compactMap { kind in
      let items = live.filter { $0.kind == kind }
      return items.isEmpty ? nil : KindGroup(kind: kind, instances: items)
    }
  }

  /// Proposals built from the legacy `TrainingConstraints` gym profiles. Unsaved until the
  /// lifter taps Save, which is what keeps "persist on explicit Save" true.
  private var importProposal: EquipmentPassport {
    profiles.first?.bootstrappedEquipmentPassport() ?? EquipmentPassport()
  }

  private var importableInstances: [EquipmentInstance] {
    let known = Set(passport.instances.map(\.id))
    return importProposal.instances.filter { !known.contains($0.id) }
  }

  /// Groups of live instances that share a label at the same location. Two of them are two
  /// physical units, so their loads can never be compared — the callout below says so.
  private struct NameCollision: Identifiable {
    let label: String
    let location: String
    let instances: [EquipmentInstance]
    var id: String { "\(label)@\(location)" }
  }

  private var nameCollisions: [NameCollision] {
    var buckets: [String: [EquipmentInstance]] = [:]
    for instance in passport.instances where !instance.isRetired {
      let key = "\(normalizeName(instance.name))@\(instance.gymProfileID ?? "")"
      let label = normalizeName(instance.name)
      guard !label.isEmpty else { continue }
      buckets[key, default: []].append(instance)
    }
    return buckets
      .filter { $0.value.count > 1 }
      .map { _, instances in
        let first = instances[0]
        return NameCollision(
          label: first.name,
          location: locationLabel(first.gymProfileID),
          instances: instances.sorted { $0.id < $1.id })
      }
      .sorted { $0.label < $1.label }
  }

  // MARK: Cards

  private var activeGymCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Active gym").forgeOverline()
      VStack(alignment: .leading, spacing: 3) {
        Text(activeGym?.name ?? String(localized: "No gym selected"))
          .forgeTitle()
          .fixedSize(horizontal: false, vertical: true)
        Text(activeGymSummary)
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 10) {
        activeGymMetric(
          value: verifiedCount,
          label: String(localized: "Verified"),
          symbol: "checkmark.seal.fill",
          tint: Theme.positive)
        activeGymMetric(
          value: reviewCount,
          label: String(localized: "Needs review"),
          symbol: "exclamationmark.triangle.fill",
          tint: Theme.plateGold)
      }
      Text("Set up in Training setup › Gym profiles. The passport only adds what a number means on each unit.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .card()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      Text("Active gym \(activeGym?.name ?? String(localized: "none")), \(activeGymSummary)"))
  }

  private var activeGymSummary: String {
    let total = activeGymInstances.count
    return String(localized: "\(total) items here · \(verifiedCount) verified · \(reviewCount) need review")
  }

  private func activeGymMetric(value: Int, label: String, symbol: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
        Text("\(value)")
          .font(.forge(28, .bold).monospacedDigit())
          .foregroundStyle(tint)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(label)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(label): \(value)"))
  }

  private var reviewWarningCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.plateGold)
        Text("Imported data needs confirming").forgeSection()
      }
      Text("\(reviewCount) items were carried over without a confirmed load meaning, so we do not know what their numbers count or which unit they are in.")
        .forgeBody()
        .fixedSize(horizontal: false, vertical: true)
      Text("Until you confirm a unit and a loading convention, loads recorded on those units stay separate from everything else. Nothing has been converted or rewritten.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .card()
  }

  private var importCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("From your training setup").forgeSection()
      Text(importExplanation)
        .forgeBody()
        .fixedSize(horizontal: false, vertical: true)
      Button {
        withAnimation(.easeOut(duration: 0.2)) { importLegacyEquipment() }
      } label: {
        Text("Add \(importableInstances.count) items")
      }
      .buttonStyle(PillSecondaryButtonStyle())
      .accessibilityLabel(Text("Add \(importableInstances.count) items from training setup"))
    }
    .card()
  }

  private var importExplanation: String {
    let ambiguous = importableInstances.filter { $0.loadModel.normalizationStatus != .verified }
      .count
    if ambiguous == 0 {
      return String(localized: "Your gym profiles list \(importableInstances.count) items. Adding them does not change any load already recorded.")
    }
    return String(
      localized: "Your gym profiles list \(importableInstances.count) items. \(ambiguous) of them — machines and cables — arrive as Needs review, because the app will not guess their unit or what their numbers mean.")
  }

  private var emptyCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("No equipment recorded yet").forgeSection()
      Text("Add the units you actually train on. Each one remembers what its number means, so a load you log today stays honest in six months.")
        .forgeBody()
        .fixedSize(horizontal: false, vertical: true)
    }
    .card()
    .accessibilityElement(children: .combine)
  }

  private var comparabilityCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("What can be compared").forgeSection()
      Text("A load is only compared with another when it is the same physical unit, the same load model revision, and the same loading convention. A matching name is not enough: two “Leg press” machines, or one that was re-plated last month, are different equipment.")
        .forgeBody()
        .fixedSize(horizontal: false, vertical: true)
      comparabilityRule(
        symbol: "equal.circle",
        title: String(localized: "Same unit, same revision, same convention"),
        detail: String(localized: "Then numbers mean the same thing and progress is real."))
      comparabilityRule(
        symbol: "pencil",
        title: String(localized: "Renaming does not change identity"),
        detail: String(localized: "The unit keeps its loads; only the label changes."))
      comparabilityRule(
        symbol: "arrow.triangle.2.circlepath",
        title: String(localized: "Changing unit, step, bar or stack starts a new revision"),
        detail: String(localized: "Loads recorded under the old revision stay separate."))
      comparabilityRule(
        symbol: "checkmark.seal",
        title: String(localized: "Confirming does not start a new revision"),
        detail: String(localized: "It confirms what the numbers already meant."))
      ForEach(nameCollisions) { collision in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.plateGold)
          Text(collisionExplanation(collision))
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .card()
  }

  private func collisionExplanation(_ collision: NameCollision) -> String {
    String(
      localized: "\(collision.instances.count) units named “\(collision.label)” at \(collision.location) are separate equipment. Their loads are not comparable with each other.")
  }

  private func comparabilityRule(symbol: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        Text(detail).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var locationFilterCard: some View {
    HStack(spacing: 10) {
      Text("Showing").forgeBody()
      Spacer(minLength: 8)
      Menu {
        Button { setFilter(nil) } label: {
          Label(
            String(localized: "All locations"),
            systemImage: filterGymID == nil ? "checkmark" : "circle")
        }
        ForEach(gymProfiles) { gym in
          Button { setFilter(gym.id) } label: {
            Label(gym.name, systemImage: filterGymID == gym.id ? "checkmark" : "circle")
          }
        }
      } label: {
        HStack(spacing: 4) {
          Text(filterGymID.map { gymName($0) } ?? String(localized: "All locations"))
            .forgeBodyStrong()
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44, alignment: .trailing)
      }
      .accessibilityLabel(Text("Filter by location"))
    }
    .card(padding: 16)
  }

  private func setFilter(_ id: String?) {
    withAnimation(.easeOut(duration: 0.15)) { filterGymID = id }
  }

  @ViewBuilder
  private var equipmentSections: some View {
    ForEach(kindGroups) { group in
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(kindLabel(group.kind)).forgeSection()
          Spacer(minLength: 8)
          Text("\(group.instances.count)").forgeCaption()
        }
        ForEach(Array(group.instances.enumerated()), id: \.element.id) { index, instance in
          equipmentRow(instance)
          if index < group.instances.count - 1 { Divider().overlay(Theme.ring) }
        }
      }
      .card()
    }
  }

  private func equipmentRow(_ instance: EquipmentInstance) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button {
        editorTarget = EditorTarget(instance: instance)
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(instance.name)
              .forgeBodyStrong()
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            statusPill(instance.loadModel.normalizationStatus)
          }
          Text("\(kindLabel(instance.kind)) · \(locationLabel(instance.gymProfileID))")
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
          Text(loadSummary(instance.loadModel))
            .forgeLabel()
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(accessibilityDescription(instance)))
      .accessibilityHint(Text("Opens the load settings for this equipment."))

      optionsMenu(instance)
    }
  }

  private func statusPill(_ status: LoadNormalizationStatus) -> some View {
    HStack(spacing: 4) {
      Image(systemName: status == .verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 10, weight: .bold))
      Text(statusLabel(status))
        .font(.forge(11, .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(statusColor(status))
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Capsule().fill(statusColor(status).opacity(0.14)))
    .accessibilityLabel(
      status == .verified
        ? Text("Load meaning verified") : Text("Load meaning needs review"))
  }

  private func optionsMenu(_ instance: EquipmentInstance) -> some View {
    Menu {
      Button {
        editorTarget = EditorTarget(instance: instance)
      } label: {
        Label("Edit", systemImage: "pencil")
      }
      if instance.isRetired {
        Button {
          restore(instance)
        } label: {
          Label("Restore", systemImage: "arrow.uturn.backward")
        }
      } else {
        Button(role: .destructive) {
          retiredToConfirm = instance
        } label: {
          Label("Retire", systemImage: "archivebox")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
    }
    .accessibilityLabel(Text("Options for \(instance.name)"))
  }

  private var retiredSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Retired").forgeSection()
        Spacer(minLength: 8)
        Text("\(retiredInstances.count)").forgeCaption()
      }
      Text("Loads already recorded against retired equipment stay readable. Restore an item if it comes back.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      ForEach(Array(retiredInstances.enumerated()), id: \.element.id) { index, instance in
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            Text(instance.name).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
            Text("\(kindLabel(instance.kind)) · \(locationLabel(instance.gymProfileID))")
              .forgeCaption()
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Button {
            restore(instance)
          } label: {
            Text("Restore")
              .forge(13, .semibold)
              .foregroundStyle(Theme.accent)
              .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Restore \(instance.name)"))
        }
        .opacity(0.72)
        if index < retiredInstances.count - 1 { Divider().overlay(Theme.ring) }
      }
    }
    .card()
  }

  private var addButton: some View {
    Button {
      editorTarget = EditorTarget(instance: nil)
    } label: {
      Label("Add equipment", systemImage: "plus")
    }
    .buttonStyle(PillSecondaryButtonStyle())
    .accessibilityLabel(Text("Add equipment"))
    .accessibilityHint(Text("Records another unit and what its numbers mean."))
  }

  private var saveBar: some View {
    VStack(spacing: 6) {
      if hasUnsavedChanges {
        Text("Unsaved changes").forgeCaption()
      } else if hasSaved {
        HStack(spacing: 5) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.positive)
          Text("Saved to this device").forgeCaption()
        }
      }
      Button {
        save()
      } label: {
        Text("Save passport")
      }
      .buttonStyle(PillButtonStyle())
      .disabled(!hasUnsavedChanges)
      .opacity(hasUnsavedChanges ? 1 : 0.5)
      .accessibilityHint(
        hasUnsavedChanges
          ? Text("Saves these equipment changes on this device.")
          : Text("No changes to save."))
    }
    .padding(.horizontal, Theme.barMargin)
    .padding(.vertical, 10)
    .background(Theme.page.opacity(0.92))
    .background(.ultraThinMaterial)
  }

  // MARK: Text

  private func loadSummary(_ model: LoadModel) -> String {
    var parts: [String] = [conventionLabel(model.convention)]
    if model.unit != .unspecified { parts.append(model.unit.symbol) }
    if model.increment > 0, model.unit != .unspecified {
      parts.append(String(localized: "\(quantity(model.increment)) \(model.unit.symbol) steps"))
    }
    if let bar = model.barWeight, model.includesBar || model.convention == .platesOnly {
      let symbol = model.unit == .unspecified ? "" : " \(model.unit.symbol)"
      parts.append(String(localized: "bar \(quantity(bar))\(symbol)"))
    }
    if let base = model.stackBaseWeight, let step = model.stackIncrement {
      let symbol = model.unit == .unspecified ? "" : " \(model.unit.symbol)"
      parts.append(
        String(localized: "stack from \(quantity(base))\(symbol), \(quantity(step))\(symbol) per step"))
    }
    return parts.joined(separator: " · ")
  }

  private func accessibilityDescription(_ instance: EquipmentInstance) -> String {
    let status = statusLabel(instance.loadModel.normalizationStatus)
    return String(
      localized: "\(instance.name), \(kindLabel(instance.kind)), \(locationLabel(instance.gymProfileID)), \(status). \(loadSummary(instance.loadModel))")
  }

  // MARK: Edits (in memory until Save)

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let profile = profiles.first else { return }
    passport = profile.equipmentPassport
    savedPassport = passport
    filterGymID = profile.trainingConstraints.activeGymProfile?.id
  }

  private func apply(_ instance: EquipmentInstance) {
    if let index = passport.instances.firstIndex(where: { $0.id == instance.id }) {
      passport.instances[index] = instance
    } else {
      passport.instances.append(instance)
    }
  }

  private func retire(_ instance: EquipmentInstance) {
    guard let index = passport.instances.firstIndex(where: { $0.id == instance.id }) else { return }
    passport.instances[index].isRetired = true
    passport.instances[index].updatedAt = .now
  }

  private func restore(_ instance: EquipmentInstance) {
    guard let index = passport.instances.firstIndex(where: { $0.id == instance.id }) else { return }
    passport.instances[index].isRetired = false
    passport.instances[index].updatedAt = .now
  }

  private func importLegacyEquipment() {
    passport.instances.append(contentsOf: importableInstances)
  }

  // MARK: Save

  private var retireConfirmation: Binding<Bool> {
    Binding(
      get: { retiredToConfirm != nil },
      set: { if !$0 { retiredToConfirm = nil } })
  }

  private func save() {
    guard let profile = profiles.first, hasUnsavedChanges else { return }
    let previous = savedPassport
    let next = passport
    let change = PassportChange(from: previous, to: next, gymNames: allGymNames)

    profile.equipmentPassport = next

    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "equipment-passport-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: "equipmentPassport",
          exerciseID: nil,
          muscle: nil,
          fromValue: Double(previous.instances.count),
          toValue: Double(next.instances.count),
          reasonCodes: [DecisionSignal.userOverride.code, "equipmentPassport"],
          evidence: change.evidence,
          humanSummary: change.humanSummary)))
    try? modelContext.save()

    savedPassport = next
    hasSaved = true
    Analytics.track(
      "equipment_passport_saved",
      [
        "added": "\(change.added.count)",
        "removed": "\(change.removed.count)",
        "retired": "\(change.retired.count)",
        "review": "\(change.stillNeedsReview)",
      ])
  }

  private struct EditorTarget: Identifiable {
    let instance: EquipmentInstance?
    var id: String { instance?.id ?? "new-equipment" }
  }
}

// MARK: - Change summary

/// A plain diff between the saved passport and the edited one, turned into evidence strings.
private struct PassportChange {
  struct RevisionNote: Identifiable {
    let id: String
    let name: String
    let from: Int
    let to: Int
  }

  let added: [EquipmentInstance]
  let removed: [EquipmentInstance]
  let retired: [EquipmentInstance]
  let restored: [EquipmentInstance]
  let revised: [RevisionNote]
  let stillNeedsReview: Int
  private let gymNames: [String: String]

  init(from old: EquipmentPassport, to new: EquipmentPassport, gymNames: [String: String]) {
    var oldByID: [String: EquipmentInstance] = [:]
    for instance in old.instances { oldByID[instance.id] = instance }
    var newIDs: Set<String> = []
    for instance in new.instances { newIDs.insert(instance.id) }

    self.gymNames = gymNames
    added = new.instances.filter { oldByID[$0.id] == nil }
    removed = old.instances.filter { !newIDs.contains($0.id) }
    retired = new.instances.filter { instance in
      guard let previous = oldByID[instance.id] else { return false }
      return !previous.isRetired && instance.isRetired
    }
    restored = new.instances.filter { instance in
      guard let previous = oldByID[instance.id] else { return false }
      return previous.isRetired && !instance.isRetired
    }
    revised = new.instances.compactMap { instance in
      guard let previous = oldByID[instance.id],
        previous.loadModel.revision != instance.loadModel.revision
      else { return nil }
      return RevisionNote(
        id: instance.id,
        name: instance.name,
        from: previous.loadModel.revision,
        to: instance.loadModel.revision)
    }
    stillNeedsReview = new.instances.filter {
      !$0.isRetired && $0.loadModel.normalizationStatus != .verified
    }.count
  }

  private func location(_ id: String?) -> String {
    guard let id else { return String(localized: "Travels with you") }
    return gymNames[id] ?? id
  }

  var evidence: [String] {
    var items: [String] = []
    for instance in added {
      items.append(String(localized: "Added \(instance.name) at \(location(instance.gymProfileID))"))
    }
    for instance in removed {
      items.append(String(localized: "Removed \(instance.name) at \(location(instance.gymProfileID))"))
    }
    for instance in retired {
      items.append(String(localized: "Retired \(instance.name) at \(location(instance.gymProfileID))"))
    }
    for instance in restored {
      items.append(String(localized: "Restored \(instance.name) at \(location(instance.gymProfileID))"))
    }
    for note in revised {
      items.append(
        String(localized: "New load model revision \(note.to) for \(note.name), was \(note.from)"))
    }
    if stillNeedsReview > 0 {
      items.append(
        String(localized: "\(stillNeedsReview) items still have no confirmed load meaning"))
    }
    if items.isEmpty { items.append(String(localized: "No item changes")) }
    return items
  }

  var humanSummary: String {
    var parts: [String] = []
    if !added.isEmpty { parts.append(String(localized: "\(added.count) added")) }
    if !removed.isEmpty { parts.append(String(localized: "\(removed.count) removed")) }
    if !retired.isEmpty { parts.append(String(localized: "\(retired.count) retired")) }
    if !restored.isEmpty { parts.append(String(localized: "\(restored.count) restored")) }
    if !revised.isEmpty {
      parts.append(String(localized: "\(revised.count) load model revisions"))
    }
    guard !parts.isEmpty else {
      return String(localized: "Equipment passport saved with no item changes.")
    }
    return String(localized: "Equipment passport saved: \(parts.joined(separator: ", ")).")
  }
}

// MARK: - Instance editor

/// Add or edit one physical unit. The screen is a sequence of plain questions:
/// what is it, where is it, what does its number mean, and what does it step by.
private struct EquipmentInstanceEditor: View {
  @Environment(\.dismiss) private var dismiss

  let gymProfiles: [GymProfileConfig]
  let existing: EquipmentInstance?
  let siblings: [EquipmentInstance]
  let activeGymProfileID: String
  let defaultUnit: LoadUnit
  let onSave: (EquipmentInstance) -> Void

  private enum Field: Hashable {
    case name, increment, bar, stackBase, stackIncrement
  }

  @FocusState private var focusedField: Field?
  @State private var name: String
  @State private var kind: EquipmentKind
  @State private var gymProfileID: String?
  @State private var convention: LoadingConvention
  @State private var unit: LoadUnit
  @State private var incrementText: String
  @State private var barText: String
  @State private var stackBaseText: String
  @State private var stackIncrementText: String

  init(
    gymProfiles: [GymProfileConfig],
    existing: EquipmentInstance?,
    siblings: [EquipmentInstance],
    activeGymProfileID: String,
    defaultUnit: LoadUnit,
    onSave: @escaping (EquipmentInstance) -> Void
  ) {
    self.gymProfiles = gymProfiles
    self.existing = existing
    self.siblings = siblings
    self.activeGymProfileID = activeGymProfileID
    self.defaultUnit = defaultUnit
    self.onSave = onSave

    let model = existing?.loadModel
    let resolvedUnit = model?.unit ?? defaultUnit
    let resolvedKind = existing?.kind ?? .barbell
    _name = State(initialValue: existing?.name ?? "")
    _kind = State(initialValue: resolvedKind)
    _gymProfileID = State(
      initialValue: existing?.gymProfileID ?? (resolvedKind.isGymIndependent ? nil : activeGymProfileID))
    _convention = State(initialValue: model?.convention ?? .totalIncludingBar)
    _unit = State(initialValue: resolvedUnit)
    _incrementText = State(initialValue: Self.text(model?.increment))
    _barText = State(initialValue: Self.text(model?.barWeight))
    _stackBaseText = State(initialValue: Self.text(model?.stackBaseWeight))
    _stackIncrementText = State(initialValue: Self.text(model?.stackIncrement))
  }

  /// `nil` and `0` both read as "not set", so an empty field never claims a value the lifter
  /// never typed.
  private static func text(_ value: Double?) -> String {
    guard let value, value > 0 else { return "" }
    return quantity(value)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          identityCard
          loadMeaningCard
          optionalValuesCard
          revisionCard
          if !comparabilityNotes.isEmpty { comparabilityCheckCard }
          if !validationErrors.isEmpty { validationCard }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 32)
      }
      .background(Theme.page)
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(Text(editorTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focusedField = nil }
        }
      }
      .safeAreaInset(edge: .bottom) { editorSaveBar }
      .onChange(of: kind) { _, newValue in applyKindDefaults(newValue) }
    }
  }

  private var editorTitle: String {
    existing == nil ? String(localized: "Add equipment") : String(localized: "Edit equipment")
  }

  // MARK: Cards

  private var identityCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Equipment").forgeSection()

      VStack(alignment: .leading, spacing: 4) {
        Text("Name").forgeLabel()
        TextField("e.g. Leg press, 2nd floor", text: $name)
          .font(.forge(15, .medium))
          .foregroundStyle(Theme.text)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .focused($focusedField, equals: .name)
          .padding(.horizontal, 12)
          .padding(.vertical, 12)
          .innerSurface(padding: 0)
          .accessibilityLabel(Text("Equipment name"))
        if let nameError {
          Text(nameError).forgeCaption().foregroundStyle(Theme.negative)
        } else {
          Text("Use the name printed on the machine, plus anything that tells two of them apart.")
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider().overlay(Theme.ring)
      pickerRow(
        title: String(localized: "Kind"),
        selection: $kind,
        options: equipmentKindOrder,
        label: { kindLabel($0) })

      Divider().overlay(Theme.ring)
      HStack(spacing: 10) {
        Text("Location").forgeBody()
        Spacer(minLength: 8)
        Picker("Location", selection: $gymProfileID) {
          ForEach(gymProfiles) { gym in
            Text(gym.name).tag(Optional(gym.id))
          }
          Text("Travels with you").tag(String?.none)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Theme.accent)
        .accessibilityLabel(Text("Gym location"))
      }
      Text(locationHint)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .card()
  }

  private var locationHint: String {
    if kind.isGymIndependent {
      return String(localized: "Bodyweight and bands read the same anywhere, so a location is optional.")
    }
    if kind.requiresExactInstance {
      return String(localized: "Machines are tied to one location. Loads from a similar machine elsewhere are never merged.")
    }
    return String(localized: "Barbells and dumbbell racks differ between gyms, so each location gets its own record.")
  }

  private var loadMeaningCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("What the number means").forgeSection()
      pickerRow(
        title: String(localized: "Loading convention"),
        selection: $convention,
        options: loadingConventionOrder,
        label: { conventionLabel($0) })
      Text(conventionExplanation(convention))
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)

      Divider().overlay(Theme.ring)
      HStack(spacing: 10) {
        Text("Unit").forgeBody()
        Spacer(minLength: 8)
        Picker("Unit", selection: $unit) {
          ForEach(LoadUnit.allCases, id: \.self) { value in
            Text(unitLabel(value)).tag(value)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Theme.accent)
        .accessibilityLabel(Text("Load unit"))
      }

      if showsIncrement {
        Divider().overlay(Theme.ring)
        numericRow(
          title: String(localized: "Smallest change"),
          unit: unit,
          text: $incrementText,
          placeholder: "2.5",
          field: .increment)
        if let incrementError {
          Text(incrementError).forgeCaption().foregroundStyle(Theme.negative)
        } else {
          Text("The smallest jump the equipment can actually make.")
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider().overlay(Theme.ring)
      HStack(alignment: .top, spacing: 8) {
        Image(
          systemName: resultingStatus == .verified
            ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(statusColor(resultingStatus))
        Text(statusExplanation)
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        Text("\(statusLabel(resultingStatus)). \(statusExplanation)"))
    }
    .card()
  }

  @ViewBuilder
  private var optionalValuesCard: some View {
    if showsBar || showsStack || identityNote != nil {
      VStack(alignment: .leading, spacing: 12) {
        Text("Optional details").forgeSection()
        if showsBar {
          numericRow(
            title: String(localized: "Bar weight"),
            unit: unit,
            text: $barText,
            placeholder: "20",
            field: .bar)
          if let barError {
            Text(barError).forgeCaption().foregroundStyle(Theme.negative)
          } else if convention == .platesOnly {
            Text("Optional. Without it the app cannot total a plates-only load.")
              .forgeCaption()
              .fixedSize(horizontal: false, vertical: true)
          } else {
            Text("The bar is counted as part of the number you record.")
              .forgeCaption()
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if showsBar && showsStack { Divider().overlay(Theme.ring) }
        if showsStack {
          numericRow(
            title: String(localized: "First stack step"),
            unit: unit,
            text: $stackBaseText,
            placeholder: "5",
            field: .stackBase)
          VStack(alignment: .leading, spacing: 8) {
            numericRow(
              title: String(localized: "Weight per step"),
              unit: unit,
              text: $stackIncrementText,
              placeholder: "5",
              field: .stackIncrement)
            if let stackError {
              Text(stackError).forgeCaption().foregroundStyle(Theme.negative)
            } else {
              Text("Used to read a stack value and to know the smallest real jump.")
                .forgeCaption()
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        if let identityNote {
          Text(identityNote)
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .card()
    }
  }

  private var revisionCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Load model").forgeSection()
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(revisionTitle)
          .forgeBodyStrong()
        Spacer(minLength: 8)
        if semanticsChanged {
          Text("Starts a new revision").forgeCaption().foregroundStyle(Theme.plateGold)
        }
      }
      Text(revisionExplanation)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .card()
    .accessibilityElement(children: .combine)
  }

  private var revisionTitle: String {
    existing == nil ? String(localized: "Revision 1") : String(localized: "Revision \(resolvedRevision)")
  }

  private var saveButtonTitle: String {
    existing == nil ? String(localized: "Add to passport") : String(localized: "Save changes")
  }

  private var revisionExplanation: String {
    if existing == nil {
      return String(localized: "A new unit starts at revision 1. Every load you record against it carries this revision.")
    }
    if semanticsChanged {
      return String(localized: "Unit, convention, step, bar or stack settings changed, so this becomes revision \(resolvedRevision). Loads recorded under revision \(existingRevision) stay separate and keep their original meaning.")
    }
    return String(localized: "Nothing that changes the meaning of a number changed, so this stays revision \(existingRevision). Renaming does not start a new revision.")
  }

  private struct ComparabilityNote: Identifiable {
    let id: String
    let text: String
    let comparable: Bool
  }

  /// Same-name siblings checked against the model that would be saved. The exercise dimension
  /// is held constant on purpose, so the verdict is purely about equipment identity, revision
  /// and convention.
  private var comparabilityNotes: [ComparabilityNote] {
    guard isValid else { return [] }
    let built = buildInstance()
    return sameNameSiblings.prefix(3).map { other in
      if let reason = built.incompatibility(with: other, exerciseID: "equipment-passport") {
        ComparabilityNote(
          id: other.id,
          text: String(
            localized: "\(other.name) at \(locationName(other.gymProfileID)): \(reason)."),
          comparable: false)
      } else {
        ComparabilityNote(
          id: other.id,
          text: String(localized: "\(other.name) at \(locationName(other.gymProfileID)): same unit and revision."),
          comparable: true)
      }
    }
  }

  private var comparabilityCheckCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Compared with the same name").forgeSection()
      Text("Matching names do not make two units interchangeable. Here is what the passport would say.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      ForEach(comparabilityNotes) { note in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: note.comparable ? "equal.circle" : "xmark.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(note.comparable ? Theme.positive : Theme.plateGold)
          Text(note.text).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .card()
  }

  private var validationCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.negative)
        Text("Fix before saving").forgeSection()
      }
      ForEach(validationErrors, id: \.self) { error in
        Text(error).forgeBody().fixedSize(horizontal: false, vertical: true)
      }
    }
    .card()
    .accessibilityElement(children: .combine)
  }

  private var editorSaveBar: some View {
    VStack(spacing: 6) {
      Button {
        focusedField = nil
        onSave(buildInstance())
        dismiss()
      } label: {
        Text(saveButtonTitle)
      }
      .buttonStyle(PillButtonStyle())
      .disabled(!isValid)
      .opacity(isValid ? 1 : 0.5)
      .accessibilityHint(
        isValid
          ? Text("Keeps this item in the passport. Nothing is written to this device until you save the passport.")
          : Text("Fix the highlighted problems first."))
    }
    .padding(.horizontal, Theme.barMargin)
    .padding(.vertical, 10)
    .background(Theme.page.opacity(0.92))
    .background(.ultraThinMaterial)
  }

  // MARK: Rows

  private func pickerRow<T: Hashable>(
    title: String,
    selection: Binding<T>,
    options: [T],
    label: @escaping (T) -> String
  ) -> some View {
    HStack(spacing: 10) {
      Text(title).forgeBody()
      Spacer(minLength: 8)
      Picker(title, selection: selection) {
        ForEach(options, id: \.self) { option in
          Text(label(option)).tag(option)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(Theme.accent)
      .accessibilityLabel(Text(title))
    }
  }

  private func numericRow(
    title: String,
    unit: LoadUnit,
    text: Binding<String>,
    placeholder: String,
    field: Field
  ) -> some View {
    HStack(spacing: 10) {
      Text(title).forgeBody().fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      TextField(placeholder, text: text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(.forge(15, .medium).monospacedDigit())
        .foregroundStyle(Theme.text)
        .frame(minWidth: 72, alignment: .trailing)
        .focused($focusedField, equals: field)
        .accessibilityLabel(Text(title))
      if unit != .unspecified {
        Text(unit.symbol).forgeLabel()
      }
    }
  }

  // MARK: Derived state

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var existingRevision: Int { existing?.loadModel.revision ?? 1 }

  private var showsIncrement: Bool {
    convention != .notApplicable && convention != .unknown && convention != .combined
  }

  private var showsBar: Bool {
    kind == .barbell || convention == .totalIncludingBar || convention == .platesOnly
  }

  private var showsStack: Bool {
    kind == .machine || kind == .cable || kind == .plateLoaded || convention == .combined
  }

  /// Why the load meaning can or cannot be confirmed. Shown verbatim next to the status pill.
  private var resultingStatus: LoadNormalizationStatus {
    if convention == .unknown { return .ambiguous }
    if unit == .unspecified && convention != .notApplicable { return .ambiguous }
    if showsIncrement && (parsed(incrementText) ?? 0) <= 0 { return .ambiguous }
    if convention == .combined && (parsed(stackIncrementText) ?? 0) <= 0 { return .ambiguous }
    return .verified
  }

  private var statusExplanation: String {
    if convention == .unknown {
      return String(localized: "Saving now keeps this as Needs review: we still would not know what the number counts.")
    }
    if unit == .unspecified && convention != .notApplicable {
      return String(localized: "Saving now keeps this as Needs review: without a unit, numbers cannot be converted or compared.")
    }
    if showsIncrement && (parsed(incrementText) ?? 0) <= 0 {
      return String(localized: "Saving now keeps this as Needs review: the smallest change is missing.")
    }
    if convention == .combined && (parsed(stackIncrementText) ?? 0) <= 0 {
      return String(localized: "Saving now keeps this as Needs review: the weight per stack step is missing.")
    }
    return String(localized: "Verified: the unit, convention and step describe what a number on this unit means.")
  }

  private var identityNote: String? {
    guard let collision = sameNameCollision else { return nil }
    return String(
      localized: "There is already a “\(collision.name)” at \(locationName(collision.gymProfileID)). Saving adds a separate unit — loads recorded on the two are never merged.")
  }

  private var sameNameSiblings: [EquipmentInstance] {
    let key = normalizeName(trimmedName)
    guard !key.isEmpty else { return [] }
    return siblings.filter { $0.id != existing?.id && normalizeName($0.name) == key }
      .sorted { $0.id < $1.id }
  }

  private var sameNameCollision: EquipmentInstance? {
    let key = normalizeName(trimmedName)
    guard !key.isEmpty else { return nil }
    return siblings.first {
      $0.id != existing?.id && $0.gymProfileID == gymProfileID && normalizeName($0.name) == key
    }
  }

  private func locationName(_ id: String?) -> String {
    guard let id else { return String(localized: "Travels with you") }
    return gymProfiles.first { $0.id == id }?.name ?? id
  }

  private func parsed(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return Double(trimmed.replacingOccurrences(of: ",", with: "."))
  }

  // MARK: Validation

  private var nameError: String? {
    if trimmedName.isEmpty { return String(localized: "Enter a name for this equipment.") }
    if trimmedName.count > 60 { return String(localized: "Keep the name under 60 characters.") }
    return nil
  }

  private var incrementError: String? {
    guard showsIncrement else { return nil }
    guard let value = parsed(incrementText) else {
      return String(localized: "Enter the smallest change as a number.")
    }
    return value > 0 ? nil : String(localized: "The smallest change must be greater than zero.")
  }

  private var barError: String? {
    guard convention == .totalIncludingBar else { return nil }
    guard let value = parsed(barText) else {
      return String(localized: "The number includes the bar, so enter the bar weight.")
    }
    return value > 0 ? nil : String(localized: "Bar weight must be greater than zero.")
  }

  private var stackError: String? {
    guard convention == .combined else { return nil }
    guard let base = parsed(stackBaseText) else {
      return String(localized: "Enter the weight of the first stack step.")
    }
    guard base >= 0 else { return String(localized: "The first stack step cannot be negative.") }
    guard let step = parsed(stackIncrementText) else {
      return String(localized: "Enter the weight added per stack step.")
    }
    return step > 0 ? nil : String(localized: "Weight per step must be greater than zero.")
  }

  private var validationErrors: [String] {
    [nameError, incrementError, barError, stackError].compactMap { $0 }
  }

  private var isValid: Bool { validationErrors.isEmpty }

  // MARK: Resulting model

  /// Derived rather than asked: the domain follows from the convention and the kind, so the
  /// lifter never has to answer an engineering question.
  private var resultingDomain: LoadDomain {
    if convention == .assistanceDisplayed { return .assistance }
    if kind == .bodyweight && convention == .notApplicable { return .bodyweight }
    if convention == .combined && (kind == .machine || kind == .cable || kind == .plateLoaded) {
      return .machineScale
    }
    return .externalMass
  }

  /// Hidden fields keep the value already stored, so opening an imported item and saving it
  /// unchanged is never a silent semantics change.
  private var resultingIncrement: Double {
    if showsIncrement { return parsed(incrementText) ?? 0 }
    if convention == .combined { return parsed(stackIncrementText) ?? 0 }
    if convention == .notApplicable { return existing?.loadModel.increment ?? 0 }
    return existing?.loadModel.increment ?? 0
  }

  private var resultingBarWeight: Double? {
    showsBar ? parsed(barText) : nil
  }

  private var resultingStackBase: Double? {
    showsStack ? parsed(stackBaseText) : nil
  }

  private var resultingStackIncrement: Double? {
    showsStack ? parsed(stackIncrementText) : nil
  }

  private var semanticsChanged: Bool {
    guard let model = existing?.loadModel else { return false }
    return model.domain != resultingDomain
      || model.convention != convention
      || model.unit != unit
      || model.increment != resultingIncrement
      || model.barWeight != resultingBarWeight
      || model.stackBaseWeight != resultingStackBase
      || model.stackIncrement != resultingStackIncrement
  }

  private var resolvedRevision: Int {
    existing == nil ? 1 : (semanticsChanged ? existingRevision + 1 : existingRevision)
  }

  private func uniqueInstanceID() -> String {
    let base = EquipmentInstance.stableID(name: trimmedName, gymProfileID: gymProfileID)
    let taken = Set(siblings.map(\.id))
    guard taken.contains(base) else { return base }
    var index = 2
    while taken.contains("\(base)-\(index)") { index += 1 }
    return "\(base)-\(index)"
  }

  private func buildInstance() -> EquipmentInstance {
    let now = Date.now
    let id = existing?.id ?? uniqueInstanceID()
    let model = LoadModel(
      id: existing?.loadModel.id ?? "\(id).model",
      revision: resolvedRevision,
      domain: resultingDomain,
      convention: convention,
      unit: unit,
      increment: resultingIncrement,
      barWeight: resultingBarWeight,
      stackBaseWeight: resultingStackBase,
      stackIncrement: resultingStackIncrement,
      normalizationStatus: resultingStatus,
      createdAt: existing?.loadModel.createdAt ?? now,
      updatedAt: now)
    return EquipmentInstance(
      id: id,
      name: trimmedName,
      kind: kind,
      gymProfileID: gymProfileID,
      loadModel: model,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      isRetired: existing?.isRetired ?? false)
  }

  // MARK: Kind defaults

  private var usesPounds: Bool { unit == .pounds }

  private func applyKindDefaults(_ kind: EquipmentKind) {
    let defaults: (convention: LoadingConvention, increment: String, stackBase: String, stackIncrement: String)
    switch kind {
    case .barbell:
      defaults = (.totalIncludingBar, usesPounds ? "5" : "2.5", "", "")
      if barText.isEmpty { barText = usesPounds ? "45" : "20" }
    case .dumbbell:
      defaults = (.perHand, usesPounds ? "5" : "2", "", "")
    case .machine, .cable, .plateLoaded:
      defaults = (.combined, "", "5", usesPounds ? "10" : "5")
    case .bodyweight, .bands:
      defaults = (.notApplicable, "", "", "")
    case .unknown:
      defaults = (.unknown, "", "", "")
    }
    convention = defaults.convention
    incrementText = defaults.increment
    if !defaults.stackBase.isEmpty { stackBaseText = defaults.stackBase }
    if !defaults.stackIncrement.isEmpty { stackIncrementText = defaults.stackIncrement }
    if kind == .unknown {
      unit = .unspecified
      barText = ""
      stackBaseText = ""
      stackIncrementText = ""
    }
  }
}
