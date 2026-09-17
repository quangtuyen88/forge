import SwiftUI

struct AvatarInitial: View {
  let handle: String?
  var size: CGFloat = 36

  var body: some View {
    Text(String((handle ?? "?").prefix(1)).uppercased())
      .forge(size * 0.42, .bold)
      .foregroundColor(Theme.onAccent)
      .frame(width: size, height: size)
      .background(Circle().fill(Theme.accent))
      .accessibilityHidden(true)
  }
}

struct PostCardView: View {
  let post: Post
  @State private var kudoedOverride: Bool?
  @State private var kudosDelta = 0
  @State private var commentDelta = 0
  @State private var showComments = false

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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
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
              .font(.system(size: 14, weight: .semibold))
            Text("\(kudosCount)").forgeLabel().monospacedDigit()
          }
          .foregroundStyle(kudoed ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        Button { showComments = true } label: {
          HStack(spacing: 5) {
            Image(systemName: "bubble.right")
              .font(.system(size: 14, weight: .semibold))
            Text("\(commentsCount)").forgeLabel().monospacedDigit()
          }
          .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        Spacer()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(isPresented: $showComments) {
      CommentsSheet(post: post) { commentDelta += 1 }
    }
  }

  private var sessionBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(post.str("dayName") ?? String(localized: "Session")).forge(18, .semibold, tracking: -0.5)
      HStack(spacing: 22) {
        stat("\(Int(post.num("sets") ?? 0))", String(localized: "sets"))
        stat(String(localized: "\(Fmt.grouped(post.num("tonnageKg") ?? 0)) kg"), String(localized: "tonnage"))
        stat(String(localized: "\(Int(post.num("durationMin") ?? 0)) min"), String(localized: "duration"))
      }
      if let line = post.muscleLine {
        Text(line).forgeLabel().monospacedDigit()
      }
    }
  }

  private var prBody: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(post.str("exercise") ?? String(localized: "PR")).forgeBodyStrong()
      Spacer()
      Text(String(localized: "\(Fmt.num(post.num("e1rm") ?? 0)) kg e1RM"))
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
      let ok = await SocialClient.shared.kudos(postID: post.id, on: newValue)
      if !ok {
        kudoedOverride = nil
        kudosDelta += newValue ? -1 : 1
      }
    }
  }
}

struct CommentsSheet: View {
  let post: Post
  var onPosted: () -> Void = {}
  @State private var comments: [Comment]?
  @State private var text = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let comments {
          if comments.isEmpty {
            Text("No comments yet. Say something.").forgeLabel().padding(.top, 40)
          } else {
            List(comments) { comment in
              VStack(alignment: .leading, spacing: 4) {
                Text(comment.text).forgeBody()
                Text(comment.date ?? .now, format: .relative(presentation: .named)).forgeCaption()
              }
              .padding(.vertical, 4)
            }
            .listStyle(.plain)
          }
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("Comments")
      .toolbar { Button("Done") { dismiss() } }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 10) {
          TextField("Add a comment", text: $text)
            .forgeBody()
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
          Button("Send") { send() }
            .foregroundStyle(Theme.accent)
            .forgeBodyStrong()
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(Theme.page.opacity(0.92))
        .background(.ultraThinMaterial)
      }
      .background(Theme.page)
    }
    .presentationBackground(Theme.page)
    .task { comments = await SocialClient.shared.comments(postID: post.id) }
  }

  private func send() {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return }
    text = ""
    Task {
      if let comment = await SocialClient.shared.comment(postID: post.id, text: body) {
        comments = (comments ?? []) + [comment]
        onPosted()
      }
    }
  }
}
