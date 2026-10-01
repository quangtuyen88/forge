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
    NavigationStack {
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
      .navigationBarTitleDisplayMode(.large)
      .sheet(isPresented: $showSignIn) { AccountView() }
      .sheet(isPresented: $showInvite) {
        NavigationStack {
          VStack(alignment: .leading, spacing: 10) {
            ReferralView()
          }
          .padding(.horizontal, Theme.margin)
          .padding(.top, 24)
          .navigationTitle("Invite friends")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { showInvite = false } }
          }
        }
        .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showEdit) {
        if let profile {
          HandleSetupCard(
            existing: profile, onSave: { updated in self.profile = updated }, asSheet: true)
        }
      }
      .task(id: auth.user?.id) {
        guard auth.user != nil else { checking = false; return }
        await loadProfile()
      }
    }
  }

  private func loadProfile() async {
    do {
      profile = try await SocialClient.shared.profile()
      loadError = nil
    } catch {
      if Task.isCancelled || SocialClient.isCancellation(error) { return }
      profile = nil
      let message = (error as? SocialError)?.errorDescription ?? error.localizedDescription
      loadError = message == "profile not found" ? nil : message
    }
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
    VStack(alignment: .leading, spacing: Theme.groupGap) {
      signInCard
      exampleCard
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
  }

  private var signInCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: "person.2.fill")
        .scaledSystemFont(28, weight: .semibold)
        .foregroundStyle(Theme.accent)
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
  }

  private var exampleCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Example").forgeCaption()
      VStack(alignment: .leading, spacing: 14) {
        exampleRow(String(localized: "You", bundle: L10n.bundle), progress: 0.7)
        exampleRow(String(localized: "Sam", bundle: L10n.bundle), progress: 1.0)
        exampleRow(String(localized: "Jo", bundle: L10n.bundle), progress: 0.4)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Example: see your crew's weekly rings")
  }

  private func exampleRow(_ name: String, progress: Double) -> some View {
    HStack(spacing: 12) {
      AvatarInitial(handle: name, size: 32)
      Text(name).forgeBodyStrong()
      Spacer()
      RingView(progress: progress, lineWidth: 8, color: Theme.accentValue)
        .frame(width: 40, height: 40)
    }
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
  @State private var loadFailed = false
  @State private var findHandle = ""
  @State private var found: CrewUserDetail?
  @State private var findError: String?
  @AppStorage(CrewBlocklist.key) private var blockedHandles = ""

  private var visiblePosts: [Post] {
    posts.filter { !CrewBlocklist.contains($0.user.handle, in: blockedHandles) }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.inner) {
        if visiblePosts.isEmpty && loadFailed {
          CrewErrorCard(title: String(localized: "Couldn't load your crew.", bundle: L10n.bundle)) {
            Task { await load(reset: true) }
          }
        } else if visiblePosts.isEmpty && loaded && nextCursor == nil {
          emptyState
        } else {
          ForEach(visiblePosts) { post in
            PostCardView(post: post)
          }
          if loadFailed {
            Button {
              Task { await loadMore() }
            } label: {
              HStack(spacing: 6) {
                Text(String(localized: "Couldn't load more", bundle: L10n.bundle)).forgeLabel()
                Text(String(localized: "Try again", bundle: L10n.bundle)).forgeLabel()
                  .foregroundStyle(Theme.accentText)
              }
              .frame(maxWidth: .infinity, minHeight: 44)
              .contentShape(Rectangle())
            }
            .foregroundStyle(Theme.textSecondary)
            .buttonStyle(RowPressStyle())
          } else if nextCursor != nil {
            Button {
              Task { await loadMore() }
            } label: {
              if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
              } else {
                Text("Load more").forgeBodyStrong().frame(maxWidth: .infinity, minHeight: 44)
              }
            }
            .foregroundStyle(Theme.accentText)
            .buttonStyle(RowPressStyle())
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
        .scaledSystemFont(22, weight: .semibold)
        .foregroundStyle(Theme.accent)
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
        Button {
          find()
        } label: {
          Text("Find")
            .foregroundStyle(Theme.accentText)
            .forgeBodyStrong()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
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
      do {
        found = try await SocialClient.shared.user(handle: handle)
      } catch {
        findError = (error as? SocialError)?.errorDescription ?? String(localized: "No one with that handle", bundle: L10n.bundle)
      }
    }
  }

  private func load(reset: Bool) async {
    loading = true
    defer { loading = false }
    do {
      let page = try await SocialClient.shared.feed(cursor: reset ? nil : nextCursor)
      if reset { posts = page.posts } else { posts += page.posts }
      nextCursor = page.nextCursor
      loadFailed = false
    } catch {
      // Cancellation is no result: keep everything, leave the first load not done.
      if Task.isCancelled || SocialClient.isCancellation(error) { return }
      loadFailed = true
    }
    loaded = true
  }

  private func loadMore() async {
    await load(reset: false)
  }
}

private struct CrewErrorCard: View {
  let title: String
  var message: String? = nil
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).forgeTitle()
      if let message {
        Text(message).forgeLabel()
      }
      Button("Try again") { retry() }
        .buttonStyle(PillSecondaryButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
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
  @State private var failed = false
  @State private var sort: RingSort = .sessions
  @AppStorage(CrewBlocklist.key) private var blockedHandles = ""
  private enum RingSort: String, CaseIterable {
    case sessions = "Sessions", tonnage = "Tonnage", name = "Name"
    var label: String {
      switch self {
      case .sessions: return String(localized: "Sessions", bundle: L10n.bundle)
      case .tonnage: return String(localized: "Tonnage", bundle: L10n.bundle)
      case .name: return String(localized: "Name", bundle: L10n.bundle)
      }
    }
  }

  private var target: Int { max(profiles.first?.daysPerWeek ?? 3, 1) }

  private var weekLabel: String {
    weekOffset == 0 ? String(localized: "This week", bundle: L10n.bundle) : weekOffset == -1 ? String(localized: "Last week", bundle: L10n.bundle) : isoWeek(offset: weekOffset)
  }

  private var weekRangeText: String {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let shifted = cal.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
    guard let week = cal.dateInterval(of: .weekOfYear, for: shifted) else { return "" }
    return "\(week.start.formatted(.dateTime.weekday(.abbreviated).day().locale(L10n.locale))) – \(week.end.addingTimeInterval(-1).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale)))"
  }

  private var sortedRows: [LeaderRow] {
    guard let rows else { return [] }
    switch sort {
    case .sessions: return rows.sorted { ($0.sessions, $0.tonnageKg) > ($1.sessions, $1.tonnageKg) }
    case .tonnage: return rows.sorted { $0.tonnageKg > $1.tonnageKg }
    case .name: return rows.sorted { ($0.handle ?? "") < ($1.handle ?? "") }
    }
  }

  private var visibleRows: [LeaderRow] {
    sortedRows.filter { !CrewBlocklist.contains($0.handle, in: blockedHandles) }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        HStack {
          Button { weekOffset -= 1 } label: {
            Image(systemName: "chevron.backward").frame(width: 40, height: 40)
          }
          .buttonStyle(IconButtonStyle())
          .accessibilityLabel("Previous week")
          Spacer()
          Text(weekLabel).forgeBodyStrong()
          Spacer()
          Button { weekOffset = min(0, weekOffset + 1) } label: {
            Image(systemName: "chevron.forward").frame(width: 40, height: 40)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(weekOffset >= 0)
          .accessibilityLabel("Next week")
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
              Image(systemName: "chevron.up.chevron.down").scaledSystemFont(11, weight: .semibold)
            }
            .foregroundStyle(Theme.accentText)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
          }
        }
        if failed {
          CrewErrorCard(title: String(localized: "Couldn't load your crew.", bundle: L10n.bundle)) {
            rows = nil
            failed = false
            Task { await loadRows() }
          }
        } else if let rows {
          if rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Image(systemName: "person.2.fill").scaledSystemFont(22, weight: .semibold).foregroundStyle(Theme.accent).frame(width: 48, height: 48).background(Circle().fill(Theme.accentTint))
              Text("No sessions this week yet").forgeSection()
              Text("Rings fill as your crew logs. Yours counts too.").forgeLabel()
              Button("Invite a friend") { showInvite = true }.buttonStyle(PillSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
          } else {
            ForEach(visibleRows) { row in
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
      await loadRows()
    }
  }

  private func loadRows() async {
    do {
      rows = try await SocialClient.shared.leaderboard(week: isoWeek(offset: weekOffset))
      failed = false
    } catch {
      if Task.isCancelled || SocialClient.isCancellation(error) { return }
      rows = nil
      failed = true
    }
  }

  private func ringRow(_ row: LeaderRow) -> some View {
    let isSelf = row.userId == auth.user?.id
    return HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          AvatarInitial(handle: row.handle, size: 32)
          Text(isSelf ? String(localized: "you", bundle: L10n.bundle) : (row.handle ?? "—")).forgeBodyStrong()
          if isSelf { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
        }
        MetricValue(value: "\(row.sessions)/\(target)", unit: String(localized: "sessions", bundle: L10n.bundle), size: 30, color: Theme.accentValue)
        MetricValue(value: Fmt.grouped(row.tonnageKg), unit: "kg", size: 15, color: Theme.textSecondary, unitColor: Theme.textTertiary)
      }
      Spacer()
      RingView(progress: Double(row.sessions) / Double(target), lineWidth: 10, color: row.sessions >= target ? Theme.positive : Theme.accentValue, accessibilityLabel: String(localized: "\(row.sessions) of \(target) sessions", bundle: L10n.bundle))
        .frame(width: 84, height: 84)
    }
    .card()
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(isSelf ? Theme.accent : .clear, lineWidth: 1.5))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(ringRowLabel(row, isSelf: isSelf))
  }

  private func ringRowLabel(_ row: LeaderRow, isSelf: Bool) -> String {
    let name = isSelf ? String(localized: "You", bundle: L10n.bundle) : (row.handle ?? String(localized: "Someone", bundle: L10n.bundle))
    if row.sessions >= target {
      return String(localized: "\(name), \(row.sessions) of \(target) sessions, goal reached, \(Fmt.grouped(row.tonnageKg)) kilograms", bundle: L10n.bundle)
    }
    return String(localized: "\(name), \(row.sessions) of \(target) sessions, \(Fmt.grouped(row.tonnageKg)) kilograms", bundle: L10n.bundle)
  }
}

// MARK: - Me

private struct MeTab: View {
  let profile: CrewProfile
  @Binding var showInvite: Bool
  @Binding var showEdit: Bool
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @AppStorage(CrewBlocklist.key) private var blockedHandles = ""
  @State private var stats: CrewStats?
  @Query private var sessions: [WorkoutSession]

  /// Trusted sets the lifter's own feedback keeps out of the Crew scope — shown, never deleted.
  private var crewExcludedSets: Int { sessions.excludedSetCount(.crew) }

  private var blocked: [String] { CrewBlocklist.parse(blockedHandles).sorted() }

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
            Button {
              showEdit = true
            } label: {
              Text("Edit")
                .foregroundStyle(Theme.accentText)
                .forgeBodyStrong()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
          }
          if !profile.bio.isEmpty {
            Text(profile.bio).forgeBody()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        if let stats {
          HStack(spacing: 10) {
            StatTile(symbol: "dumbbell.fill", value: "\(stats.sessions)", label: String(localized: "sessions posted", bundle: L10n.bundle), tint: Theme.accentValue)
            StatTile(symbol: "flame.fill", value: "\(stats.streakWeeks)", unit: "wk", label: String(localized: "Streak", bundle: L10n.bundle))
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

        if crewExcludedSets > 0 {
          VStack(alignment: .leading, spacing: 8) {
            Text("Left out of Crew").forgeSection()
            Text(String(
              localized: "\(crewExcludedSets) set\(L10n.pluralSuffix(crewExcludedSets)) you marked as cut short or uncomfortable are not counted as eligible work, so they are not posted as records. Your logged sets stay in History.",
              bundle: L10n.bundle))
              .forgeBody()
              .fixedSize(horizontal: false, vertical: true)
            Text("This only affects Crew. Adherence, readiness and your program read the same sets as before.")
              .forgeCaption()
              .foregroundStyle(Theme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }

        Button { showInvite = true } label: {
          HStack {
            Image(systemName: "person.badge.plus")
              .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
              Text("Invite a friend").forgeBodyStrong()
              Text("Give a month, get a month").forgeLabel()
            }
            Spacer()
            Image(systemName: "chevron.forward").foregroundStyle(Theme.textTertiary)
          }
          .frame(minHeight: 52)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .card()

        if !blocked.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            Text("Blocked people").forgeSection().padding(.bottom, 10)
            ForEach(blocked, id: \.self) { handle in
              HStack {
                Text("@\(handle)").forgeBody()
                Spacer()
                Button {
                  blockedHandles = CrewBlocklist.removing(handle, from: blockedHandles)
                } label: {
                  Text("Unblock")
                    .foregroundStyle(Theme.accentText)
                    .forgeBodyStrong()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
              }
              .frame(minHeight: 44)
              if handle != blocked.last { Divider().overlay(Theme.ring) }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }

        VStack(alignment: .leading, spacing: 0) {
          Text("Auto-post").forgeSection().padding(.bottom, 10)
          HStack {
            Text("Finished workouts").forgeBody()
            Spacer()
            Text(autoPostWorkouts ? String(localized: "On", bundle: L10n.bundle) : String(localized: "Off", bundle: L10n.bundle)).forgeLabel()
          }
          .frame(minHeight: 36)
          Divider().overlay(Theme.ring)
          HStack {
            Text("New PRs").forgeBody()
            Spacer()
            Text(autoPostPRs ? String(localized: "On", bundle: L10n.bundle) : String(localized: "Off", bundle: L10n.bundle)).forgeLabel()
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
      do {
        stats = try await SocialClient.shared.user(handle: profile.handle).stats
      } catch {
        stats = nil
      }
    }
  }
}

// MARK: - Handle setup / edit

struct HandleSetupCard: View {
  let existing: CrewProfile?
  let onSave: (CrewProfile) -> Void
  var asSheet: Bool = false
  @State private var handle = ""
  @State private var displayName = ""
  @State private var bio = ""
  @State private var saving = false
  @State private var error: String?
  @State private var showDiscard = false
  @Environment(\.dismiss) private var dismiss

  private var isDirty: Bool {
    if let existing {
      return handle != existing.handle || displayName != existing.displayName || bio != existing.bio
    }
    return !handle.isEmpty || !displayName.isEmpty || !bio.isEmpty
  }

  var body: some View {
    Group {
      if asSheet {
        NavigationStack {
          form
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
            }
        }
      } else {
        form
      }
    }
    .interactiveDismissDisabled(asSheet && isDirty)
    .confirmationDialog("Discard changes?", isPresented: $showDiscard, titleVisibility: .visible) {
      Button("Discard changes", role: .destructive) { dismiss() }
    } message: {
      Text("Your edits won't be saved.")
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(existing == nil ? String(localized: "Pick a handle", bundle: L10n.bundle) : String(localized: "Edit profile", bundle: L10n.bundle)).forgeTitle()
      Text("Your handle is how friends find you in the crew.").forgeLabel()
      TextField("Handle (a-z, 0-9, _)", text: $handle)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textContentType(.username)
        .keyboardType(.asciiCapable)
        .accessibilityLabel("Handle")
        .forgeBody()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
      TextField("Display name", text: $displayName)
        .accessibilityLabel("Display name")
        .forgeBody()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
      TextField("Bio (optional)", text: $bio, axis: .vertical)
        .lineLimit(1...3)
        .accessibilityLabel("Bio")
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
          Text(existing == nil ? String(localized: "Create profile", bundle: L10n.bundle) : String(localized: "Save", bundle: L10n.bundle))
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

  private func cancel() {
    if isDirty { showDiscard = true } else { dismiss() }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    if let updated = await SocialClient.shared.updateProfile(handle: handle, displayName: displayName, bio: bio) {
      onSave(updated)
      dismiss()
    } else {
      error = SocialClient.shared.lastError ?? String(localized: "Could not save profile", bundle: L10n.bundle)
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
  @State private var loadFailed: String?
  @State private var showUnfollow = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if let failure = loadFailed {
            CrewErrorCard(
              title: String(localized: "Couldn't load this profile.", bundle: L10n.bundle),
              message: failure
            ) {
              loadFailed = nil
              detail = nil
              posts = []
              Task { await load() }
            }
          } else if let detail {
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
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .confirmationDialog("Unfollow @\(handle)?", isPresented: $showUnfollow, titleVisibility: .visible) {
        Button("Unfollow", role: .destructive) { Task { await toggleFollow() } }
        Button("Cancel", role: .cancel) {}
      }
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
        MetricItem(String(localized: "Sessions posted", bundle: L10n.bundle), "\(detail.stats.sessions)", color: Theme.accentValue),
        MetricItem(String(localized: "Week streak", bundle: L10n.bundle), "\(detail.stats.streakWeeks)", unit: "wk"),
      ])
      if detail.following {
        Button {
          showUnfollow = true
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
    do {
      let user = try await SocialClient.shared.user(handle: handle)
      detail = user
      loadFailed = nil
      let page = try await SocialClient.shared.feed()
      posts = page.posts.filter { $0.user.id == user.profile.userId }
    } catch {
      if Task.isCancelled || SocialClient.isCancellation(error) { return }
      detail = nil
      posts = []
      loadFailed = (error as? SocialError)?.errorDescription ?? error.localizedDescription
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
      if self.detail?.following == true, let page = try? await SocialClient.shared.feed() {
        posts = page.posts.filter { $0.user.id == detail.profile.userId }
      }
    }
  }
}
