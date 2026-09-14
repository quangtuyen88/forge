import SwiftUI
import ForgeCore

struct PRRecord: Identifiable {
  let exercise: Exercise
  let e1rm: Double
  let previous: Double?
  var id: String { exercise.id }
}

struct PRSheet: View {
  @Environment(\.dismiss) private var dismiss
  let prs: [PRRecord]
  let usesLb: Bool
  var onClose: () -> Void

  var body: some View {
    NavigationStack {
      List(prs) { pr in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(pr.exercise.name).forgeBodyStrong()
            Text("\(display(pr.e1rm)) e1RM · was \(display(pr.previous ?? 0))")
              .foregroundStyle(Theme.textSecondary).forgeLabel()
              .monospacedDigit()
          }
          Spacer()
          ShareLink(item: card(pr), preview: SharePreview("New PR — \(pr.exercise.name)")) {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
      .navigationTitle("New PRs")
      .toolbar { Button("Done") { dismiss(); onClose() } }
      .presentationDetents([.medium])
    }
  }

  private func display(_ kg: Double) -> String {
    String(format: "%.1f %@", usesLb ? Plates.kgToLb(kg) : kg, usesLb ? "lb" : "kg")
  }

  private func card(_ pr: PRRecord) -> Image {
    let renderer = ImageRenderer(content: PRCardView(name: pr.exercise.name, value: display(pr.e1rm)))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }
}

struct PRCardView: View {
  let name: String
  let value: String
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  var body: some View {
    VStack(spacing: 10) {
      Image(coach.flex).resizable().scaledToFill()
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
        .shadow(color: Theme.accent.opacity(0.35), radius: 18)
        .accessibilityHidden(true)
      Text("NEW PR")
        .forge(12, .semibold, tracking: 2)
        .foregroundColor(Theme.accent)
      Text(name).forge(24, .bold, tracking: -0.8)
      Text(value).forge(34, .bold, tracking: -0.9).monospacedDigit()
      Text(Date.now, style: .date).forge(12, .medium).foregroundColor(.white.opacity(0.6))
      HStack(spacing: 6) {
        Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold))
        Text("FORGE").forge(11, .medium, tracking: 3)
      }
      .foregroundColor(Color.white.opacity(0.6))
    }
    .padding(30)
    .foregroundColor(.white)
    .background(
      LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.20), Color(red: 0.02, green: 0.03, blue: 0.06)], startPoint: .top, endPoint: .bottom))
    .frame(width: 360)
  }
}
