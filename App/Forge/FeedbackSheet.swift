import SwiftUI
import UIKit

extension Analytics {
  // ponytail: baseURL resolution duplicated from Analytics (private there); unify when Analytics.swift is editable
  static func sendFeedback(text: String, screen: String) async {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    struct Feedback: Codable { let device: String; let screen: String; let text: String }
    guard let secret = AppSecret.value,
          let url = URL(string: base)?.appending(path: "feedback") else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 10
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONEncoder().encode(Feedback(device: deviceID, screen: screen, text: text))
    _ = try? await URLSession.shared.data(for: req)
  }
}

struct FeedbackSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var sending = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        TextEditor(text: $text)
          .forgeBody()
          .frame(height: 180)
          .padding(8)
          .scrollContentBackground(.hidden)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
        Text("Goes to the Forge team with your device id, nothing else.")
          .forgeCaption()
        Spacer()
        Button {
          sending = true
          Task {
            await Analytics.sendFeedback(text: text, screen: "settings")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
          }
        } label: {
          HStack(spacing: 8) {
            if sending { ProgressView() }
            Text("Send")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
      }
      .padding(Theme.margin)
      .background(Theme.page)
      .navigationTitle("Send feedback")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
  }
}
