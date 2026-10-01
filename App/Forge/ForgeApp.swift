import SwiftUI
import SwiftData
import UIKit

@main
struct ForgeApp: App {
  @State private var store = Store()
  static let sharedContainer: ModelContainer = {
    // JourneyPlans: the three Journey models are device-local. They are declared here so they
    // persist, and deliberately NOT declared in `SyncEngine` (an explicit allowlist), so a
    // private note, a hide/restore override and the local identity card never leave the device.
    let container = try! ModelContainer(
      for: UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self,
      BodyMeasurement.self, ProgressPhoto.self, CoachMessage.self, CoachNote.self,
      NutritionProfile.self, FoodItem.self, FoodEntry.self, CustomExercise.self,
      DecisionLogEntry.self, JourneyReflection.self, JourneyVisibilityOverride.self,
      JourneyPrivateProfile.self)
    return container
  }()

  private let container: ModelContainer

  init() {
    L10n.install()
    let container = Self.sharedContainer
    self.container = container
#if DEBUG
    setvbuf(stdout, nil, _IOLBF, 0)
    if ProcessInfo.processInfo.arguments.contains("--seed-demo") { DemoSeed.run(in: container.mainContext) }
    // Planning QA fixtures (--planning-fixture=<ID>): wipe and seed; runs after --seed-demo.
    PlanningFixtures.run(in: container.mainContext)
#endif
    CustomExerciseRegistry.reload(container.mainContext)
    WatchSync.shared.configure(container: container)
    SyncEngine.shared.configure(container: container)
    AuthClient.shared.configure(store: store)
    _ = store.listen()
    Keychain.delete("anthropic-api-key")
    if let large = UIFont(name: "InterTight-Bold", size: 30) {
      let scaledLarge = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)
      UINavigationBar.appearance().largeTitleTextAttributes = [.font: scaledLarge, .kern: -0.9]
    }
    if let title = UIFont(name: "InterTight-SemiBold", size: 17) {
      let scaledTitle = UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)
      UINavigationBar.appearance().titleTextAttributes = [.font: scaledTitle, .kern: -0.4]
    }
    if let tab = UIFont(name: "InterTight-Medium", size: 11) {
      let scaledTab = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: tab)
      UITabBarItem.appearance().setTitleTextAttributes([.font: scaledTab], for: .normal)
    }
    if let seg = UIFont(name: "InterTight-Medium", size: 13) {
      let scaledSeg = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: seg)
      UISegmentedControl.appearance().setTitleTextAttributes([.font: scaledSeg], for: .normal)
      UISegmentedControl.appearance().setTitleTextAttributes([.font: scaledSeg], for: .selected)
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .font(.forge(16))
        .tint(Theme.accentText)
        .environment(store)
        .environment(AuthClient.shared)
        .environment(SyncEngine.shared)
        .task { await store.load() }
    }
    .modelContainer(container)
  }
}

struct RootView: View {
  @Query private var profiles: [UserProfile]
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(L10n.key) private var appLanguage = "en"

  private func consumeStartWorkoutFlag() {
    guard let defaults = UserDefaults(suiteName: WidgetBridge.suite),
          defaults.bool(forKey: "forge.intent.startWorkout") else { return }
    defaults.set(false, forKey: "forge.intent.startWorkout")
    NotificationCenter.default.post(name: .forgeStartWorkout, object: nil)
  }

  private func consumeCheckInFlag() {
    guard let defaults = UserDefaults(suiteName: WidgetBridge.suite),
          defaults.bool(forKey: "forge.intent.checkIn") else { return }
    defaults.set(false, forKey: "forge.intent.checkIn")
    NotificationCenter.default.post(name: .forgeCheckIn, object: nil)
  }

  private func rescheduleTrainingDayReminders() {
    guard let profile = profiles.first, profile.reminderHour != nil,
      UserDefaults.standard.bool(forKey: ReminderScheduler.trainingDaysKey)
    else { return }
    ReminderScheduler.reschedule(profile: profile)
  }

  var body: some View {
    Group {
      if let profile = profiles.first {
        if profile.isSubscribed {
          MainTabView()
        } else {
          PaywallView()
        }
      } else {
        OnboardingView()
      }
    }
    .id(appLanguage)
    .environment(\.locale, Locale(identifier: appLanguage))
    // AX3 is about 235 % of the default size, above Apple's 200 % target.
    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    .onAppear {
      Analytics.track("app_open")
      // ponytail: cold-start clear only — re-clearing on scenePhase .active would drop the flag of a backgrounded live workout
      UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
      consumeStartWorkoutFlag()
      consumeCheckInFlag()
      Task { await RemoteConfig.shared.refresh() }
      Task { await AuthClient.shared.refresh() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        consumeStartWorkoutFlag()
        consumeCheckInFlag()
      }
      if phase == .active || phase == .background {
        rescheduleTrainingDayReminders()
        Task { await SyncEngine.shared.sync() }
      }
    }
  }
}

struct MainTabView: View {
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      TodayView(selection: $selection)
        .tabItem { Label("Today", systemImage: "flame.fill") }
        .tag(0)
      CoachView()
        .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
        .tag(1)
      ProgressTabView()
        .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        .tag(2)
      CrewView()
        .tabItem { Label("Crew", systemImage: "person.2.fill") }
        .tag(3)
    }
    .onReceive(NotificationCenter.default.publisher(for: .forgeStartWorkout)) { _ in
      selection = 0
    }
  }
}
