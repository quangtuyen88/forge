import SwiftUI
import ForgeCore

/// "Your lifts" collection: the collector's shelf of every logged lift,
/// plus locked silhouettes for lifts that are planned but not tried yet.
struct LiftCollectionView: View {
  let data: ProgressData
  let usesLb: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if data.lifts.isEmpty && data.plannedNotLogged.isEmpty {
          VStack(spacing: 12) {
            Illustration(name: "art-empty-progress", height: 140)
            Text("Log your first workout to start your collection.").forgeLabel()
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 48)
        } else {
          countCard
          ForEach(BodyArea.allCases) { area in
            let planned = data.plannedNotLogged.filter { BodyArea($0.primary) == area }
            if !data.lifts(in: area).isEmpty || !planned.isEmpty {
              shelf(area, planned: planned)
            }
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationTitle("Your lifts")
  }

  private var plannedFraction: Double {
    guard data.plannedCount > 0 else { return 0 }
    return Double(data.plannedCount - data.plannedNotLogged.count) / Double(data.plannedCount)
  }

  private var countCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Lifts logged").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("\(data.lifts.count)").forge(56, .bold).foregroundStyle(Theme.accent).monospacedDigit()
          Text("lifts").forge(20, .semibold).foregroundStyle(Theme.textSecondary)
        }
        if !data.plannedNotLogged.isEmpty {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Theme.track)
              Capsule().fill(Theme.accent).frame(width: geo.size.width * plannedFraction)
            }
          }
          .frame(height: 10)
          Label(
            "\(data.plannedNotLogged.count) lifts in your plan not tried yet",
            systemImage: "lock.fill"
          )
          .forgeLabel()
        }
      }
    }
  }

  private func shelf(_ area: BodyArea, planned: [Exercise]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(area.title).forge(17, .semibold).foregroundStyle(Theme.text)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(data.lifts(in: area)) { lift in
            NavigationLink {
              LiftDetailView(exercise: lift.exercise, data: data, usesLb: usesLb)
            } label: {
              VStack(spacing: 6) {
                LiftToken(exercise: lift.exercise, size: 68, record: lift.freshRecord, onSky: true)
                Text(lift.exercise.localizedName)
                  .forge(13, .regular)
                  .foregroundStyle(Theme.text)
                  .lineLimit(2, reservesSpace: true)
                  .multilineTextAlignment(.center)
                  .frame(width: 84)
              }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(
              lift.freshRecord
                ? String(localized: "\(lift.exercise.localizedName), recent record", bundle: L10n.bundle)
                : lift.exercise.localizedName)
            .accessibilityIdentifier("progress.lift.\(lift.exercise.id)")
          }
          ForEach(planned) { exercise in
            VStack(spacing: 6) {
              LockedToken(size: 68)
              Text("???").forge(13, .semibold).foregroundStyle(Theme.text)
              Text("In your plan").forge(13, .regular).foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 84)
            .accessibilityLabel("A lift in your plan you have not tried yet")
          }
        }
        .padding(.horizontal, Theme.margin)
      }
      .padding(.horizontal, -Theme.margin)
    }
  }
}
