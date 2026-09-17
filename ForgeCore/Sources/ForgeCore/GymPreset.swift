import Foundation

public enum GymPreset: String, CaseIterable, Codable, Sendable {
  case commercial, home, dumbbellsOnly, hotel, noMachines, bodyweight

  public var name: String {
    switch self {
    case .commercial: return String(localized: "Commercial gym", bundle: ForgeCoreResources.bundle)
    case .home: return String(localized: "Home", bundle: ForgeCoreResources.bundle)
    case .dumbbellsOnly: return String(localized: "Dumbbells only", bundle: ForgeCoreResources.bundle)
    case .hotel: return String(localized: "Hotel", bundle: ForgeCoreResources.bundle)
    case .noMachines: return String(localized: "No machines", bundle: ForgeCoreResources.bundle)
    case .bodyweight: return String(localized: "Bodyweight", bundle: ForgeCoreResources.bundle)
    }
  }

  public var detail: String {
    switch self {
    case .commercial: return String(localized: "Barbells, dumbbells, machines, cables, pull-up bar.", bundle: ForgeCoreResources.bundle)
    case .home: return String(localized: "Barbell, dumbbells, bands and bodyweight.", bundle: ForgeCoreResources.bundle)
    case .dumbbellsOnly: return String(localized: "Dumbbells and bodyweight.", bundle: ForgeCoreResources.bundle)
    case .hotel: return String(localized: "Dumbbells, machines and bodyweight.", bundle: ForgeCoreResources.bundle)
    case .noMachines: return String(localized: "Everything except machines.", bundle: ForgeCoreResources.bundle)
    case .bodyweight: return String(localized: "Bodyweight and bands.", bundle: ForgeCoreResources.bundle)
    }
  }

  public var equipment: Set<Equipment> {
    switch self {
    // Bands are rare on a commercial floor; bodyweight covers pull-ups and dips, which belong in a full gym.
    case .commercial: return [.barbell, .dumbbell, .machine, .cable, .bodyweight]
    case .home: return [.barbell, .dumbbell, .bands, .bodyweight]
    case .dumbbellsOnly: return [.dumbbell, .bodyweight]
    case .hotel: return [.dumbbell, .machine, .bodyweight]
    case .noMachines: return [.barbell, .dumbbell, .cable, .bodyweight, .bands]
    case .bodyweight: return [.bodyweight, .bands]
    }
  }

  public static func matching(_ equipment: Set<Equipment>) -> GymPreset? {
    GymPreset.allCases.first { $0.equipment == equipment }
  }
}
