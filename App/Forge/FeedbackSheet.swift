import SwiftUI
import UIKit

extension Analytics {
  // ponytail: baseURL resolution duplicated from Analytics (private there); unify when Analytics.swift is editable
  @discardableResult static func sendFeedback(text: String, screen: String) async -> Bool {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    struct Feedback: Codable { let device: String; let screen: String; let text: String }
    guard let secret = AppSecret.value,
          let url = URL(string: base)?.appending(path: "feedback") else { return false }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 10
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONEncoder().encode(Feedback(device: deviceID, screen: screen, text: text))
    guard let (_, response) = try? await URLSession.shared.data(for: req),
          let http = response as? HTTPURLResponse else { return false }
    return (200..<300).contains(http.statusCode)
  }
}

struct FeedbackSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var sending = false
  @State private var failed = false
  @State private var confirmDiscard = false

  /// The Settings agent pushes this view inside its own stack with this false.
  var showsOwnNavigationStack = true

  var body: some View {
    if showsOwnNavigationStack {
      NavigationStack { editor }
    } else {
      editor
    }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextEditor(text: $text)
        .forgeBody()
        .frame(height: 180)
        .accessibilityLabel("Feedback")
        .overlay(alignment: .topLeading) {
          if text.isEmpty {
            Text("What's working, what isn't?")
              .forgeBody()
              .foregroundStyle(Theme.textTertiary)
              .padding(.horizontal, 8)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .padding(8)
        .scrollContentBackground(.hidden)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
      Text("Goes to the Regulift team with your device id, nothing else.")
        .forgeCaption()
      Spacer()
      if failed {
        Text("Couldn't send. Check your connection and try again.")
          .forgeCaption()
          .foregroundStyle(Theme.negative)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button {
        send()
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
    .toolbar {
      if showsOwnNavigationStack {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            if text.isEmpty {
              dismiss()
            } else {
              confirmDiscard = true
            }
          }
        }
      }
    }
    .interactiveDismissDisabled(!text.isEmpty)
    .confirmationDialog(
      "Discard your feedback?",
      isPresented: $confirmDiscard,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { dismiss() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text("What you typed is thrown away.")
    }
  }

  private func send() {
    sending = true
    failed = false
    Task {
      let ok = await Analytics.sendFeedback(text: text, screen: "settings")
      if ok {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
      } else {
        sending = false
        failed = true
      }
    }
  }
}
