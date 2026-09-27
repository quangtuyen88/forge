import CoreImage
import CoreImage.CIFilterBuiltins
import ForgeCore
import SwiftData
import SwiftUI

// Crew on My Progress (docs/design/crew-progress/): the section under Consistency, the
// "Your crew" week screen its footer opens, and the invite sheet. Data comes from
// CrewStore (the social crew snapshot plus the lifter's local week); avatars, day stamps,
// kudos and record tokens come from CrewComponents. Nothing here touches the network
// beyond CrewStore/SocialClient calls.

// MARK: - My Progress section

struct CrewProgressSection: View {
  let usesLb: Bool

  @Environment(AuthClient.self) private var auth
  @Query private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @State private var showInvite = false
  @State private var showSignIn = false

  private var selfWeek: CrewSelfWeek {
    CrewSelfWeek.make(sessions: sessions, target: profiles.first?.daysPerWeek ?? 3)
  }

  /// Fixture runs get the mock snapshot on the very first frame too, so the card never flashes in.
  private var displaySnapshot: CrewSnapshot? {
    #if DEBUG
    if CrewStore.shared.isFixture, CrewStore.shared.snapshot == nil { return CrewFixture.snapshot() }
    #endif
    return CrewStore.shared.snapshot
  }

  var body: some View {
    let store = CrewStore.shared
    let snapshot = displaySnapshot
    let showsCrew = store.isFixture || (auth.user != nil && snapshot?.hasCrew == true)
    let showsInvite = !store.isFixture && (auth.user == nil || snapshot != nil)
    // An always-present container, not a Group: a Group that renders empty in the loading
    // state would never run the refresh task or mount the sign-in/invite sheets.
    return VStack(alignment: .leading, spacing: 0) {
      if showsCrew, let snapshot {
        crewCardView(snapshot)
      } else if showsInvite {
        inviteCardView
      }
    }
    .task(id: auth.user?.id) { await CrewStore.shared.refresh(selfWeek: selfWeek) }
    .sheet(isPresented: $showInvite) { CrewInviteSheet() }
    .sheet(isPresented: $showSignIn) { AccountView() }
  }

  // MARK: Crew card (mock 03)

  private func crewCardView(_ snapshot: CrewSnapshot) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Crew this week").forgeSection()
        Spacer()
        if snapshot.streakWeeks > 0 {
          SkyPill(
            String(localized: "\(snapshot.streakWeeks)-week streak", bundle: L10n.bundle),
            symbol: "flame.fill", style: .orange)
        }
      }
      SkyCard {
        VStack(alignment: .leading, spacing: 14) {
          Text("Sessions together")
            .forge(15, .semibold)
            .foregroundStyle(Theme.textSecondary)
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(snapshot.sessionsTogether)")
              .forge(56, .bold)
              .foregroundStyle(Theme.accent)
              .monospacedDigit()
              .accessibilityIdentifier("crew.together")
            Text("of \(snapshot.plannedTogether)")
              .forge(20, .semibold)
              .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if snapshot.toGo > 0 {
              Text("\(snapshot.toGo) to go by Sunday")
                .forge(15)
                .foregroundStyle(Theme.textSecondary)
            } else {
              Text("Everyone's done this week")
                .forge(15, .semibold)
                .foregroundStyle(Theme.positiveText)
            }
          }
          ringsRow(snapshot)
          if let record = snapshot.recordsByOthers.first {
            Divider()
            recordRow(record)
          }
          if !CrewStore.shared.isFixture && !autoPostWorkouts {
            shareGateRow
          }
        }
      } footer: {
        NavigationLink {
          CrewWeekView(usesLb: usesLb)
        } label: {
          FooterStrip(
            symbol: "person.2.fill", title: "Your crew", detail: "\(snapshot.members.count)")
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("crew.open")
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("crew.card")
    }
  }

  /// Self first, then the first four others (members order), one ring each.
  private func ringsRow(_ snapshot: CrewSnapshot) -> some View {
    let members = snapshot.members.filter(\.isSelf) + Array(snapshot.others.prefix(4))
    return HStack(alignment: .top, spacing: 8) {
      ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
        ringColumn(member, index: index)
      }
    }
  }

  private func ringColumn(_ member: CrewMember, index: Int) -> some View {
    let name = member.isSelf ? String(localized: "You", bundle: L10n.bundle) : member.name
    return VStack(spacing: 6) {
      CrewRingAvatar(
        initial: member.initial,
        isYou: member.isSelf,
        done: member.done,
        target: member.target,
        delay: Double(index) * 0.07)
      Text(name)
        .forge(15, member.isSelf ? .semibold : .regular)
        .foregroundStyle(member.isSelf ? Theme.text : Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text("\(member.done)/\(member.target)")
        .forge(15, .semibold)
        .monospacedDigit()
        .foregroundStyle(member.isComplete ? Theme.positiveText : Theme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(member.done) of \(member.target) sessions")
  }

  private func recordRow(_ record: CrewRecord) -> some View {
    let name = record.displayName ?? record.handle ?? "—"
    return HStack(spacing: 12) {
      CrewRecordToken(
        exercise: record.exerciseId.flatMap(ExerciseDB.find),
        size: 56,
        ownerInitial: String(name.prefix(1)),
        ownerIsYou: false)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(name) set a \(record.exerciseName) record")
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(2)
        Text(verbatim: recordSetLine(record))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      Spacer(minLength: 8)
      KudosButton(sent: record.kudoed, style: .onCard) {
        Task { await CrewStore.shared.toggleKudos(record) }
      }
      .accessibilityIdentifier("crew.record.kudos")
    }
  }

  /// "160 kg × 3 · Sat" in the lifter's unit; an estimated max when the set is unknown.
  private func recordSetLine(_ record: CrewRecord) -> String {
    let isLbUnit = unitIsLb(record.exerciseId)
    let unit = isLbUnit ? "lb" : "kg"
    let weekday = weekdayShort(record.date)
    if let weightKg = record.weightKg, let reps = record.reps {
      let weight = isLbUnit ? Plates.kgToLb(weightKg) : weightKg
      return "\(Fmt.num(weight)) \(unit) × \(reps) · \(weekday)"
    }
    let e1rm = isLbUnit ? Plates.kgToLb(record.e1rm) : record.e1rm
    return String(localized: "Estimated max \(Fmt.num(e1rm)) \(unit) · \(weekday)", bundle: L10n.bundle)
  }

  private func weekdayShort(_ day: String) -> String {
    guard let date = CrewWeek.date(from: day) else { return day }
    return date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
  }

  private func unitIsLb(_ exerciseId: String?) -> Bool {
    guard let exerciseId else { return usesLb }
    return profiles.first?.isLb(for: exerciseId) ?? usesLb
  }

  /// Sharing is off while a crew exists: say so quietly, offer the one-tap fix.
  private var shareGateRow: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
      Text("Your crew can't see your sessions yet")
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
      Spacer(minLength: 8)
      Button {
        autoPostWorkouts = true
        autoPostPRs = true
      } label: {
        Text("Share them")
          .frame(minHeight: 44)
      }
      .buttonStyle(TodayButtonStyle(kind: .secondary, compact: true))
    }
  }

  // MARK: Invite card (mock 01)

  private var inviteCardView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your crew").forgeSection()
      SkyCard {
        VStack(alignment: .leading, spacing: 12) {
          previewRow
          Text("Train with your crew")
            .forge(22, .bold)
            .foregroundStyle(Theme.text)
          Text("See each other's week, cheer new records and compare lift trends.")
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
          Button {
            invite()
          } label: {
            Label("Invite your crew", systemImage: "person.badge.plus")
          }
          .buttonStyle(PillButtonStyle(minHeight: 50))
          .accessibilityIdentifier("crew.invite")
          Label(
            autoPostWorkouts
              ? String(localized: "People who follow you see your sessions and records.", bundle: L10n.bundle)
              : String(localized: "Nothing is shared until you turn sharing on.", bundle: L10n.bundle),
            systemImage: autoPostWorkouts ? "person.2.fill" : "lock.fill")
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
      }
    }
  }

  /// Five quiet skeleton columns; decorative, so it stays out of VoiceOver.
  private var previewRow: some View {
    HStack(alignment: .top, spacing: 8) {
      ForEach(0..<5, id: \.self) { _ in
        VStack(spacing: 6) {
          ZStack {
            Circle().strokeBorder(Theme.track, lineWidth: 4)
            Circle()
              .trim(from: 0, to: 0.2)
              .stroke(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Circle().fill(Theme.track).frame(width: 40, height: 40)
          }
          .frame(width: 52, height: 52)
          Capsule().fill(Theme.track).frame(width: 36, height: 8)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .accessibilityHidden(true)
  }

  private func invite() {
    if auth.user == nil {
      showSignIn = true
    } else {
      showInvite = true
    }
  }
}

// MARK: - "Your crew" week screen (mock 04)

struct CrewWeekView: View {
  /// Fixed stamp column so the day-letter header lines up with every member's stamps.
  private static let stampColumn: CGFloat = 22
  private static let stampSpacing: CGFloat = 3
  private static let ringSize: CGFloat = 44
  private static let stampRowLeading: CGFloat = 54  // ring avatar (44) + row spacing (10)

  let usesLb: Bool
  @Query private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @State private var showInvite = false

  /// Computed per render, never cached: the letters must follow an in-app language switch.
  private var dayLetterSymbols: [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = L10n.locale
    return calendar.veryShortWeekdaySymbols
  }

  private var selfWeek: CrewSelfWeek {
    CrewSelfWeek.make(sessions: sessions, target: profiles.first?.daysPerWeek ?? 3)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let snapshot = CrewStore.shared.snapshot {
          weekCard(snapshot)
          if !snapshot.records.isEmpty {
            recordsShelf(snapshot)
          }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .navigationTitle("Your crew")
    .toolbarBackground(.hidden, for: .navigationBar)
    .modifier(CrewWeekSubtitle(text: subtitle))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showInvite = true
        } label: {
          Image(systemName: "person.badge.plus")
        }
        .accessibilityLabel("Invite your crew")
      }
    }
    .sheet(isPresented: $showInvite) { CrewInviteSheet() }
    .task { await CrewStore.shared.refresh(selfWeek: selfWeek) }
    .refreshable { await CrewStore.shared.refresh(selfWeek: selfWeek) }
  }

  private var subtitle: String? {
    guard let snapshot = CrewStore.shared.snapshot else { return nil }
    return String(
      localized: "\(weekRange(snapshot)) · \(snapshot.sessionsTogether) of \(snapshot.plannedTogether) sessions",
      bundle: L10n.bundle)
  }

  /// "Sep 21 – 27": the snapshot week, localized.
  private func weekRange(_ snapshot: CrewSnapshot) -> String {
    guard let start = CrewWeek.date(from: snapshot.weekStart) else { return snapshot.weekStart }
    let end = CrewWeek.calendar.date(byAdding: .day, value: 6, to: start) ?? start
    return start.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
      + " – " + end.formatted(.dateTime.day().locale(L10n.locale))
  }

  private func weekDays(_ snapshot: CrewSnapshot) -> [Date] {
    if let start = CrewWeek.date(from: snapshot.weekStart) {
      return CrewWeek.days(ofWeekStarting: start)
    }
    return CrewWeek.days(ofWeekStarting: CrewWeek.start(for: .now))
  }

  private func weekCard(_ snapshot: CrewSnapshot) -> some View {
    let days = weekDays(snapshot)
    return SkyCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("This week").forge(17, .semibold)
          Spacer()
          if snapshot.streakWeeks > 0 {
            SkyPill(
              String(localized: "\(snapshot.streakWeeks)-week streak", bundle: L10n.bundle),
              symbol: "flame.fill", style: .orange)
          }
        }
        VStack(spacing: 0) {
          dayHeader(days)
            .padding(.bottom, 10)
          ForEach(Array(snapshot.members.enumerated()), id: \.element.id) { index, member in
            if index > 0 {
              Divider().padding(.leading, Self.stampRowLeading)
            }
            memberRow(member, days: days)
          }
          Text(
            snapshot.toGo > 0
              ? String(localized: "\(snapshot.toGo) to go by Sunday", bundle: L10n.bundle)
              : String(localized: "Everyone's done this week", bundle: L10n.bundle)
          )
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("crew.week")
  }

  /// Day letters over the stamp columns; today's letter carries the accent.
  private func dayHeader(_ days: [Date]) -> some View {
    let todayIndex = days.firstIndex { CrewWeek.calendar.isDate($0, inSameDayAs: .now) }
    return HStack(spacing: Self.stampSpacing) {
      Spacer(minLength: 0)
      ForEach(days.indices, id: \.self) { index in
        Text(dayLetterSymbols[CrewWeek.calendar.component(.weekday, from: days[index]) - 1])
          .forge(13, .semibold)
          .foregroundStyle(index == todayIndex ? Theme.accent : Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(width: Self.stampColumn)
      }
    }
  }

  private func memberRow(_ member: CrewMember, days: [Date]) -> some View {
    HStack(spacing: 10) {
      CrewRingAvatar(
        initial: member.initial, isYou: member.isSelf, done: member.done, target: member.target,
        size: Self.ringSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(member.isSelf ? String(localized: "You", bundle: L10n.bundle) : member.name)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text("\(member.sessions) of \(member.target)")
          .forge(15)
          .monospacedDigit()
          .lineLimit(1)
          .foregroundStyle(member.isComplete ? Theme.positiveText : Theme.textSecondary)
      }
      .layoutPriority(1)
      Spacer(minLength: 6)
      HStack(spacing: Self.stampSpacing) {
        ForEach(days.indices, id: \.self) { index in
          CrewDayStamp(state: stampState(member, day: days[index]), size: Self.stampColumn)
            .frame(width: Self.stampColumn)
        }
      }
    }
    .frame(minHeight: 56)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(memberSummary(member))
  }

  private func stampState(_ member: CrewMember, day: Date) -> CrewDayStamp.State {
    if member.days.contains(CrewWeek.dayString(day)) { return .trained }
    if CrewWeek.calendar.isDate(day, inSameDayAs: .now) { return .today }
    return day < .now ? .rest : .future
  }

  private func memberSummary(_ member: CrewMember) -> String {
    let trained = member.days
      .compactMap { CrewWeek.date(from: $0)?.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale)) }
      .joined(separator: ", ")
    if trained.isEmpty {
      return String(
        localized: "\(member.name), \(member.sessions) of \(member.target) sessions", bundle: L10n.bundle)
    }
    return String(
      localized: "\(member.name), \(member.sessions) of \(member.target) sessions, trained \(trained)",
      bundle: L10n.bundle)
  }

  // MARK: Records shelf

  private func recordsShelf(_ snapshot: CrewSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Records this week").forgeSection()
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(snapshot.records) { record in
            recordCell(record)
          }
        }
        .padding(.horizontal, Theme.margin)
      }
      .padding(.horizontal, -Theme.margin)
    }
  }

  private func recordCell(_ record: CrewRecord) -> some View {
    let name = record.displayName ?? record.handle ?? "—"
    let isLbUnit = unitIsLb(record.exerciseId)
    let unit = isLbUnit ? "lb" : "kg"
    let setLine: String
    if let weightKg = record.weightKg, let reps = record.reps {
      let weight = isLbUnit ? Plates.kgToLb(weightKg) : weightKg
      setLine = "\(Fmt.num(weight)) \(unit) × \(reps)"
    } else {
      let e1rm = isLbUnit ? Plates.kgToLb(record.e1rm) : record.e1rm
      setLine = String(localized: "Estimated max \(Fmt.num(e1rm)) \(unit)", bundle: L10n.bundle)
    }
    return VStack(spacing: 6) {
      CrewRecordToken(
        exercise: record.exerciseId.flatMap(ExerciseDB.find),
        size: 76,
        ownerInitial: String(name.prefix(1)),
        ownerIsYou: record.isSelf,
        onSky: true)
      Text(record.exerciseName)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .lineLimit(2, reservesSpace: true)
        .multilineTextAlignment(.center)
      Text(verbatim: "\(name) · \(setLine)")
        .forge(13)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
      if record.isSelf {
        Label("\(record.kudos) kudos", systemImage: "hands.clap.fill")
          .forge(13, .semibold)
          .foregroundStyle(Theme.textSecondary)
      } else {
        KudosButton(sent: record.kudoed, style: .onPage) {
          Task { await CrewStore.shared.toggleKudos(record) }
        }
      }
    }
    .frame(width: 116)
    .accessibilityIdentifier("crew.week.record.\(record.id)")
  }

  private func unitIsLb(_ exerciseId: String?) -> Bool {
    guard let exerciseId else { return usesLb }
    return profiles.first?.isLb(for: exerciseId) ?? usesLb
  }
}

/// The week range line under the title; `navigationSubtitle` exists from iOS 26.
private struct CrewWeekSubtitle: ViewModifier {
  let text: String?

  func body(content: Content) -> some View {
    if #available(iOS 26, *), let text {
      content.navigationSubtitle(text)
    } else {
      content
    }
  }
}

// MARK: - Invite sheet (mock 02)

struct CrewInviteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @State private var profile: CrewProfile?
  @State private var loading = true
  @State private var loadError: String?
  @State private var qrImage: UIImage?

  var body: some View {
    Group {
      if loading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let profile {
        inviteContent(profile)
      } else if let loadError {
        errorView(loadError)
      } else {
        HandleSetupCard(existing: nil, dismissOnSave: false) { profile = $0 }
      }
    }
    .presentationDetents([.fraction(0.8), .large])
    .presentationDragIndicator(.visible)
    .task { await load() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("crew.invite.sheet")
  }

  private func load() async {
    loading = true
    // Fixture runs show the QR without a server: use the fixture self member's handle.
    #if DEBUG
      if CrewStore.shared.isFixture,
        let selfMember = CrewFixture.snapshot().members.first(where: \.isSelf)
      {
        profile = CrewProfile(
          userId: selfMember.userId,
          handle: selfMember.handle ?? "an_lifts",
          displayName: selfMember.displayName ?? "An",
          bio: "")
        loading = false
        return
      }
    #endif
    profile = await SocialClient.shared.profile()
    // "profile not found" is the handle-setup step (same check as CrewView); anything else is
    // a failure worth retrying, and the handle form must never show for it (a PUT would
    // replace an existing handle).
    loadError = profile == nil && SocialClient.shared.lastError != "profile not found"
      ? SocialClient.shared.lastError ?? String(localized: "Crew is unreachable", bundle: L10n.bundle) : nil
    loading = false
  }

  /// A load that failed some other way: the error and a retry, never the handle form.
  private func errorView(_ message: String) -> some View {
    VStack(spacing: 12) {
      Text(message)
        .forgeLabel()
        .multilineTextAlignment(.center)
      Button("Try again") { Task { await load() } }
        .buttonStyle(PillSecondaryButtonStyle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, Theme.margin)
  }

  private func inviteContent(_ profile: CrewProfile) -> some View {
    let url = inviteURL(profile)
    return ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("Invite your crew")
            .forge(22, .bold)
            .foregroundStyle(Theme.text)
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.text)
          }
          .buttonStyle(IconButtonStyle())
          .accessibilityLabel("Close")
        }
        qrTile(handle: profile.handle)
          .frame(maxWidth: .infinity)
        VStack(spacing: 4) {
          Text("@\(profile.handle)")
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
          Text("Friends scan this with their iPhone camera.")
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        Text("What people who follow you see")
          .forge(15, .semibold)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 2)
        seesRow(symbol: "calendar", color: Theme.accent, text: "Sessions and streaks")
        seesRow(symbol: "trophy.fill", color: Theme.recordRing, text: "Records and lift trends")
        seesRow(symbol: "lock.fill", color: Theme.accent, text: "Not shared: check-ins, notes, coach chats")
        Toggle(isOn: Binding(
          get: { autoPostWorkouts },
          set: { on in
            autoPostWorkouts = on
            autoPostPRs = on
          })) {
          Text("Share my sessions and records")
        }
        .toggleStyle(.switch)
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .accessibilityIdentifier("crew.share.toggle")
        if let url {
          ShareLink(item: url, message: Text("Train with me on Regulift")) {
            Label("Share invite link", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(PillButtonStyle())
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 14)
      .padding(.bottom, 32)
    }
  }

  /// 44 pt row: 30 pt icon badge (8 pt rounded square, symbol color at 14 % fill, DESIGN §5).
  private func seesRow(symbol: String, color: Color, text: LocalizedStringKey) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 30, height: 30)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(color.opacity(0.14)))
      Text(text)
        .forge(15)
        .foregroundStyle(Theme.text)
      Spacer(minLength: 0)
    }
    .frame(minHeight: 44)
  }

  /// The white tile keeps the QR black-on-white so it scans in dark mode too.
  private func qrTile(handle: String) -> some View {
    Group {
      if let qrImage {
        Image(uiImage: qrImage)
          .interpolation(.none)
          .resizable()
      } else {
        Color.white
      }
    }
    .frame(width: 176, height: 176)
    // Inside the tile: the white margin is the QR quiet zone.
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white)
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.ring, lineWidth: 1)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("QR code to follow @\(handle)")
    .task(id: handle) { generateQR(for: "\(invitePathBase())/c/\(handle)") }
  }

  private func inviteURL(_ profile: CrewProfile) -> URL? {
    URL(string: "\(invitePathBase())/c/\(profile.handle)")
  }

  private func invitePathBase() -> String {
    var base = ForgeAPI.baseURL
    while base.hasSuffix("/") { base.removeLast() }
    return base
  }

  private func generateQR(for string: String) {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return }
    let white = CIImage(color: CIColor.white).cropped(to: output.extent)
    let combined = output.composited(over: white)
    let scale = max(1, ((176.0 * displayScale) / combined.extent.width).rounded(.up))
    let scaled = combined.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return }
    qrImage = UIImage(cgImage: cgImage)
  }
}
