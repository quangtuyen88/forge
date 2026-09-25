import SwiftData
import SwiftUI

struct BodyNutritionView: View {
  let usesLb: Bool
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query private var progressPhotos: [ProgressPhoto]

  private var latestWeight: String? {
    measurements.first(where: { ($0.weightKg ?? 0) > 0 })?.weightKg
      .map { UnitFormat.weight($0, usesLb: usesLb) }
  }

  private var bodyStatsSubtitle: String {
    latestWeight ?? String(localized: "No measurements yet", bundle: L10n.bundle)
  }

  private var photosSubtitle: String {
    progressPhotos.isEmpty
      ? String(localized: "Private progress photos", bundle: L10n.bundle)
      : String(
        localized: "\(progressPhotos.count) private photo\(L10n.pluralSuffix(progressPhotos.count))",
        bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: 0) {
          NavigationLink {
            MeasurementsView(usesLb: usesLb)
          } label: {
            ProgressListRow(
              symbol: "scalemass", tint: Theme.accent,
              title: String(localized: "Body stats", bundle: L10n.bundle),
              subtitle: bodyStatsSubtitle)
          }
          .buttonStyle(RowPressStyle())
          .accessibilityIdentifier("progress.bodyStats")
          Divider().padding(.leading, 58)
          NavigationLink {
            ProgressPhotosView()
          } label: {
            ProgressListRow(
              symbol: "camera.fill", tint: Theme.metricTime,
              title: String(localized: "Progress photos", bundle: L10n.bundle),
              subtitle: photosSubtitle)
          }
          .buttonStyle(RowPressStyle())
          .accessibilityIdentifier("progress.photos")
          Divider().padding(.leading, 58)
          NavigationLink {
            NutritionView()
          } label: {
            ProgressListRow(
              symbol: "fork.knife", tint: Theme.metricEnergy,
              title: String(localized: "Fuel", bundle: L10n.bundle),
              subtitle: String(
                localized: "Calories, macros and daily guidance", bundle: L10n.bundle))
          }
          .buttonStyle(RowPressStyle())
          .accessibilityIdentifier("progress.fuel")
        }
        .card(padding: 0)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Body & nutrition")
    .navigationBarTitleDisplayMode(.large)
  }
}
