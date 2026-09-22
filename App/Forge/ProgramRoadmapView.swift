import ForgeCore
import SwiftData
import SwiftUI

struct ProgramRoadmapView: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @State private var expandedWeek: Int?

  private var profile: UserProfile? { profiles.first }
  private var currentWeek: Int { profile?.currentWeek(sessions: sessions) ?? 1 }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        overviewCard
        planToolsCard
        if let profile {
          ForEach(1...Mesocycle.weeks, id: \.self) { week in
            weekCard(week, profile: profile)
          }
        }
        explanationCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Program roadmap")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    .onAppear { expandedWeek = currentWeek }
  }

  private var overviewCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Your 6-week block").forgeTitle()
          Text("Volume builds for five weeks, then drops for recovery.").forgeLabel()
        }
        Spacer()
        MetricValue(
          value: "\(currentWeek)", unit: "/ \(Mesocycle.weeks)", size: 30, color: Theme.metricSets)
      }
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule().fill(Theme.metricSets)
            .frame(
              width: geometry.size.width * min(1, Double(currentWeek) / Double(Mesocycle.weeks)))
        }
      }
      .frame(height: 10)
    }
    .card()
  }

  private func weekCard(_ week: Int, profile: UserProfile) -> some View {
    let plan = Program.week(week, profile: profile.profileInput)
    let totalSets = plan.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
    let isCurrent = week == currentWeek
    let isDeload = week == Mesocycle.deloadWeek
    let expanded = expandedWeek == week
    return VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation(.snappy) { expandedWeek = expanded ? nil : week }
      } label: {
        HStack(spacing: 12) {
          ZStack {
            Circle().fill(
              (isDeload ? Theme.metricTime : Theme.metricSets).opacity(isCurrent ? 0.2 : 0.1))
            Text("\(week)").forgeBodyStrong().monospacedDigit()
              .foregroundStyle(isDeload ? Theme.metricTime : Theme.metricSets)
          }
          .frame(width: 40, height: 40)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(isDeload ? "Deload week" : "Week \(week)").forgeBodyStrong()
              if isCurrent {
                Text("CURRENT").forge(9, .bold, tracking: 0.7)
                  .foregroundStyle(Theme.onAccent)
                  .padding(.horizontal, 7).padding(.vertical, 3)
                  .background(Capsule().fill(Theme.accent))
              }
            }
            Text(
              "\(plan.count) workouts · \(totalSets) working sets\(week > currentWeek ? " · planned · may adapt" : "")"
            ).forgeCaption()
              .monospacedDigit()
          }
          Spacer()
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      if expanded {
        Divider().overlay(Theme.ring)
        // Positional: `Program.split` legitimately repeats day names within a week, so the
        // name is not a unique id here.
        ForEach(Array(plan.enumerated()), id: \.offset) { _, day in
          NavigationLink {
            SessionMusclePreviewView(day: day, showsDoneButton: false)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "figure.strengthtraining.traditional")
                .foregroundStyle(isDeload ? Theme.metricTime : Theme.metricSets)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(localizedDayName(day.name)).forgeBodyStrong()
                Text(daySummary(day)).forgeCaption()
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
          }
          .buttonStyle(RowPressStyle())
        }
      }
    }
    .card()
  }

  /// Routes from the roadmap into the planning features that act on this block. Each one is
  /// pushed, so the roadmap stays in the back stack and the week is never more than a tap away.
  private var planToolsCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Plan tools").forgeSection().padding(.bottom, 10)
      planToolLink(
        symbol: "calendar.day.timeline.left",
        title: "Week designer",
        subtitle: "Lay out this week and record what actually happened",
        color: Theme.metricTime
      ) { WeekDesignerView() }
      Divider().overlay(Theme.ring)
      planToolLink(
        symbol: "target",
        title: "Goal roadmap",
        subtitle: "One goal, judged on the evidence it has",
        color: Theme.metricSets
      ) { GoalRoadmapView() }
      Divider().overlay(Theme.ring)
      planToolLink(
        symbol: "square.and.arrow.down.on.square",
        title: "Import or share program",
        subtitle: "Review an imported program, share a redacted copy",
        color: Theme.metricLoad
      ) { ProgramImportAnalysisView() }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func planToolLink<Destination: View>(
    symbol: String,
    title: String,
    subtitle: String,
    color: Color,
    @ViewBuilder destination: () -> Destination
  ) -> some View {
    NavigationLink {
      destination()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(color)
          .frame(width: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).forgeBodyStrong()
          Text(subtitle).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle)
  }

  private var explanationCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("How the block adapts").forgeSection()
      explanationRow(
        "arrow.up.right", "Build",
        "Weeks 1–5 add productive volume when recovery and performance allow.", Theme.metricSets)
      explanationRow(
        "arrow.down.right", "Deload",
        "Week 6 cuts working sets and caps effort so fatigue can fall.", Theme.metricTime)
      explanationRow(
        "list.bullet.clipboard", "Proof",
        "Every applied adjustment is recorded in the decision ledger with its source values.",
        Theme.metricLoad)
      if let latest = decisions.first {
        Divider().overlay(Theme.ring)
        Text("Latest · \(latest.humanSummary)").forgeCaption()
      }
    }
    .card()
  }

  private func explanationRow(_ symbol: String, _ title: String, _ text: String, _ color: Color)
    -> some View
  {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(text).forgeCaption()
      }
    }
  }

  private func daySummary(_ day: PlannedDay) -> String {
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    let names = SessionMusclePreviewView.breakdown(day).prefix(2).map { $0.muscle.a11yName }
    return "\(day.exercises.count) exercises · \(sets) sets · \(names.joined(separator: " + "))"
  }
}

struct SessionMusclePreviewView: View {
  @Environment(\.dismiss) private var dismiss
  let day: PlannedDay
  var showsDoneButton = true

  struct Emphasis: Identifiable {
    let muscle: Muscle
    let sets: Int
    let fraction: Double
    var id: Muscle { muscle }
  }

  static func breakdown(_ day: PlannedDay) -> [Emphasis] {
    var counts: [Muscle: Int] = [:]
    for planned in day.exercises { counts[planned.exercise.primary, default: 0] += planned.sets }
    let total = max(1, counts.values.reduce(0, +))
    return counts.map {
      Emphasis(muscle: $0.key, sets: $0.value, fraction: Double($0.value) / Double(total))
    }
    .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.rawValue < $1.muscle.rawValue }
  }

  private var emphasis: [Emphasis] { Self.breakdown(day) }
  private var intensity: [Muscle: Double] {
    let peak = max(1, emphasis.map(\.sets).max() ?? 1)
    return Dictionary(
      uniqueKeysWithValues: emphasis.map { ($0.muscle, Double($0.sets) / Double(peak)) })
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 8) {
          Text(localizedDayName(day.name)).forgeTitle()
          Text("Planned set share, not a physiological activation score.").forgeCaption()
          MuscleMapView(intensity: intensity)
            .frame(height: 260)
            .frame(maxWidth: .infinity)
        }
        .card()
        VStack(spacing: 0) {
          ForEach(Array(emphasis.enumerated()), id: \.element.id) { index, item in
            HStack(spacing: 12) {
              Circle().fill(Theme.rampColor(item.fraction)).frame(width: 12, height: 12)
              Text(item.muscle.a11yName).forgeBodyStrong()
              Spacer()
              Text("\(item.sets) sets").forgeCaption().monospacedDigit()
              MetricValue(
                value: "\(Int((item.fraction * 100).rounded()))", unit: "%", size: 20,
                color: Theme.metricSets)
            }
            .padding(.vertical, 10)
            if index < emphasis.count - 1 { Divider().overlay(Theme.ring) }
          }
        }
        .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Muscle emphasis")
    .toolbar {
      if showsDoneButton {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}
