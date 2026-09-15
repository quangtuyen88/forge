import SwiftUI

// ponytail: CrewProfileView shows the other user's posts filtered from the first feed page only; a dedicated per-user posts endpoint can extend this later
struct CrewView: View {
  @Environment(AuthClient.self) private var auth
  @State private var segment = 0
  @State private var profile: CrewProfile?
  @State private var checking = true
  @State private var showSignIn = false
  @State private var showInvite = false
  @State private var showEdit = false

  var body: some View {
    Group {
      if auth.user == nil {
        signedOut
      } else if checking {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let profile {
        content(profile)
      }
    }
    .background(Theme.page)
    .navigationTitle("Crew")
    .sheet(isPresented: $showSignIn) { AccountView() }
    .sheet(isPresented: $showInvite) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Invite").forgeSection()
        ReferralView()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showEdit) {
      if let profile {
        HandleSetupCard(existing: profile) { updated in self.profile = updated }
      }
    }
    .task(id: auth.user?.id) {
      guard auth.user != nil else { checking = false; return }
      profile = await SocialClient.shared.profile()
      checking = false
    }
  }

  private var signedOut: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: "person.2.fill")
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 56, height: 56)
        .background(Circle().fill(Theme.accent.opacity(0.12)))
        .padding(.bottom, 6)
      Text("Train with friends").forgeTitle()
      Text("Follow your crew, see every session, give kudos and climb the weekly leaderboard.")
        .forgeBody()
      Button("Sign in") { showSignIn = true }
        .buttonStyle(PillButtonStyle())
        .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
  }

  private func content(_ profile: CrewProfile) -> some View {
    VStack(spacing: 0) {
      Picker("Crew", selection: $segment) {
        Text("Feed").tag(0)
        Text("Leaderboard").tag(1)
        Text("Me").tag(2)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, Theme.inner)
      switch segment {
      case 1: LeaderboardTab()
      case 2: MeTab(profile: profile, showInvite: $showInvite, showEdit: $showEdit)      default: FeedTab()
      }
    }
  }
}

// MARK: - Feed

private struct FeedTab: View {
  @State private var posts: [Post] = []
  @State private var nextCursor: String?
  @State private var loading = false
  @State private var loaded = false
  @State private var findHandle = ""
  @State private var found: CrewUserDetail?
  @State private var findError: String?

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.inner) {
        if posts.isEmpty && loaded {
          emptyState
        } else {
          ForEach(posts) { post in
            PostCardView(post: post)
          }
          if nextCursor != nil {
            Button {
              Task { await loadMore() }
            } label: {
              if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
              } else {
                Text("Load more").forgeBodyStrong().frame(maxWidth: .infinity, minHeight: 44)
              }
            }
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .refreshable { await load(reset: true) }
    .task { if !loaded { await load(reset: true) } }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Follow someone to fill this up").forgeSection()
      Text("Sessions and PRs from people you follow land here.").forgeLabel()
      HStack(spacing: 10) {
        TextField("Find people — their handle", text: $findHandle)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .forgeBody()
          .padding(10)
          .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
        Button("Find") { find() }
          .foregroundStyle(Theme.accent)
          .forgeBodyStrong()
          .disabled(findHandle.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if let findError {
        Text(findError).forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .sheet(item: $found) { detail in
      CrewProfileView(handle: detail.profile.handle)
    }
  }

  private func find() {
    let handle = findHandle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !handle.isEmpty else { return }
    findError = nil
    Task {
      if let detail = await SocialClient.shared.user(handle: handle) {
        found = detail
      } else {
        findError = SocialClient.shared.lastError ?? "No one with that handle"
      }
    }
  }

  private func load(reset: Bool) async {
    loading = true
    defer { loading = false }
    if let page = await SocialClient.shared.feed(cursor: reset ? nil : nextCursor) {
      if reset { posts = page.posts } else { posts += page.posts }
      nextCursor = page.nextCursor
    }
    loaded = true
  }

  private func loadMore() async {
    await load(reset: false)
  }
}

// MARK: - Leaderboard

private func isoWeekKey(_ date: Date = .now) -> String {
  var cal = Calendar(identifier: .iso8601)
  cal.timeZone = TimeZone(identifier: "UTC")!
  let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
  return String(format: "%d-W%02d", comps.yearForWeekOfYear!, comps.weekOfYear!)
}

private func isoWeek(offset: Int) -> String {
  var cal = Calendar(identifier: .iso8601)
  cal.timeZone = TimeZone(identifier: "UTC")!
  let shifted = cal.date(byAdding: .weekOfYear, value: offset, to: .now) ?? .now
  return isoWeekKey(shifted)
}

private struct LeaderboardTab: View {
  @Environment(AuthClient.self) private var auth
  @State private var weekOffset = 0
  @State private var rows: [LeaderRow]?

  private var weekLabel: String {
    weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week" : isoWeek(offset: weekOffset)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.inner) {
        HStack {
          Button { weekOffset -= 1 } label: {
            Image(systemName: "chevron.left").frame(width: 40, height: 40)
          }
          .buttonStyle(IconButtonStyle())
          Spacer()
          Text(weekLabel).forgeBodyStrong()
          Spacer()
          Button { weekOffset = min(0, weekOffset + 1) } label: {
            Image(systemName: "chevron.right").frame(width: 40, height: 40)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(weekOffset >= 0)
        }
        .padding(.horizontal, 2)
        if let rows {
          if rows.isEmpty {
            Text("No sessions this week yet.").forgeLabel().padding(.top, 24)
          } else {
            VStack(spacing: 0) {
              ForEach(Array(rows.enumerated()), id: \.element.userId) { index, row in
                leaderboardRow(rank: index + 1, row: row)
                if index < rows.count - 1 { Divider().overlay(Theme.ring) }
              }
            }
            .card(padding: 6)
          }
        } else {
          ProgressView().padding(.top, 40)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .task(id: isoWeek(offset: weekOffset)) {
      rows = await SocialClient.shared.leaderboard(week: isoWeek(offset: weekOffset))
    }
  }

  private func leaderboardRow(rank: Int, row: LeaderRow) -> some View {
    let isSelf = row.userId == auth.user?.id
    return HStack(spacing: 12) {
      Text("\(rank)").forge(15, .bold).monospacedDigit()
        .foregroundColor(isSelf ? Theme.accent : Theme.textTertiary)
        .frame(width: 28)
      Text(row.handle ?? "—").forgeBodyStrong()
      Spacer()
      Text("\(row.sessions) sessions").forgeLabel().monospacedDigit()
      Text("\(Int(row.tonnageKg.rounded())) kg").forgeLabel().monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 12)
    .frame(minHeight: 44)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .fill(isSelf ? Theme.accent.opacity(0.10) : .clear))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .strokeBorder(isSelf ? Theme.accent : .clear, lineWidth: 1.5))
    .contentShape(Rectangle())
  }
}

// MARK: - Me

private struct MeTab: View {
  let profile: CrewProfile
  @Binding var showInvite: Bool
  @Binding var showEdit: Bool
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = true
  @AppStorage("autoPostPRs") private var autoPostPRs = true
  @State private var stats: CrewStats?

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            AvatarInitial(handle: profile.handle)
            VStack(alignment: .leading, spacing: 2) {
              Text("@\(profile.handle)").forgeBodyStrong()
              Text(profile.displayName).forgeLabel()
            }
            Spacer()
            Button("Edit") { showEdit = true }
              .foregroundStyle(Theme.accent)
              .forgeBodyStrong()
          }
          if !profile.bio.isEmpty {
            Text(profile.bio).forgeBody()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        if let stats {
          HStack(spacing: 10) {
            StatTile(symbol: "dumbbell.fill", value: "\(stats.sessions)", label: "sessions posted")
            StatTile(symbol: "flame.fill", value: "\(stats.streakWeeks)", label: "week streak")
          }
          if !stats.topPRs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              Text("Top PRs").forgeSection().padding(.bottom, 10)
              ForEach(stats.topPRs, id: \.exercise) { pr in
                HStack {
                  Text(pr.exercise).forgeBody()
                  Spacer()
                  Text(String(format: "%.1f kg", pr.e1rm)).forgeLabel().monospacedDigit()
                }
                .frame(minHeight: 40)
              }
            }
            .card()
          }
        }

        Button { showInvite = true } label: {
          HStack {
            Image(systemName: "person.badge.plus")
              .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
              Text("Invite a friend").forgeBodyStrong()
              Text("Give a month, get a month").forgeLabel()
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
          }
          .frame(minHeight: 52)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()

        VStack(alignment: .leading, spacing: 0) {
          Text("Auto-post").forgeSection().padding(.bottom, 10)
          HStack {
            Text("Finished workouts").forgeBody()
            Spacer()
            Text(autoPostWorkouts ? "On" : "Off").forgeLabel()
          }
          .frame(minHeight: 36)
          Divider().overlay(Theme.ring)
          HStack {
            Text("New PRs").forgeBody()
            Spacer()
            Text(autoPostPRs ? "On" : "Off").forgeLabel()
          }
          .frame(minHeight: 36)
          Text("Change these in Settings → Crew.").forgeCaption().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .task(id: profile.handle) {
      stats = await SocialClient.shared.user(handle: profile.handle)?.stats
    }
  }
}

// MARK: - Handle setup / edit

struct HandleSetupCard: View {
  let existing: CrewProfile?
  let onSave: (CrewProfile) -> Void
  @State private var handle = ""
  @State private var displayName = ""
  @State private var bio = ""
  @State private var saving = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(existing == nil ? "Pick a handle" : "Edit profile").forgeTitle()
      Text("Your handle is how friends find you in the crew.").forgeLabel()
      TextField("Handle (a-z, 0-9, _)", text: $handle)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .forgeBody()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
      TextField("Display name", text: $displayName)
        .forgeBody()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
      TextField("Bio (optional)", text: $bio, axis: .vertical)
        .lineLimit(1...3)
        .forgeBody()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
      if let error {
        Text(error).forgeCaption().foregroundStyle(Theme.negative)
      }
      Button {
        Task { await save() }
      } label: {
        if saving {
          ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 52)
        } else {
          Text(existing == nil ? "Create profile" : "Save")
        }
      }
      .buttonStyle(PillButtonStyle())
      .disabled(saving || handle.isEmpty || displayName.isEmpty)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
    .onAppear {
      if let existing, handle.isEmpty {
        handle = existing.handle
        displayName = existing.displayName
        bio = existing.bio
      }
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    if let updated = await SocialClient.shared.updateProfile(handle: handle, displayName: displayName, bio: bio) {
      onSave(updated)
      dismiss()
    } else {
      error = SocialClient.shared.lastError ?? "Could not save profile"
    }
  }
}

// MARK: - Other user's profile

struct CrewProfileView: View {
  let handle: String
  @Environment(\.dismiss) private var dismiss
  @State private var detail: CrewUserDetail?
  @State private var posts: [Post] = []
  @State private var busy = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if let detail {
            profileCard(detail)
            if !posts.isEmpty {
              ForEach(posts) { post in
                PostCardView(post: post)
              }
            } else {
              Text("No recent sessions posted.").forgeLabel()
            }
          } else {
            ProgressView().padding(.top, 60)
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("@\(handle)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
    .presentationBackground(Theme.page)
    .task { await load() }
  }

  private func profileCard(_ detail: CrewUserDetail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AvatarInitial(handle: detail.profile.handle)
        VStack(alignment: .leading, spacing: 2) {
          Text(detail.profile.displayName).forgeBodyStrong()
          Text("@\(detail.profile.handle)").forgeLabel()
        }
        Spacer()
      }
      if !detail.profile.bio.isEmpty {
        Text(detail.profile.bio).forgeBody()
      }
      HStack(spacing: 22) {
        VStack(alignment: .leading, spacing: 1) {
          Text("\(detail.stats.sessions)").forge(16, .bold).monospacedDigit()
          Text("sessions").forgeCaption()
        }
        VStack(alignment: .leading, spacing: 1) {
          Text("\(detail.stats.streakWeeks)").forge(16, .bold).monospacedDigit()
          Text("week streak").forgeCaption()
        }
        Spacer()
      }
      if detail.following {
        Button {
          Task { await toggleFollow() }
        } label: {
          if busy {
            ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 52)
          } else {
            Text("Unfollow")
          }
        }
        .buttonStyle(PillSecondaryButtonStyle())
      } else {
        Button {
          Task { await toggleFollow() }
        } label: {
          if busy {
            ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 52)
          } else {
            Text("Follow")
          }
        }
        .buttonStyle(PillButtonStyle())
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func load() async {
    detail = await SocialClient.shared.user(handle: handle)
    if let page = await SocialClient.shared.feed() {
      posts = page.posts.filter { $0.user.id == detail?.profile.userId }
    }
  }

  private func toggleFollow() async {
    guard let detail else { return }
    busy = true
    defer { busy = false }
    let ok = detail.following
      ? await SocialClient.shared.unfollow(id: detail.profile.userId)
      : await SocialClient.shared.follow(id: detail.profile.userId)
    if ok { self.detail?.following.toggle() }
  }
}
