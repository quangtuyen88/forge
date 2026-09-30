import SwiftUI

struct AvatarInitial: View {
  let handle: String?
  var size: CGFloat = 36

  var body: some View {
    // ast-grep-ignore: design-no-uppercase-text
    Text(String((handle ?? "?").prefix(1)).uppercased())
      .forge(size * 0.42, .bold)
      .foregroundStyle(Theme.onAccent)
      .frame(width: size, height: size)
      .background(Circle().fill(Theme.accentStrong))
      .accessibilityHidden(true)
  }
}

struct PostCardView: View {
  let post: Post
  @State private var kudoedOverride: Bool?
  @State private var kudosDelta = 0
  @State private var commentDelta = 0
  @State private var showComments = false
  @State private var showReport = false
  @State private var showBlockConfirm = false
  @State private var reportThanks = false
  @State private var reportFailed = false
  @AppStorage(CrewBlocklist.key) private var blockedHandles = ""

  private var kudoed: Bool { kudoedOverride ?? post.kudoed }
  private var kudosCount: Int { post.kudos + kudosDelta }
  private var commentsCount: Int { post.comments + commentDelta }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        AvatarInitial(handle: post.user.handle)
        VStack(alignment: .leading, spacing: 2) {
          Text(post.user.handle ?? "unknown").forgeBodyStrong()
          if let date = post.date {
            Text(date, format: .relative(presentation: .named)).forgeCaption()
          }
        }
        Spacer()
        if post.type == "pr" {
          Image(systemName: "trophy.fill")
            .scaledSystemFont(14, weight: .semibold)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Personal record")
        }
        Menu {
          Button {
            showReport = true
          } label: {
            Label("Report", systemImage: "flag")
          }
          if let handle = post.user.handle {
            Button(role: .destructive) {
              showBlockConfirm = true
            } label: {
              Label("Block @\(handle)", systemImage: "hand.raised")
            }
          }
        } label: {
          Image(systemName: "ellipsis")
            .scaledSystemFont(16, weight: .semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
      }
      if post.type == "session" {
        sessionBody
      } else {
        prBody
      }
      HStack(spacing: 18) {
        Button { toggleKudos() } label: {
          HStack(spacing: 5) {
            Image(systemName: kudoed ? "hand.thumbsup.fill" : "hand.thumbsup")
              .scaledSystemFont(14, weight: .semibold)
            Text("\(kudosCount)").forgeLabel().monospacedDigit()
          }
          .foregroundStyle(kudoed ? Theme.accentText : Theme.textSecondary)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(String(localized: "Give kudos, \(kudosCount) kudos", bundle: L10n.bundle))
        .accessibilityAddTraits(kudoed ? .isSelected : [])
        Button { showComments = true } label: {
          HStack(spacing: 5) {
            Image(systemName: "bubble.right")
              .scaledSystemFont(14, weight: .semibold)
            Text("\(commentsCount)").forgeLabel().monospacedDigit()
          }
          .foregroundStyle(Theme.textSecondary)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(String(localized: "Comments, \(commentsCount)", bundle: L10n.bundle))
        Spacer()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(isPresented: $showComments) {
      CommentsSheet(post: post) { commentDelta += 1 }
    }
    .confirmationDialog("Report", isPresented: $showReport, titleVisibility: .visible) {
      Button("Spam") { submitReport("Spam") }
      Button("Harassment") { submitReport("Harassment") }
      Button("Something else") { submitReport("Something else") }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog("Block @\(post.user.handle ?? "unknown")?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
      Button("Block @\(post.user.handle ?? "unknown")", role: .destructive) { blockAuthor() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You won't see their posts or comments.")
    }
    .alert("Thanks. The Regulift team will review it.", isPresented: $reportThanks) {
      Button("OK", role: .cancel) {}
    }
    .alert(String(localized: "Couldn't send. Try again.", bundle: L10n.bundle), isPresented: $reportFailed) {
      Button("OK", role: .cancel) {}
    }
  }

  private func submitReport(_ reason: String) {
    Task {
      if await Analytics.sendFeedback(text: crewReportText(post, reason), screen: "crew") {
        AccessibilityNotification.Announcement(String(localized: "Thanks. The Regulift team will review it.", bundle: L10n.bundle)).post()
        reportThanks = true
      } else {
        reportFailed = true
      }
    }
  }

  private func blockAuthor() {
    guard let handle = post.user.handle else { return }
    blockedHandles = CrewBlocklist.adding(handle, to: blockedHandles)
  }

  private var sessionBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(post.str("dayName") ?? String(localized: "Session", bundle: L10n.bundle)).forge(18, .semibold, tracking: -0.5)
      HStack(spacing: 22) {
        stat("\(Int(post.num("sets") ?? 0))", String(localized: "sets", bundle: L10n.bundle))
        stat(String(localized: "\(Fmt.grouped(post.num("tonnageKg") ?? 0)) kg", bundle: L10n.bundle), String(localized: "tonnage", bundle: L10n.bundle))
        stat(String(localized: "\(Int(post.num("durationMin") ?? 0)) min", bundle: L10n.bundle), String(localized: "duration", bundle: L10n.bundle))
      }
      if let line = post.muscleLine {
        Text(line).forgeLabel().monospacedDigit()
      }
    }
  }

  private var prBody: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(post.str("exercise") ?? String(localized: "PR", bundle: L10n.bundle)).forgeBodyStrong()
      Spacer()
      Text(String(localized: "\(Fmt.num(post.num("e1rm") ?? 0)) kg e1RM", bundle: L10n.bundle))
        .forgeNumber()
        .monospacedDigit()
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value).forge(16, .bold).monospacedDigit()
      Text(label).forgeCaption()
    }
  }

  private func toggleKudos() {
    let newValue = !kudoed
    kudoedOverride = newValue
    kudosDelta += newValue ? 1 : -1
    Task {
      do {
        try await SocialClient.shared.kudos(postID: post.id, on: newValue)
      } catch {
        kudoedOverride = nil
        kudosDelta += newValue ? -1 : 1
        AccessibilityNotification.Announcement(String(localized: "Couldn't send kudos.", bundle: L10n.bundle)).post()
      }
    }
  }
}

private func crewReportText(_ post: Post, _ reason: String) -> String {
  "crew report · \(reason) · post \(post.id) · @\(post.user.handle ?? "unknown")"
}

private func commentReportText(_ comment: Comment, _ post: Post, _ reason: String) -> String {
  let author = comment.userId == post.user.id ? "@\(post.user.handle ?? "unknown")" : "user \(comment.userId)"
  return "crew report · \(reason) · comment \(comment.id) · post \(post.id) · \(author)"
}

struct CommentsSheet: View {
  let post: Post
  var onPosted: () -> Void = {}
  @State private var comments: [Comment]?
  @State private var text = ""
  @State private var sendError: String?
  @State private var sending = false
  @State private var showReport = false
  @State private var reportedComment: Comment?
  @State private var showBlockConfirm = false
  @State private var reportThanks = false
  @State private var reportFailed = false
  @AppStorage(CrewBlocklist.key) private var blockedHandles = ""
  @Environment(\.dismiss) private var dismiss

  /// The comments endpoint returns no author handle, so blocking can only target the post's author.
  private var visibleComments: [Comment] {
    (comments ?? []).filter { comment in
      !(CrewBlocklist.contains(post.user.handle, in: blockedHandles) && comment.userId == post.user.id)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if let comments {
          if visibleComments.isEmpty {
            Text("No comments yet. Say something.").forgeLabel().padding(.top, 40)
          } else {
            List(visibleComments) { comment in
              VStack(alignment: .leading, spacing: 4) {
                Text(comment.text).forgeBody()
                Text(comment.date ?? .now, format: .relative(presentation: .named)).forgeCaption()
              }
              .padding(.vertical, 4)
              .contextMenu {
                Button {
                  reportedComment = comment
                  showReport = true
                } label: {
                  Label("Report", systemImage: "flag")
                }
                if comment.userId == post.user.id, let handle = post.user.handle {
                  Button(role: .destructive) {
                    showBlockConfirm = true
                  } label: {
                    Label("Block @\(handle)", systemImage: "hand.raised")
                  }
                }
              }
            }
            .listStyle(.plain)
          }
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("Comments")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            TextField("Add a comment", text: $text)
              .forgeBody()
              .padding(10)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
            Button {
              send()
            } label: {
              Text("Send")
                .foregroundStyle(Theme.accentText)
                .forgeBodyStrong()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
          }
          if let sendError {
            Text(sendError).forgeCaption().foregroundStyle(Theme.negative)
          }
        }
        .padding(.horizontal, Theme.barMargin)
        .padding(.vertical, 10)
        .background(Theme.page.opacity(0.92))
        .background(.ultraThinMaterial)
      }
      .background(Theme.page)
      .confirmationDialog("Report", isPresented: $showReport, titleVisibility: .visible) {
        Button("Spam") { submitReport("Spam") }
        Button("Harassment") { submitReport("Harassment") }
        Button("Something else") { submitReport("Something else") }
        Button("Cancel", role: .cancel) {}
      }
      .confirmationDialog("Block @\(post.user.handle ?? "unknown")?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
        Button("Block @\(post.user.handle ?? "unknown")", role: .destructive) { blockAuthor() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You won't see their posts or comments.")
      }
      .alert("Thanks. The Regulift team will review it.", isPresented: $reportThanks) {
        Button("OK", role: .cancel) {}
      }
      .alert(String(localized: "Couldn't send. Try again.", bundle: L10n.bundle), isPresented: $reportFailed) {
        Button("OK", role: .cancel) {}
      }
    }
    .presentationBackground(Theme.page)
    .task {
      do {
        comments = try await SocialClient.shared.comments(postID: post.id)
      } catch {
        comments = []
      }
    }
  }

  private func submitReport(_ reason: String) {
    let comment = reportedComment
    let reportText = comment.map { commentReportText($0, post, reason) } ?? crewReportText(post, reason)
    Task {
      if await Analytics.sendFeedback(text: reportText, screen: "crew") {
        AccessibilityNotification.Announcement(String(localized: "Thanks. The Regulift team will review it.", bundle: L10n.bundle)).post()
        reportThanks = true
      } else {
        reportFailed = true
      }
    }
  }

  private func blockAuthor() {
    guard let handle = post.user.handle else { return }
    blockedHandles = CrewBlocklist.adding(handle, to: blockedHandles)
  }

  private func send() {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty, !sending else { return }
    sending = true
    sendError = nil
    Task {
      defer { sending = false }
      do {
        let comment = try await SocialClient.shared.comment(postID: post.id, text: body)
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == body { text = "" }
        comments = (comments ?? []) + [comment]
        onPosted()
      } catch {
        sendError = String(localized: "Couldn't post your comment.", bundle: L10n.bundle)
      }
    }
  }
}
