import SwiftUI
import SwiftData
import ForgeCore

/// "Lift collection": the collector's shelf of every logged lift grouped by area,
/// plus locked silhouettes for lifts that are planned but not tried yet.
struct LiftCollectionView: View {
  let data: ProgressData
  let usesLb: Bool
  @Query private var profiles: [UserProfile]

  private var freshRecords: Set<String> { StrengthV3.freshRecordIDs(data) }

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
          ProgressLargeTitle(title: "Lift collection", art: "art-equipment")
          countCard
          ForEach(BodyArea.allCases) { area in
            if !data.lifts(in: area).isEmpty {
              shelf(area)
            }
          }
          if !data.plannedNotLogged.isEmpty {
            comingNext
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .progressTitleNavigation("Lift collection")
  }

  private var plannedFraction: Double {
    guard data.plannedCount > 0 else { return 0 }
    return Double(data.plannedCount - data.plannedNotLogged.count) / Double(data.plannedCount)
  }

  private var countCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 14) {
          Text("\(data.lifts.count)")
            .forge(56, .bold)
            .foregroundStyle(Theme.accent)
            .monospacedDigit()
          VStack(alignment: .leading, spacing: 1) {
            if data.plannedCount > 0 {
              Text(String(localized: "of \(data.plannedCount) lifts logged", bundle: L10n.bundle))
                .forge(19, .semibold)
                .foregroundStyle(Theme.text)
              Text("in your program").forge(15, .regular).foregroundStyle(Theme.textSecondary)
            } else {
              Text("lifts logged").forge(19, .semibold).foregroundStyle(Theme.text)
            }
          }
        }
        if data.plannedCount > 0 {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Theme.track)
              Capsule()
                .fill(.mark(Theme.gradBrand))
                .frame(width: geo.size.width * plannedFraction)
            }
          }
          .frame(height: 10)
          .accessibilityHidden(true)
        }
        if !data.plannedNotLogged.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "lock")
              .font(.system(size: 15, weight: .medium))
            Text(
              String(
                localized: "\(data.plannedNotLogged.count) in your plan, not logged yet",
                bundle: L10n.bundle)
            )
            .forge(15, .regular)
          }
          .foregroundStyle(Theme.textSecondary)
        }
        if !freshRecords.isEmpty {
          HStack(spacing: 8) {
            Circle().strokeBorder(Theme.recordRing, lineWidth: 2).frame(width: 14, height: 14)
            Text(
              String(
                localized: "\(freshRecords.count) set a record in the last 7 days",
                bundle: L10n.bundle)
            )
            .forge(15, .regular)
            .monospacedDigit()
          }
          .foregroundStyle(Theme.textSecondary)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func shelf(_ area: BodyArea) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(area.title).forgeSection().accessibilityAddTraits(.isHeader)
        Spacer()
        Text(String(localized: "\(data.lifts(in: area).count) lifts", bundle: L10n.bundle))
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      LazyVGrid(columns: gridColumns, spacing: 18) {
        ForEach(data.lifts(in: area)) { lift in
          liftLink(lift)
        }
      }
      .padding(.horizontal, -8)
    }
  }

  private var gridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
  }

  /// One logged lift on the shelf.
  private func liftLink(_ lift: ProgressData.Lift) -> some View {
    let trend = data.trend(for: lift.exercise.id)
    let latest = trend.map { Fmt.num(lbValue($0.latest.e1rmKg, id: lift.exercise.id).rounded()) }
    return NavigationLink {
      LiftDetailView(exercise: lift.exercise, data: data, usesLb: usesLb)
    } label: {
      VStack(spacing: 8) {
        LiftToken(exercise: lift.exercise, size: 64, record: freshRecords.contains(lift.exercise.id))
        Text(lift.exercise.localizedName)
          .forge(13, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.center)
          .frame(width: 84)
        if let latest {
          Text(verbatim: "\(latest) \(unit(for: lift.exercise.id))")
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(
      freshRecords.contains(lift.exercise.id)
        ? String(localized: "\(lift.exercise.localizedName), recent record", bundle: L10n.bundle)
        : lift.exercise.localizedName)
    .accessibilityIdentifier("progress.lift.\(lift.exercise.id)")
  }

  private var comingNext: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Coming next").forgeSection().accessibilityAddTraits(.isHeader)
        Spacer()
        Text(String(localized: "\(data.plannedNotLogged.count) lifts", bundle: L10n.bundle))
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      LazyVGrid(columns: gridColumns, spacing: 18) {
        ForEach(data.plannedNotLogged) { exercise in
          VStack(spacing: 8) {
            LockedLiftToken(exercise: exercise, size: 64)
            Text(exercise.localizedName)
              .forge(13, .semibold)
              .foregroundStyle(Theme.textSecondary)
              .lineLimit(2, reservesSpace: true)
              .multilineTextAlignment(.center)
              .frame(width: 84)
            Text(BodyArea(exercise.primary).shortTitle)
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            String(
              localized: "\(exercise.localizedName), in your plan, not logged yet",
              bundle: L10n.bundle))
          .accessibilityIdentifier("progress.lift.locked.\(exercise.id)")
        }
      }
      .padding(.horizontal, -8)
    }
  }

  /// Per-exercise kg/lb override beats the profile-wide default.
  private func lbValue(_ kg: Double, id: String) -> Double {
    (profiles.first?.isLb(for: id) ?? usesLb) ? Plates.kgToLb(kg) : kg
  }

  private func unit(for id: String) -> String {
    (profiles.first?.isLb(for: id) ?? usesLb) ? "lb" : "kg"
  }
}

/// Quiet silhouette of a planned lift: art dimmed on a row disc, small lock badge.
struct LockedLiftToken: View {
  let exercise: Exercise
  let size: CGFloat

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Circle().fill(Theme.innerSurface)
      ExerciseArtCircle(exercise: exercise, size: size)
        .saturation(0)
        .opacity(0.28)
      Circle()
        .fill(Theme.track)
        .frame(width: 23, height: 23)
        .overlay(Circle().strokeBorder(Theme.pageGrey, lineWidth: 2))
        .overlay(
          Image(systemName: "lock")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary))
        .offset(x: 3, y: 3)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
