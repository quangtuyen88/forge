import SwiftUI
import SwiftData
import ForgeCore

/// "Your lifts" collection: the collector's shelf of every logged lift,
/// plus locked silhouettes for lifts that are planned but not tried yet.
struct LiftCollectionView: View {
  let data: ProgressData
  let usesLb: Bool
  @AppStorage("liftCollectionMode") private var mode = "shelf"
  @Query private var profiles: [UserProfile]
  private var crew = CrewStore.shared

  /// Crew falls back to the shelf when there is no crew, so the view is never blank.
  private var effectiveMode: String {
    mode == "crew" && crew.snapshot?.hasCrew != true ? "shelf" : mode
  }

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
          VStack(spacing: 10) {
            // The picker reads effectiveMode (a stored "crew" with no crew highlights "Shelf")
            // and writes the raw mode, so choosing a segment always fixes the stored value.
            Picker(
              "View",
              selection: Binding(get: { effectiveMode }, set: { mode = $0 })
            ) {
              Text("Shelf").tag("shelf")
              Text("Trends").tag("trends")
              if crew.snapshot?.hasCrew == true {
                Text("Crew").tag("crew")
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("lifts.mode")
            if effectiveMode == "crew", let snapshot = crew.snapshot {
              crewSummary(snapshot)
            }
          }
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
    .task {
      if crew.snapshot == nil { await crew.refresh(selfWeek: nil) }
    }
  }

  /// The one line under the picker in crew mode: the crew and how much of the shelf it shares.
  private func crewSummary(_ snapshot: CrewSnapshot) -> some View {
    let others = snapshot.others
    let shared = data.lifts.filter { snapshot.crewLiftIDs.contains($0.exercise.id) }.count
    return HStack(spacing: 8) {
      CrewAvatarStack(
        members: others.prefix(4).map { (initial: $0.initial, record: false) },
        extra: max(0, others.count - 4),
        size: 24,
        border: Theme.todayPage)
      Text("Your crew does \(shared) of your \(data.lifts.count) lifts")
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityIdentifier("lifts.crew.summary")
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
      Text(area.title).forgeSection().accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(data.lifts(in: area)) { lift in
            if effectiveMode == "trends" {
              liftLink(lift)
                .accessibilityValue(
                  TrendChangeText.label(
                    changeKg: data.trend(for: lift.exercise.id)?.changeKg(in: .all), isLb: isLb(lift)))
            } else if effectiveMode == "crew", let snapshot = crew.snapshot {
              liftLink(lift)
                .accessibilityValue(crewValue(for: lift, snapshot: snapshot))
            } else {
              liftLink(lift)
            }
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

  /// One logged lift on the shelf; trends mode adds its small line and change under the name.
  private func liftLink(_ lift: ProgressData.Lift) -> some View {
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
        if mode == "trends" {
          HStack(spacing: 4) {
            if let trend = data.trend(for: lift.exercise.id), trend.workouts.count >= 2 {
              LiftSparkline(
                valuesKg: trend.workouts.map(\.e1rmKg), endIsRecord: trend.latestIsRecord,
                lineWidth: 1.5, dotDiameter: 4, ringColor: .clear)
                .frame(width: 22, height: 12)
            }
            TrendChangeText(
              changeKg: data.trend(for: lift.exercise.id)?.changeKg(in: .all), isLb: isLb(lift), size: 13)
          }
          .accessibilityIdentifier("lifts.trend.\(lift.exercise.id)")
        } else if effectiveMode == "crew" {
          crewLine(for: lift)
        }
      }
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(
      lift.freshRecord
        ? String(localized: "\(lift.exercise.localizedName), recent record", bundle: L10n.bundle)
        : lift.exercise.localizedName)
    .accessibilityIdentifier("progress.lift.\(lift.exercise.id)")
  }

  /// Under the name in crew mode: who else trains this lift, or "Just you".
  @ViewBuilder private func crewLine(for lift: ProgressData.Lift) -> some View {
    if let snapshot = crew.snapshot {
      let lines = snapshot.lines(for: lift.exercise.id)
      Group {
        if lines.isEmpty {
          Text("Just you")
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
        } else {
          let shown = snapshot.others.filter { member in
            lines.contains { $0.userId == member.userId }
          }
          CrewAvatarStack(
            members: shown.prefix(3).map { member in
              (initial: member.initial,
               record: snapshot.records.contains {
                 $0.userId == member.userId && $0.exerciseId == lift.exercise.id
               })
            },
            extra: max(0, shown.count - 3),
            size: 22,
            border: Theme.todayPage)
        }
      }
      .accessibilityIdentifier("lifts.crew.\(lift.exercise.id)")
    }
  }

  /// "Linh, Kenji and Mai also do this lift" for the crew the row shows, or "Only you".
  private func crewValue(for lift: ProgressData.Lift, snapshot: CrewSnapshot) -> String {
    let lines = snapshot.lines(for: lift.exercise.id)
    let names = snapshot.others
      .filter { member in lines.contains { $0.userId == member.userId } }
      .prefix(3)
      .map(\.name)
    guard !names.isEmpty else { return String(localized: "Only you", bundle: L10n.bundle) }
    let list = Array(names).formatted(.list(type: .and).locale(L10n.locale))
    return String(localized: "\(list) also do this lift", bundle: L10n.bundle)
  }

  /// Per-exercise kg/lb override beats the profile-wide default.
  private func isLb(_ lift: ProgressData.Lift) -> Bool {
    profiles.first?.isLb(for: lift.exercise.id) ?? usesLb
  }
}
