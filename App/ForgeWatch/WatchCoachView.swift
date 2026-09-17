import SwiftUI
import WatchConnectivity

struct WatchCoachView: View {
  @Environment(WatchStore.self) private var store
  @State private var text = ""
  @State private var thinking = false
  @State private var errorText: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          TextField("Ask coach", text: $text)
            .font(WatchTheme.font(15))
          Button {
            send()
          } label: {
            Text("Send")
              .font(WatchTheme.font(13, .semibold))
              .foregroundStyle(.black)
          }
          .buttonStyle(.borderedProminent)
          .tint(WatchTheme.accent)
          .disabled(thinking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        if thinking {
          ProgressView()
        }

        if !store.lastAnswer.isEmpty {
          Text(store.lastAnswer)
            .font(WatchTheme.font(15))
        }

        if !WCSession.default.isReachable {
          Text("Open Regulift on iPhone")
            .font(WatchTheme.font(13))
            .foregroundStyle(.secondary)
        }

        if let errorText {
          Text(errorText)
            .font(WatchTheme.font(13))
            .foregroundStyle(WatchTheme.danger)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Ask coach")
    .onAppear {
      if text.isEmpty { text = store.lastQuestion }
    }
  }

  private func send() {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !thinking else { return }
    guard WCSession.default.isReachable else {
      errorText = String(localized: "Open Regulift on iPhone")
      return
    }
    store.lastQuestion = question
    thinking = true
    errorText = nil

    let timeout = Task {
      try? await Task.sleep(for: .seconds(30))
      guard !Task.isCancelled else { return }
      await MainActor.run {
        thinking = false
        errorText = String(localized: "Coach is offline right now.")
      }
    }

    WCSession.default.sendMessage(["ask": question], replyHandler: { reply in
      Task { @MainActor in
        timeout.cancel()
        thinking = false
        errorText = nil
        if let answer = reply["answer"] as? String, !answer.isEmpty {
          store.lastAnswer = answer
        }
      }
    }, errorHandler: { _ in
      Task { @MainActor in
        timeout.cancel()
        thinking = false
        errorText = String(localized: "Coach is offline right now.")
      }
    })
  }
}
