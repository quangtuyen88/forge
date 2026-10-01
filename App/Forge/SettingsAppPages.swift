import ForgeCore
import StoreKit
import SwiftData
import SwiftUI
import UserNotifications

/// Deletes the training data this device holds; shared by Your data and Delete account.
enum TrainingDataWipe {
  /// Journey overrides and the local identity card are device-local, so a device or account wipe clears them too.
  @MainActor static func wipe(_ context: ModelContext) {
    // The JPEG files live outside the store; delete them before their rows go.
    for photo in (try? context.fetch(FetchDescriptor<ProgressPhoto>())) ?? [] {
      photo.deleteFile()
    }
    try? context.delete(model: WorkoutSession.self)
    try? context.delete(model: CheckIn.self)
    try? context.delete(model: BodyMeasurement.self)
    try? context.delete(model: ProgressPhoto.self)
    try? context.delete(model: CoachMessage.self)
    try? context.delete(model: FoodEntry.self)
    try? context.delete(model: JourneyReflection.self)
    try? context.delete(model: JourneyVisibilityOverride.self)
    try? context.delete(model: JourneyPrivateProfile.self)
  }
}

struct ReminderPage: View {
  @Bindable var profile: UserProfile
  @Environment(\.modelContext) private var modelContext
  @AppStorage(ReminderScheduler.trainingDaysKey) private var trainingDaysOnly = false
  @State private var preview: (title: String, body: String)?
  @State private var refresh = 0
  @State private var notificationsDenied = false

  private var on: Bool { profile.reminderHour != nil }
  private var hour: Int { profile.reminderHour ?? 19 }
  private var time: String { SettingsFormat.time(hour: hour, minute: profile.reminderMinute) }

  private var hero: (title: String, subtitle: String) {
    if !on {
      return (
        String(localized: "No reminder.", bundle: L10n.bundle),
        String(localized: "Turn it on for a nudge at a time you pick.", bundle: L10n.bundle)
      )
    }
    if trainingDaysOnly {
      return (
        String(localized: "\(time) on training days.", bundle: L10n.bundle),
        String(localized: "No nudge on rest days.", bundle: L10n.bundle)
      )
    }
    return (
      String(localized: "\(time) every day.", bundle: L10n.bundle),
      String(localized: "Rest days too.", bundle: L10n.bundle)
    )
  }

  private var localPreview: (title: String, body: String) {
    if trainingDaysOnly,
      let slot = ReminderSchedule.slots(
        plan: profile.weekPlan, hour: hour, minute: profile.reminderMinute, now: .now, calendar: .current
      )?.first
    {
      return (ReminderSchedule.title(for: slot), ReminderSchedule.body(for: slot))
    }
    return (
      String(localized: "Time to train", bundle: L10n.bundle),
      String(localized: "Open Regulift for today's session.", bundle: L10n.bundle)
    )
  }

  private func touch() {
    profile.updatedAt = .now
    try? modelContext.save()
  }

  private var onBinding: Binding<Bool> {
    Binding(
      get: { profile.reminderHour != nil },
      set: { isOn in
        if isOn {
          profile.reminderHour = profile.reminderHour ?? 19
          touch()
          Task {
            await Notifications.requestAuthorization()
            if await Notifications.authorizationStatus() == .denied {
              // A denial leaves nothing schedulable; the switch goes back off.
              profile.reminderHour = nil
              touch()
              notificationsDenied = true
            }
            ReminderScheduler.reschedule(profile: profile)
            refresh += 1
          }
        } else {
          profile.reminderHour = nil
          touch()
          ReminderScheduler.reschedule(profile: profile)
          preview = nil
          refresh += 1
        }
      })
  }

  private var timeBinding: Binding<Date> {
    Binding(
      get: {
        var components = DateComponents()
        components.hour = profile.reminderHour ?? 19
        components.minute = profile.reminderMinute
        return Calendar.current.date(from: components) ?? .now
      },
      set: { date in
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        profile.reminderHour = components.hour
        profile.reminderMinute = components.minute ?? 0
        touch()
        ReminderScheduler.reschedule(profile: profile)
        refresh += 1
      })
  }

  private var modeBinding: Binding<Bool> {
    Binding(
      get: { trainingDaysOnly },
      set: { trainingDays in
        trainingDaysOnly = trainingDays
        ReminderScheduler.reschedule(profile: profile)
        refresh += 1
      })
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Reminder", bundle: L10n.bundle)) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsHero(title: hero.title, subtitle: hero.subtitle, art: "art-reminder")
        if on {
          let shown = preview ?? localPreview
          NotificationPreview(title: shown.title, body: shown.body)
            .padding(.top, 6)
        }
      }
    } content: {
      Spacer().frame(height: 10)
      SettingsToggleRow(
        title: String(localized: "Remind me to train", bundle: L10n.bundle), isOn: onBinding
      )
      .accessibilityIdentifier("settings.reminder.toggle")
      if on {
        SettingsHairline(inset: false)
        SettingsRow(title: String(localized: "Time", bundle: L10n.bundle), accessory: .none) {
          DatePicker(String(localized: "Time", bundle: L10n.bundle), selection: timeBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        SettingsSectionLabel(String(localized: "Remind me on", bundle: L10n.bundle))
        Picker(String(localized: "When to remind", bundle: L10n.bundle), selection: modeBinding) {
          Text(String(localized: "Training days", bundle: L10n.bundle)).tag(true)
          Text(String(localized: "Every day", bundle: L10n.bundle)).tag(false)
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
        .accessibilityIdentifier("settings.reminder.mode")
      }
    }
    .task(id: refresh) {
      try? await Task.sleep(for: .milliseconds(400))
      preview = await Notifications.nextReminder()
    }
    .alert(
      String(localized: "Notifications are off for Regulift.", bundle: L10n.bundle),
      isPresented: $notificationsDenied
    ) {
      Button(String(localized: "Open Settings", bundle: L10n.bundle)) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    }
  }
}

struct DataPage: View {
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(AuthClient.self) private var auth
  @Environment(SyncEngine.self) private var sync
  @Environment(\.modelContext) private var modelContext
  @State private var showImport = false
  @State private var showAccount = false
  @State private var confirmDelete = false
  @State private var showExport = false
  @State private var wipeIncomplete = false

  private var n: Int { sessions.filter { $0.completed && !$0.tombstoned }.count }
  private var workouts: String {
    String(localized: "\(n) workout\(L10n.pluralSuffix(n))", bundle: L10n.bundle)
  }

  private var hero: (title: String, subtitle: String) {
    if n == 0 {
      return (
        String(localized: "No workouts yet.", bundle: L10n.bundle),
        String(localized: "Import from Strong or Hevy to bring your history.", bundle: L10n.bundle)
      )
    }
    let title = String(localized: "\(workouts) on this iPhone.", bundle: L10n.bundle)
    let subtitle =
      auth.user == nil
      ? String(localized: "Not synced yet. Sign in to keep them on every device.", bundle: L10n.bundle)
      : String(
        localized: "Synced to your account. Last sync \(SettingsFormat.relativeSync(sync.lastSync)).",
        bundle: L10n.bundle)
    return (title, subtitle)
  }

  // Same test as the delete: after an offline launch `auth.user` is still nil.
  private var deletesInAccount: Bool {
    auth.token != nil && !SyncEngine.currentOwner.isEmpty
  }

  private var deleteNote: String {
    deletesInAccount
      ? String(
        localized: "Deletes workouts, check-ins, body stats, photos and coach chats on this iPhone and in your account. This can’t be undone.",
        bundle: L10n.bundle)
      : String(
        localized: "Deletes workouts, check-ins, body stats, photos and coach chats on this iPhone. This can’t be undone.",
        bundle: L10n.bundle)
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Your data", bundle: L10n.bundle)) {
      VStack(alignment: .leading, spacing: 0) {
        SettingsHero(title: hero.title, subtitle: hero.subtitle)
        if auth.user == nil {
          Button { showAccount = true } label: {
            Text(String(localized: "Sign in", bundle: L10n.bundle))
              .forge(17, .semibold)
              .foregroundStyle(Theme.text)
              .padding(.horizontal, 20)
              .frame(minWidth: 44, minHeight: 44)
              .background(Capsule().fill(Theme.fieldChip))
              .contentShape(Rectangle())
          }
          .buttonStyle(ControlPressStyle())
          .padding(.top, 4)
        }
      }
    } content: {
      SettingsSectionLabel(String(localized: "Import and export", bundle: L10n.bundle))
      Button {
        showImport = true
      } label: {
        SettingsRow(
          title: String(localized: "Import from Strong or Hevy", bundle: L10n.bundle),
          subtitle: String(localized: "CSV export from either app", bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      SettingsHairline(inset: false)
      ShareLink(item: csvURL) {
        SettingsRow(
          title: String(localized: "Export CSV", bundle: L10n.bundle),
          subtitle: String(localized: "Every set: date, lift, weight, reps, effort", bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
      Spacer().frame(height: 36)
      Button {
        confirmDelete = true
      } label: {
        SettingsRow(
          title: String(localized: "Delete all training data", bundle: L10n.bundle),
          titleColor: Theme.negative, accessory: .none)
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("settings.data.delete")
      Text(deleteNote)
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 4)
    }
    .navigationDestination(isPresented: $showImport) {
      ImportView(showsOwnNavigationStack: false)
    }
    .navigationDestination(isPresented: $showAccount) {
      AccountView(showsOwnNavigationStack: false)
    }
    .sheet(isPresented: $showExport) { ActivityView(items: [csvURL]) }
    .confirmationDialog(
      String(localized: "Delete all training data?", bundle: L10n.bundle),
      isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button(String(localized: "Export CSV first", bundle: L10n.bundle)) { showExport = true }
      Button(String(localized: "Delete everything", bundle: L10n.bundle), role: .destructive) {
        Task { await deleteAllData() }
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        deletesInAccount
        ? String(localized: "Deletes your training data on this device and in your account.", bundle: L10n.bundle)
        : String(localized: "\(workouts) and everything logged with them leave this iPhone for good.", bundle: L10n.bundle))
    }
    // The dialog's safe action reads in ink; only the delete is red.
    .tint(Theme.text)
    .alert(
      String(localized: "Deleted from this iPhone", bundle: L10n.bundle),
      isPresented: $wipeIncomplete
    ) {
      Button(String(localized: "OK", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized: "Regulift couldn't reach your account. It removes the data there the next time it syncs.",
          bundle: L10n.bundle))
    }
  }

  private var csvURL: URL {
    let rows =
      sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map {
            "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)"
          }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func deleteAllData() async {
    let synced = deletesInAccount
    if synced {
      var rows: [(type: String, wireID: String)] = []
      for m in (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? [] {
        rows.append(("session", m.remoteID))
      }
      for m in (try? modelContext.fetch(FetchDescriptor<CheckIn>())) ?? [] {
        rows.append(("checkin", m.remoteID))
      }
      for m in (try? modelContext.fetch(FetchDescriptor<BodyMeasurement>())) ?? [] {
        rows.append(("measurement", m.remoteID))
      }
      for m in (try? modelContext.fetch(FetchDescriptor<FoodEntry>())) ?? [] {
        rows.append(("nutrition", m.remoteID.isEmpty ? "" : "food-\(m.remoteID)"))
      }
      SyncEngine.shared.deleteEverywhere(rows, syncNow: false)
    }
    TrainingDataWipe.wipe(modelContext)
    try? modelContext.save()
    if synced {
      let confirmed = await SyncEngine.shared.flush()
      if !confirmed { wipeIncomplete = true }
    }
  }
}

struct AccountPage: View {
  @Environment(AuthClient.self) private var auth
  @Environment(SyncEngine.self) private var sync
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var confirmAccountDelete = false
  @State private var deleteFailed = false
  @State private var deleteSessionExpired = false

  private var heroSubtitle: String {
    var subtitle = String(
      localized: "Last sync · \(SettingsFormat.relativeSync(sync.lastSync))", bundle: L10n.bundle)
    if let email = auth.user?.email, email.lowercased().hasSuffix("@privaterelay.appleid.com") {
      subtitle += "\n" + String(localized: "Apple private relay", bundle: L10n.bundle)
    }
    return subtitle
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Account", bundle: L10n.bundle)) {
      SettingsHero(
        title: auth.user?.email ?? String(localized: "Signed in", bundle: L10n.bundle),
        subtitle: heroSubtitle)
    } content: {
      Spacer().frame(height: 10)
      SettingsRow(
        title: String(localized: "Plan", bundle: L10n.bundle),
        value: auth.user?.tier == "pro"
          ? String(localized: "Pro", bundle: L10n.bundle)
          : String(localized: "Free", bundle: L10n.bundle),
        accessory: .none)
      SettingsHairline(inset: false)
      SettingsRow(title: String(localized: "Sync", bundle: L10n.bundle), accessory: .none) {
        if sync.syncing {
          ProgressView()
        } else {
          Button {
            Task { await SyncEngine.shared.sync() }
          } label: {
            Text(String(localized: "Sync now", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.accentText)
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
        }
      }
      SettingsHairline(inset: false)
      Button {
        Task {
          await auth.signOut()
          dismiss()
        }
      } label: {
        SettingsRow(
          title: String(localized: "Sign out", bundle: L10n.bundle),
          titleColor: Theme.accentText, accessory: .none)
      }
      .buttonStyle(RowPressStyle())
      SettingsHairline(inset: false)
      Button {
        confirmAccountDelete = true
      } label: {
        SettingsRow(
          title: String(localized: "Delete account", bundle: L10n.bundle),
          titleColor: Theme.negative, accessory: .none)
      }
      .buttonStyle(RowPressStyle())
    }
    .confirmationDialog(
      String(localized: "Delete your account?", bundle: L10n.bundle),
      isPresented: $confirmAccountDelete, titleVisibility: .visible
    ) {
      Button(String(localized: "Delete account and data", bundle: L10n.bundle), role: .destructive) {
        Analytics.track("account_deleted")
        Task { await deleteAccountAndData() }
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized: "Your account and the data synced to it are deleted. Training data on this iPhone is deleted too. An App Store subscription keeps billing until you cancel it in Settings › Apple Account › Subscriptions.",
          bundle: L10n.bundle))
    }
    .alert(
      String(localized: "Couldn't delete your account", bundle: L10n.bundle),
      isPresented: $deleteFailed
    ) {
      Button(String(localized: "OK", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        deleteSessionExpired
        ? String(localized: "Your session expired. Sign in again, then delete your account.", bundle: L10n.bundle)
        : String(localized: "Check your connection and try again.", bundle: L10n.bundle))
    }
  }

  /// Local data is wiped only after the server confirmed the deletion, so a failed call keeps it.
  private func deleteAccountAndData() async {
    deleteFailed = false
    deleteSessionExpired = false
    do {
      try await auth.deleteAccount()
    } catch let error as APIError where error.status == 401 {
      // ForgeAPI already dropped the dead session token; a retry needs a fresh sign-in.
      await auth.signOut()
      deleteSessionExpired = true
      return
    } catch {
      deleteFailed = true
      return
    }
    TrainingDataWipe.wipe(modelContext)
    SyncEngine.shared.resetAfterAccountDeletion(
      profile: (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first)
    try? modelContext.save()
    dismiss()
    AccessibilityNotification.Announcement(String(localized: "Your account was deleted.", bundle: L10n.bundle)).post()
  }
}

struct ProPage: View {
  @Environment(Store.self) private var store
  @State private var restoring = false
  @State private var restoreCaption: String?
  @State private var showManageSubscription = false
  #if DEBUG
    @State private var showPurchaseTest = false
  #endif

  var body: some View {
    SettingsFieldPage(title: String(localized: "Regulift Pro", bundle: L10n.bundle)) {
      SettingsHero(title: SettingsFormat.subscriptionStatus(store.status), art: "art-pro")
    } content: {
      Spacer().frame(height: 10)
      Button {
        guard !restoring else { return }
        restoring = true
        Task {
          switch await store.restore() {
          case .restored:
            restoreCaption = String(localized: "Purchases restored.", bundle: L10n.bundle)
          case .nothingToRestore:
            restoreCaption = String(localized: "No purchases to restore.", bundle: L10n.bundle)
          case .failed(let message):
            restoreCaption = message
          }
          restoring = false
        }
      } label: {
        SettingsRow(
          title: String(localized: "Restore purchases", bundle: L10n.bundle),
          titleColor: Theme.accentText, accessory: .none
        ) {
          if restoring { ProgressView() }
        }
      }
      .buttonStyle(RowPressStyle())
      .disabled(restoring)
      if let restoreCaption {
        Text(restoreCaption)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 4)
          .fixedSize(horizontal: false, vertical: true)
      }
      if store.canManageSubscription {
        SettingsHairline(inset: false)
        Button {
          showManageSubscription = true
        } label: {
          SettingsRow(
            title: String(localized: "Manage subscription", bundle: L10n.bundle),
            titleColor: Theme.accentText, accessory: .none)
        }
        .buttonStyle(RowPressStyle())
      }
      #if DEBUG
        SettingsHairline(inset: false)
        Button {
          showPurchaseTest = true
        } label: {
          SettingsRow(
            title: String(localized: "Test purchase flow", bundle: L10n.bundle),
            titleColor: Theme.accentText, accessory: .none)
        }
        .buttonStyle(RowPressStyle())
      #endif
    }
    .manageSubscriptionsSheet(isPresented: $showManageSubscription)
    #if DEBUG
      .sheet(isPresented: $showPurchaseTest) { PaywallView() }
    #endif
  }
}

struct CrewSharingPage: View {
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false

  private var heroTitle: String {
    switch (autoPostWorkouts, autoPostPRs) {
    case (false, false): return String(localized: "Nothing posts on its own.", bundle: L10n.bundle)
    case (true, false): return String(localized: "Finished workouts post to your crew.", bundle: L10n.bundle)
    case (false, true): return String(localized: "New PRs post to your crew.", bundle: L10n.bundle)
    default: return String(localized: "Workouts and PRs post to your crew.", bundle: L10n.bundle)
    }
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Crew sharing", bundle: L10n.bundle)) {
      SettingsHero(
        title: heroTitle,
        subtitle: String(localized: "Your crew sees only what you post.", bundle: L10n.bundle))
    } content: {
      Spacer().frame(height: 10)
      SettingsToggleRow(
        title: String(localized: "Post finished workouts to my crew", bundle: L10n.bundle),
        isOn: $autoPostWorkouts)
      SettingsHairline(inset: false)
      SettingsToggleRow(
        title: String(localized: "Post new PRs to my crew", bundle: L10n.bundle),
        isOn: $autoPostPRs)
    }
  }
}

struct InvitePage: View {
  var body: some View {
    SettingsFieldPage(title: String(localized: "Invite friends", bundle: L10n.bundle)) {
      SettingsHero(
        title: String(localized: "Give a month, get a month", bundle: L10n.bundle),
        subtitle: String(
          localized: "A friend who joins with your code gets a free month, and so do you.",
          bundle: L10n.bundle))
    } content: {
      ReferralView()
        .padding(.top, 16)
    }
  }
}
