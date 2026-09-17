import SwiftUI
import SwiftData

// ponytail: CrewProfileView shows the other user's posts filtered from the first feed page only; a dedicated per-user posts endpoint can extend this later
struct CrewView: View {
  @Environment(AuthClient.self) private var auth
  @State private var segment = 1
  @State private var profile: CrewProfile?
  @State private var checking = true
  @State private var loadError: String?
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
      } else if let loadError {
        errorCard(loadError)
      } else {
        HandleSetupCard(existing: nil) { profile = $0 }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
      await loadProfile()
    }
  }

  private func loadProfile() async {
    let loaded = await SocialClient.shared.profile()
    profile = loaded
    // ponytail: matching the server's "profile not found" message stands in for a typed 404 (client exposes only lastError)
    loadError = loaded == nil && SocialClient.shared.lastError != "profile not found"
      ? SocialClient.shared.lastError ?? String(localized: "Crew is unreachable") : nil
    checking = false
  }

  private func errorCard(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Crew is unreachable").forgeTitle()
      Text(message).forgeLabel()
      Button("Try again") { Task { checking = true; await loadProfile() } }
        .buttonStyle(PillSecondaryButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
  }

  private var signedOut: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: "person.2.fill")
        .font(.system(size: 28, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 56, height: 56)
        .background(Circle().fill(Theme.accentTint))
        .padding(.bottom, 6)
      Text("Train with your crew").forgeTitle()
      Text("See everyone's week as rings, give kudos, climb the board.")
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
        Text("Rings").tag(1)
        Text("Me").tag(2)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, Theme.inner)
      switch segment {
      case 1: RingsTab(showInvite: $showInvite)
      case 2: MeTab(profile: profile, showInvite: $showInvite, showEdit: $showEdit)
      default: FeedTab()
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
      Image(systemName: "bubble.left.and.bubble.right.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 48, height: 48)
        .background(Circle().fill(Theme.accentTint))
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
    .sheet(item: $found, onDismiss: { Task { await load(reset: true) } }) { detail in
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
        findError = SocialClient.shared.lastError ?? String(localized: "No one with that handle")
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

private struct RingsTab: View {
  @Environment(AuthClient.self) private var auth
  @Query private var profiles: [UserProfile]
  @Binding var showInvite: Bool
  @State private var weekOffset = 0
  @State private var rows: [LeaderRow]?
  @State private var sort: RingSort = .sessions
  private enum RingSort: String, CaseIterable {
    case sessions = "Sessions", tonnage = "Tonnage", name = "Name"
    var label: String {
      switch self {
      case .sessions: return String(localized: "Sessions")
      case .tonnage: return String(localized: "Tonnage")
      case .name: return String(localized: "Name")
      }
    }
  }

  private var target: Int { max(profiles.first?.daysPerWeek ?? 3, 1) }

  private var weekLabel: String {
    weekOffset == 0 ? String(localized: "This week") : weekOffset == -1 ? String(localized: "Last week") : isoWeek(offset: weekOffset)
  }

  private var weekRangeText: String {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let shifted = cal.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
    guard let week = cal.dateInterval(of: .weekOfYear, for: shifted) else { return "" }
    return "\(week.start.formatted(.dateTime.weekday(.abbreviated).day())) – \(week.end.addingTimeInterval(-1).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
  }

  private var sortedRows: [LeaderRow] {
    guard let rows else { return [] }
    switch sort {
    case .sessions: return rows.sorted { ($0.sessions, $0.tonnageKg) > ($1.sessions, $1.tonnageKg) }
    case .tonnage: return rows.sorted { $0.tonnageKg > $1.tonnageKg }
    case .name: return rows.sorted { ($0.handle ?? "") < ($1.handle ?? "") }
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
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
        HStack {
          Text(weekRangeText).forgeCaption()
          Spacer()
          Menu {
            Picker("Sort", selection: $sort) {
              ForEach(RingSort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
          } label: {
            HStack(spacing: 4) {
              Text(sort.label).forgeBodyStrong()
              Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
          }
        }
        if let rows {
          if rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Image(systemName: "person.2.fill").font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.accent).frame(width: 48, height: 48).background(Circle().fill(Theme.accentTint))
              Text("No sessions this week yet").forgeSection()
              Text("Rings fill as your crew logs. Yours counts too.").forgeLabel()
              Button("Invite a friend") { showInvite = true }.buttonStyle(PillSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
          } else {
            ForEach(sortedRows) { row in
              ringRow(row)
            }
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

  private func ringRow(_ row: LeaderRow) -> some View {
    let isSelf = row.userId == auth.user?.id
    return HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          AvatarInitial(handle: row.handle, size: 32)
          Text(isSelf ? String(localized: "you") : (row.handle ?? "—")).forgeBodyStrong()
          if isSelf { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
        }
        MetricValue(value: "\(row.sessions)/\(target)", unit: String(localized: "sessions"), size: 30, color: Theme.accentValue)
        MetricValue(value: Fmt.grouped(row.tonnageKg), unit: "kg", size: 15, color: Theme.textSecondary, unitColor: Theme.textTertiary)
      }
      Spacer()
      RingView(progress: Double(row.sessions) / Double(target), lineWidth: 10, color: row.sessions >= target ? Theme.positive : Theme.accentValue, accessibilityLabel: String(localized: "\(row.sessions) of \(target) sessions"))
        .frame(width: 84, height: 84)
    }
    .card()
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(isSelf ? Theme.accent : .clear, lineWidth: 1.5))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(isSelf ? "You" : row.handle ?? "Someone"), \(row.sessions) of \(target) sessions, \(Fmt.grouped(row.tonnageKg)) kilograms")
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
            StatTile(symbol: "dumbbell.fill", value: "\(stats.sessions)", label: String(localized: "sessions posted"), tint: Theme.accentValue)
            StatTile(symbol: "flame.fill", value: "\(stats.streakWeeks)", unit: "wk", label: String(localized: "streak"))
          }
          if !stats.topPRs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              Text("Top PRs").forgeSection().padding(.bottom, 10)
              ForEach(Array(stats.topPRs.enumerated()), id: \.element.exercise) { index, pr in
                SessionRow(title: pr.exercise, value: Fmt.num(pr.e1rm), unit: "kg", trailing: "e1RM", symbol: "trophy.fill")
                if index < stats.topPRs.count - 1 { Divider().overlay(Theme.ring) }
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
            Text(autoPostWorkouts ? String(localized: "On") : String(localized: "Off")).forgeLabel()
          }
          .frame(minHeight: 36)
          Divider().overlay(Theme.ring)
          HStack {
            Text("New PRs").forgeBody()
            Spacer()
            Text(autoPostPRs ? String(localized: "On") : String(localized: "Off")).forgeLabel()
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
      Text(existing == nil ? String(localized: "Pick a handle") : String(localized: "Edit profile")).forgeTitle()
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
          ProgressView().tint(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 52)
        } else {
          Text(existing == nil ? String(localized: "Create profile") : String(localized: "Save"))
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
      error = SocialClient.shared.lastError ?? String(localized: "Could not save profile")
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
            if !detail.stats.topPRs.isEmpty {
              VStack(alignment: .leading, spacing: 0) {
                Text("Top PRs").forgeSection().padding(.bottom, 10)
                ForEach(Array(detail.stats.topPRs.enumerated()), id: \.element.exercise) { index, pr in
                  SessionRow(title: pr.exercise, value: Fmt.num(pr.e1rm), unit: "kg", trailing: "e1RM", symbol: "trophy.fill")
                  if index < detail.stats.topPRs.count - 1 { Divider().overlay(Theme.ring) }
                }
              }
              .card()
            }
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
    VStack(spacing: 12) {
      AvatarInitial(handle: detail.profile.handle, size: 96)
      Text(detail.profile.displayName).forgeTitle()
      Text("@\(detail.profile.handle)").forgeLabel()
      if !detail.profile.bio.isEmpty {
        Text(detail.profile.bio).forgeBody().multilineTextAlignment(.center)
      }
      MetricGrid(items: [
        MetricItem(String(localized: "Sessions posted"), "\(detail.stats.sessions)", color: Theme.accentValue),
        MetricItem(String(localized: "Week streak"), "\(detail.stats.streakWeeks)", unit: "wk"),
      ])
      if detail.following {
        Button {
          Task { await toggleFollow() }
        } label: {
          if busy {
            ProgressView().tint(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 52)
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
            ProgressView().tint(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 52)
          } else {
            Text("Follow")
          }
        }
        .buttonStyle(PillButtonStyle())
      }
    }
    .frame(maxWidth: .infinity)
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
    if ok {
      self.detail?.following.toggle()
      if self.detail?.following == true, let page = await SocialClient.shared.feed() {
        posts = page.posts.filter { $0.user.id == detail.profile.userId }
      }
    }
  }
}
