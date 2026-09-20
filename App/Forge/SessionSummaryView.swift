import SwiftUI
import SwiftData
import ForgeCore

struct MuscleVolume: Identifiable {
  let muscle: Muscle
  let sets: Int
  var id: String { muscle.rawValue }
}

func muscleDisplayName(_ muscle: Muscle) -> String {
  // stable English keys for social payloads; use muscle.a11yName for on-screen copy
  switch muscle {
  case .chest: return "Chest"
  case .back: return "Back"
  case .quads: return "Quads"
  case .hamstrings: return "Hamstrings"
  case .glutes: return "Glutes"
  case .sideDelts: return "Side delts"
  case .rearDelts: return "Rear delts"
  case .frontDelts: return "Front delts"
  case .triceps: return "Triceps"
  case .biceps: return "Biceps"
  case .calves: return "Calves"
  case .abs: return "Abs"
  case .forearms: return "Forearms"
  }
}

/// The one set per exercise a card may show. Chosen from sets that were actually logged —
/// heaviest first, then most reps — and carrying whether effort was reported, so a missing
/// RPE stays missing instead of borrowing the target.
struct SessionTopSet: Identifiable, Equatable {
  let exerciseID: String
  let exerciseName: String
  let weightKg: Double
  let reps: Int
  let rpe: Double
  let effortReported: Bool
  var id: String { exerciseID }

  /// One entry per exercise, in the order the exercises were trained.
  static func best(in sets: [LoggedSet]) -> [SessionTopSet] {
    var best: [String: SessionTopSet] = [:]
    var order: [String] = []
    for set in sets {
      if best[set.exerciseID] == nil { order.append(set.exerciseID) }
      let candidate = SessionTopSet(
        exerciseID: set.exerciseID,
        exerciseName: ExerciseDB.find(set.exerciseID)?.localizedName ?? set.exerciseID,
        weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
        effortReported: set.effortReported)
      guard let current = best[set.exerciseID] else {
        best[set.exerciseID] = candidate
        continue
      }
      if candidate.weightKg > current.weightKg
        || (candidate.weightKg == current.weightKg && candidate.reps > current.reps) {
        best[set.exerciseID] = candidate
      }
    }
    return order.compactMap { best[$0] }
  }
}

struct SessionSummary {
  let date: Date
  let dayName: String
  let duration: TimeInterval
  let sets: Int
  var plannedSets = 0
  let exercises: Int
  let tonnageKg: Double
  let notes: String
  let muscles: [MuscleVolume]
  var verified = true
  /// Highlights a share card may draw from. Empty is a valid state: the composer then shows
  /// an empty state rather than inventing content.
  var topSets: [SessionTopSet] = []
}

struct SessionSummaryView: View {
  let summary: SessionSummary
  let prs: [PRRecord]
  let debrief: [DebriefLine]
  let usesLb: Bool
  var onDone: () -> Void
  @Query private var profiles: [UserProfile]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @State private var autoPosted = false
  /// Share Cards v2: the composer is a sheet over the summary, so Done stays reachable and
  /// nothing about sharing is on the path to finishing a workout.
  @State private var showShareCard = false
  @State private var shown = false
  @State private var showPRs = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The remembered Progress surface. The summary only ever reads it to hand the lifter the
  /// timeline of the session that was just saved; the Progress tab owns the switch itself.
  @AppStorage(JourneyPref.segmentKey) private var progressSegment = JourneyPref.segmentOverview

  private var coach: Coach { Coach.from(coachID) }

  private var tonnageNumber: String {
    Fmt.grouped(usesLb ? Plates.kgToLb(summary.tonnageKg) : summary.tonnageKg)
  }

  private var summaryItems: [MetricItem] {
    let live = shown || reduceMotion
    var items = [
      MetricItem(
        String(localized: "Duration", bundle: L10n.bundle),
        live ? Self.durationText(summary.duration) : "—", color: Theme.metricTime),
      MetricItem(summary.plannedSets > 0 ? String(localized: "Sets · of \(summary.plannedSets)", bundle: L10n.bundle) : String(localized: "Sets", bundle: L10n.bundle), live ? "\(summary.sets)" : "0", color: Theme.metricSets),
      MetricItem(String(localized: "Tonnage", bundle: L10n.bundle), live ? tonnageNumber : "0", unit: usesLb ? "lb" : "kg", color: Theme.metricLoad),
      MetricItem(String(localized: "Exercises", bundle: L10n.bundle), live ? "\(summary.exercises)" : "0"),
    ]
    if !prs.isEmpty { items.append(MetricItem(String(localized: "New PRs", bundle: L10n.bundle), live ? "\(prs.count)" : "0", color: Theme.metricSets)) }
    return items
  }

  /// The same rule History uses: a session under a minute is stated, never rounded into a
  /// contradictory "0 min" here and "1 min" there.
  static func durationText(_ duration: TimeInterval) -> String {
    let seconds = Int(duration)
    if seconds <= 0 { return String(localized: "—", bundle: L10n.bundle) }
    if seconds < 60 { return String(localized: "Under 1 min", bundle: L10n.bundle) }
    return String(localized: "\(seconds / 60) min", bundle: L10n.bundle)
  }

  private var coachLine: String {
    if !prs.isEmpty { return String(localized: "New PR on \(prs[0].exercise.localizedName). That's the adaptation we wanted.", bundle: L10n.bundle) }
    if 2 * summary.sets < summary.plannedSets {
      return String(localized: "Short one. \(summary.sets) of \(summary.plannedSets) sets logged.", bundle: L10n.bundle)
    }
    return String(localized: "Solid session. Recovery starts now.", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        hero
        VStack(alignment: .leading, spacing: 10) {
          Text("Workout details").forgeSection()
          MetricGrid(items: summaryItems)
          if !summary.verified {
            Text(String(localized: "Not counted for PRs, badges or Crew: sets came in too fast or a load jumped.", bundle: L10n.bundle))
              .forgeCaption()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: shown)
        musclesCard
        if !summary.notes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Notes").forgeSection()
            Text(summary.notes).forgeBody()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }
        DebriefCard(debrief: debrief, coachName: coach.name, hasPR: !prs.isEmpty)
        if showPRs {
          VStack(alignment: .leading, spacing: 12) {
            Text("New PRs").forgeSection()
            ForEach(prs) { pr in
              HStack(spacing: 12) {
                ZStack {
                  Circle().fill(Theme.positive.opacity(0.12))
                  Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                  Text(pr.exercise.localizedName).forgeBodyStrong()
                  Text("\(display(pr.e1rm, for: pr.exercise.id)) e1RM · was \(display(pr.previous ?? 0, for: pr.exercise.id))")
                    .forgeLabel()
                    .monospacedDigit()
                }
                Spacer()
                ShareLink(item: card(pr), preview: SharePreview("New PR — \(pr.exercise.localizedName)")) {
                  Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                }
              }
            }
          }
          .card()
          .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 10) {
        Button {
          showShareCard = true
        } label: {
          Label {
            Text(String(localized: "Share workout", bundle: L10n.bundle))
          } icon: {
            Image(systemName: "square.and.arrow.up")
          }
        }
        .buttonStyle(PillSecondaryButtonStyle())
        .accessibilityIdentifier("summary.shareCard")
        Button(action: viewInTimeline) {
          Label {
              Text(String(localized: "View in timeline", bundle: L10n.bundle))
            } icon: {
              Image(systemName: "chart.line.uptrend.xyaxis")
            }
          }
          .buttonStyle(PillSecondaryButtonStyle())
          .accessibilityIdentifier("summary.viewInTimeline")
          .accessibilityHint(
          String(
            localized:
              "Opens Progress on your timeline. The session you just saved stays one record.",
            bundle: L10n.bundle))
        Button("Done") { onDone() }
          .buttonStyle(PillButtonStyle())
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
    .presentationBackground(Theme.page)
    .sheet(isPresented: $showShareCard) {
      ShareCardComposer(source: shareSource) { showShareCard = false }
    }
    .task { await autoPost() }
    .task {
      guard !reduceMotion, !shown else { return }
      try? await Task.sleep(for: .milliseconds(100))
      shown = true
    }
    .task {
      guard !prs.isEmpty, !showPRs else { return }
      try? await Task.sleep(for: .milliseconds(250))
      withAnimation(.spring(duration: 0.45, bounce: 0.2)) { showPRs = true }
    }
  }

  private var maxMuscleSets: Int {
    summary.muscles.map(\.sets).max() ?? 0
  }

  private var musclesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Muscles worked").forgeSection()
      ForEach(summary.muscles) { entry in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(entry.muscle.a11yName).forgeBodyStrong()
            Spacer()
            Text(String(localized: "\(entry.sets) sets", bundle: L10n.bundle))
              .forgeLabel()
              .monospacedDigit()
          }
          GeometryReader { g in
            ZStack(alignment: .leading) {
              Capsule().fill(Theme.track)
              Capsule().fill(Theme.accent)
                .frame(width: g.size.width * CGFloat(entry.sets) / CGFloat(max(maxMuscleSets, 1)))
            }
          }
          .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      Image(coach.flex).resizable().scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
      LinearGradient(colors: [.black.opacity(0), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
      VStack(alignment: .leading, spacing: 8) {
        Text("SESSION COMPLETE")
          .forge(11, .semibold, tracking: 0.6)
          .foregroundColor(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Capsule().fill(.white.opacity(0.16)))
        Text(localizedDayName(summary.dayName))
          .forge(28, .bold)
          .tracking(-0.9)
          .foregroundColor(.white)
        Text(coachLine)
          .foregroundStyle(.white)
          .forgeBody()
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(.white.opacity(0.14)))
          .frame(maxWidth: 240, alignment: .leading)
      }
      .padding(18)
    }
    .frame(height: 240)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  private func display(_ kg: Double, for id: String) -> String {
    let lb = profiles.first?.isLb(for: id) ?? usesLb
    return Fmt.num(lb ? Plates.kgToLb(kg) : kg) + " " + (lb ? "lb" : "kg")
  }

  /// The content a card may show, taken from what the summary already resolved. Nothing is
  /// recalculated here: the highlights are the session's own top sets, the aggregates are the
  /// numbers the summary displays, and the scope label says which sets they cover.
  private var shareSource: ShareCardSource {
    let lb = profiles.first?.usesLb ?? usesLb
    let highlights = summary.topSets.map { top in
      ShareHighlight(
        exerciseID: top.exerciseID,
        exerciseName: top.exerciseName,
        load: CoachLocalReads.load(kg: top.weightKg, usesLb: profiles.first?.isLb(for: top.exerciseID) ?? lb),
        reps: top.reps,
        // Absent unless the lifter actually reported effort.
        rpeTenths: top.effortReported ? Int((top.rpe * 10).rounded()) : nil,
        qualifier: summary.verified ? nil : ShareCardQualifier.unverified)
    }
    let tonnage = lb ? Plates.kgToLb(summary.tonnageKg) : summary.tonnageKg
    return ShareCardSource(
      title: localizedDayName(summary.dayName),
      date: summary.date,
      highlights: highlights,
      totalExerciseCount: summary.exercises,
      aggregates: [
        ShareAggregate(
          key: "sets",
          value: String(localized: "\(summary.sets) working sets", bundle: L10n.bundle)),
        ShareAggregate(
          key: "duration",
          value: Self.durationText(summary.duration)),
        ShareAggregate(
          key: "tonnage",
          value: Fmt.grouped(tonnage) + " " + (lb ? "lb" : "kg")),
      ],
      // v1 ships the three achievement templates; the next-session projection stays behind
      // its own reviewed boundary.
      nextTarget: nil)
  }

  private func card(_ pr: PRRecord) -> Image {
    let renderer = ImageRenderer(content: PRCardView(name: pr.exercise.localizedName, value: display(pr.e1rm, for: pr.exercise.id)))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }

  /// Optional next step for a session that was saved successfully: remember the Timeline segment
  /// and close, so the Progress tab — the tab that already exists, with no second tab and no
  /// second source record — opens on the card for this session. The only write is the device-local
  /// segment key: the workout itself was saved once by `WorkoutView.finish()`, and the timeline
  /// projects that same record, so tapping this never duplicates a workout, set or entry.
  private func viewInTimeline() {
    progressSegment = JourneyPref.segmentTimeline
    onDone()
  }

  private func autoPost() async {
    guard !autoPosted, AuthClient.shared.token != nil, summary.verified else { return }
    autoPosted = true
    if autoPostWorkouts {
      let muscles = Dictionary(uniqueKeysWithValues: summary.muscles.map { (muscleDisplayName($0.muscle), $0.sets) })
      let payload: [String: Any] = [
        "dayName": summary.dayName,
        "sets": summary.sets,
        "tonnageKg": summary.tonnageKg,
        "durationMin": Int(summary.duration) / 60,
        "exercises": summary.exercises,
        "muscles": muscles,
      ]
      if await SocialClient.shared.post(type: "session", payload: payload) != nil {
        Analytics.track("post_created", ["type": "session"])
      }
    }
    if autoPostPRs {
      for pr in prs {
        let payload: [String: Any] = ["exercise": pr.exercise.name, "e1rm": pr.e1rm, "previous": pr.previous ?? 0]
        if await SocialClient.shared.post(type: "pr", payload: payload) != nil {
          Analytics.track("post_created", ["type": "pr"])
        }
      }
    }
  }
}

/// The coach's three-line debrief, shared by the summary sheet and history detail.
struct DebriefCard: View {
  let debrief: [DebriefLine]
  let coachName: String
  let hasPR: Bool

  private func symbol(for kind: DebriefLine.Kind) -> String {
    switch kind {
    case .result: return hasPR ? "trophy.fill" : "chart.line.uptrend.xyaxis"
    case .effort: return "gauge.with.needle"
    case .next: return "arrow.right.circle"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(coachName)'s debrief").forgeSection()
      ForEach(Array(debrief.enumerated()), id: \.offset) { _, line in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: symbol(for: line.kind))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 18)
          Text(line.text)
            .forgeLabel()
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

/// Shareable session card, same navy style as the PR card.
struct SessionCardView: View {
  let summary: SessionSummary
  let prNames: [String]
  var story: Bool = false

  private var tonnageText: String {
    "\(Int(summary.tonnageKg.rounded())) kg"
  }

  var body: some View {
    VStack(spacing: story ? 14 : 12) {
      Spacer(minLength: story ? 40 : 0)
      Text("SESSION COMPLETE")
        .forge(story ? 14 : 12, .semibold, tracking: 2)
        .foregroundColor(Theme.accent)
      Text(localizedDayName(summary.dayName)).forge(story ? 32 : 26, .bold, tracking: -0.8)
      Text(summary.date, style: .date).forge(story ? 14 : 12, .medium).foregroundColor(.white.opacity(0.6))
      HStack(spacing: story ? 34 : 28) {
        VStack(spacing: 2) {
          Text("\(Int(summary.duration) / 60) min").forge(story ? 24 : 20, .bold).monospacedDigit()
          Text("duration").forge(story ? 12 : 11, .medium).foregroundColor(.white.opacity(0.6))
        }
        VStack(spacing: 2) {
          Text("\(summary.sets)").forge(story ? 24 : 20, .bold).monospacedDigit()
          Text("sets").forge(story ? 12 : 11, .medium).foregroundColor(.white.opacity(0.6))
        }
        VStack(spacing: 2) {
          Text(tonnageText).forge(story ? 24 : 20, .bold).monospacedDigit()
          Text("tonnage").forge(story ? 12 : 11, .medium).foregroundColor(.white.opacity(0.6))
        }
      }
      if !prNames.isEmpty {
        VStack(spacing: 4) {
          ForEach(prNames, id: \.self) { name in
            Text(name).forge(story ? 15 : 13, .medium).foregroundColor(.white.opacity(0.85))
          }
        }
      }
      HStack(spacing: 6) {
        Image(systemName: "flame.fill").font(.system(size: story ? 13 : 11, weight: .bold))
        Text("REGULIFT").forge(story ? 13 : 11, .medium, tracking: 3)
      }
      .foregroundColor(.white.opacity(0.6))
      Spacer(minLength: story ? 40 : 0)
    }
    .padding(story ? 40 : 30)
    .foregroundColor(.white)
    .background(
      LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.20), Color(red: 0.02, green: 0.03, blue: 0.06)], startPoint: .top, endPoint: .bottom))
    .frame(width: 360, height: story ? 640 : nil)
  }
}
