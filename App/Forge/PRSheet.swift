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
            Text(pr.exercise.name).font(.headline)
            Text("\(display(pr.e1rm)) e1RM · was \(display(pr.previous ?? 0))")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          ShareLink(item: card(pr), preview: SharePreview("New PR — \(pr.exercise.name)")) {
            Image(systemName: "square.and.arrow.up")
          }
        }
      }
      .navigationTitle("New PRs")
      .toolbar { Button("Done") { dismiss(); onClose() } }
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

private struct PRCardView: View {
  let name: String
  let value: String

  var body: some View {
    VStack(spacing: 10) {
      Text("NEW PR").font(.title3.bold()).foregroundStyle(.orange)
      Text(name).font(.largeTitle.bold())
      Text(value).font(.title)
      Text(Date.now.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
      Text("forge").font(.caption)
    }
    .padding(30)
    .foregroundStyle(.white)
    .background(Color.black)
    .frame(width: 360)
  }
}
