import ForgeCore
import SwiftUI

/// The weekly sets-per-muscle detail screen: the volume map and landmark rings that used to
/// live on the Progress overview, behind the "Details" link of "Muscles this week".
struct MuscleVolumeView: View {
  let weekSets: [Muscle: Double]
  let recoveryReduced: Bool

  var body: some View {
    ScrollView {
      volumeCard
        .padding(.horizontal, Theme.margin)
    }
    .background(Theme.page)
    .navigationTitle("Muscles this week")
  }

  private var volumeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("This week").forgeSection()
        Spacer()
        Text("sets per muscle").forgeCaption()
      }
      MuscleMapView(intensity: weekIntensity)
        .frame(height: 220)
        .frame(maxWidth: .infinity)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(Muscle.allCases.filter { VolumeLandmarks.base(for: $0) != nil }, id: \.self) {
          muscle in
          volumeCell(muscle)
        }
      }
    }
    .card()
  }

  private func volumeCell(_ muscle: Muscle) -> some View {
    let l = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: recoveryReduced)!
    return VStack(spacing: 4) {
      VolumeRingView(sets: weekSets[muscle] ?? 0, mev: l.floor(recoveryReduced: recoveryReduced), mrv: l.mrv)
      Text(muscle.a11yName).forgeCaption()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(muscle.a11yName), \(Int((weekSets[muscle] ?? 0).rounded())) sets this week, target \(l.mrv)"
    )
  }

  private var weekIntensity: [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for muscle in Muscle.allCases {
      guard let l = VolumeLandmarks.base(for: muscle) else { continue }
      result[muscle] = min((weekSets[muscle] ?? 0) / Double(l.mrv), 1)
    }
    return result
  }
}
