import SwiftUI
import ForgeCore

struct MuscleVolume: Identifiable {
  let muscle: Muscle
  let sets: Int
  var id: String { muscle.rawValue }
}

func muscleDisplayName(_ muscle: Muscle) -> String {
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
}

struct SessionSummaryView: View {
  let summary: SessionSummary
  let prs: [PRRecord]
  let usesLb: Bool
  var onDone: () -> Void
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = true
  @AppStorage("autoPostPRs") private var autoPostPRs = true
  @State private var autoPosted = false
  @State private var shown = false
  @State private var showPRs = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var coach: Coach { Coach.from(coachID) }

  private var tonnageText: String {
    Fmt.grouped(usesLb ? Plates.kgToLb(summary.tonnageKg) : summary.tonnageKg) + (usesLb ? " lb" : " kg")
  }

  private var coachLine: String {
    if !prs.isEmpty { return "New PR on \(prs[0].exercise.name). That's the adaptation we wanted." }
    if 2 * summary.sets < summary.plannedSets {
      return "Short one. \(summary.sets) of \(summary.plannedSets) sets logged."
    }
    return "Solid session. Recovery starts now."
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        hero
        HStack(spacing: 10) {
          StatTile(symbol: "stopwatch", value: shown || reduceMotion ? "\(Int(summary.duration) / 60) min" : "0 min", label: "duration")
          StatTile(symbol: "square.stack.3d.up.fill", value: shown || reduceMotion ? "\(summary.sets)" : "0", label: "sets logged")
          StatTile(symbol: "scalemass", value: shown || reduceMotion ? tonnageText : "0 \(usesLb ? "lb" : "kg")", label: "tonnage")
        }
        .contentTransition(.numericText(countsDown: false))
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
        if prs.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Next session").forgeSection()
            Text("Loads adapt from what you just logged. Eat, sleep, come back.").forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        } else if showPRs {
          VStack(alignment: .leading, spacing: 12) {
            Text("New PRs").forgeSection()
            ForEach(prs) { pr in
              HStack(spacing: 12) {
                ZStack {
                  Circle().fill(Theme.accent.opacity(0.12))
                  Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                  Text(pr.exercise.name).forgeBodyStrong()
                  Text("\(display(pr.e1rm)) e1RM · was \(display(pr.previous ?? 0))")
                    .forgeLabel()
                    .monospacedDigit()
                }
                Spacer()
                ShareLink(item: card(pr), preview: SharePreview("New PR — \(pr.exercise.name)")) {
                  Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
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
        Menu {
          ShareLink(item: sessionCard, preview: SharePreview("Session — \(summary.dayName)")) {
            Text("Share (square)")
          }
          ShareLink(item: sessionStoryCard, preview: SharePreview("Session — \(summary.dayName)")) {
            Text("Share (story) — Instagram/TikTok")
          }
        } label: {
          Text("Share session")
        }
        .buttonStyle(PillSecondaryButtonStyle())
        Text("Square + 9:16 story for Instagram and TikTok")
          .forgeCaption()
        Button("Done") { onDone() }
          .buttonStyle(PillButtonStyle())
      }
      .padding(.horizontal, Theme.margin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
    .presentationBackground(Theme.page)
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

  private var musclesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Muscles worked").forgeSection()
      ForEach(summary.muscles) { entry in
        HStack {
          Text(muscleDisplayName(entry.muscle)).forgeBodyStrong()
          Spacer()
          Text("\(entry.sets) \(entry.sets == 1 ? "set" : "sets")")
            .forgeLabel()
            .monospacedDigit()
        }
        .innerSurface(padding: 10)
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
        Text(summary.dayName)
          .forge(28, .bold)
          .tracking(-0.9)
          .foregroundColor(.white)
        Text(coachLine)
          .foregroundStyle(.white)
          .forgeBody()
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14)))
          .frame(maxWidth: 240, alignment: .leading)
      }
      .padding(18)
    }
    .frame(height: 240)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  private func display(_ kg: Double) -> String {
    Fmt.num(usesLb ? Plates.kgToLb(kg) : kg) + " " + (usesLb ? "lb" : "kg")
  }

  private func card(_ pr: PRRecord) -> Image {
    let renderer = ImageRenderer(content: PRCardView(name: pr.exercise.name, value: display(pr.e1rm)))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }

  private var sessionCard: Image {
    let renderer = ImageRenderer(content: SessionCardView(summary: summary, prNames: Array(prs.map(\.exercise.name).prefix(3))))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }

  private var sessionStoryCard: Image {
    let renderer = ImageRenderer(content: SessionCardView(summary: summary, prNames: Array(prs.map(\.exercise.name).prefix(3)), story: true))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }

  private func autoPost() async {
    guard !autoPosted, AuthClient.shared.token != nil else { return }
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
      Text(summary.dayName).forge(story ? 32 : 26, .bold, tracking: -0.8)
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
        Text("FORGE").forge(story ? 13 : 11, .medium, tracking: 3)
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
