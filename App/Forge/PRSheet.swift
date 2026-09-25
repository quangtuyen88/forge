import SwiftUI
import SwiftData
import ForgeCore

struct PRRecord: Identifiable {
  let exercise: Exercise
  let e1rm: Double
  let previous: Double?
  /// The record set itself; older producers (Debrief, History) leave these nil.
  var weightKg: Double? = nil
  var reps: Int? = nil
  var id: String { exercise.id }
}

struct PRSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  let prs: [PRRecord]
  let usesLb: Bool
  var onClose: () -> Void

  var body: some View {
    NavigationStack {
      List(prs) { pr in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(pr.exercise.localizedName).forgeBodyStrong()
            Text("\(display(pr.e1rm, for: pr.exercise.id)) e1RM · was \(display(pr.previous ?? 0, for: pr.exercise.id))")
              .foregroundStyle(Theme.textSecondary).forgeLabel()
              .monospacedDigit()
          }
          Spacer()
          Menu {
            ShareLink(item: card(pr, story: false), preview: SharePreview("New PR — \(pr.exercise.localizedName)")) {
              Text("Share (square)")
            }
            ShareLink(item: card(pr, story: true), preview: SharePreview("New PR — \(pr.exercise.localizedName)")) {
              Text("Share (story)")
            }
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
      .navigationTitle("New PRs")
      .toolbar { Button("Done") { dismiss(); onClose() } }
      .presentationDetents([.medium])
    }
  }

  private func display(_ kg: Double, for id: String) -> String {
    let lb = profiles.first?.isLb(for: id) ?? usesLb
    return String(format: "%.1f %@", lb ? Plates.kgToLb(kg) : kg, lb ? "lb" : "kg")
  }

  private func card(_ pr: PRRecord, story: Bool) -> Image {
    let renderer = ImageRenderer(content: PRCardView(name: pr.exercise.localizedName, value: display(pr.e1rm, for: pr.exercise.id), story: story))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }
}

struct PRCardView: View {
  let name: String
  let value: String
  var story: Bool = false
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  var body: some View {
    VStack(spacing: story ? 14 : 10) {
      Spacer(minLength: story ? 40 : 0)
      Image(coach.flex).resizable().scaledToFill()
        .frame(width: story ? 170 : 120, height: story ? 170 : 120)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.positive, lineWidth: 3))
        .accessibilityHidden(true)
      Text("New PR")
        .forge(story ? 14 : 12, .semibold)
        .foregroundStyle(Theme.positive)
      Text(name)
        .forge(story ? 30 : 24, .bold, tracking: -0.8)
        .multilineTextAlignment(.center)
      Text(value)
        .forge(story ? 44 : 34, .bold, tracking: -0.9)
        .monospacedDigit()
      Text(Date.now, style: .date)
        .forge(story ? 14 : 12, .medium)
        .foregroundStyle(.white.opacity(0.6))
      HStack(spacing: 6) {
        Image(systemName: "flame.fill").font(.system(size: story ? 13 : 11, weight: .bold))
        Text("REGULIFT").forge(story ? 13 : 11, .medium, tracking: 3)
      }
      .foregroundStyle(Color.white.opacity(0.6))
      Spacer(minLength: story ? 40 : 0)
    }
    .padding(story ? 40 : 30)
    .foregroundStyle(.white)
    .background(Theme.shareSurface)
    .frame(width: 360, height: story ? 640 : nil)
  }
}
