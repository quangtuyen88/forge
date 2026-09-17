import SwiftUI
import SwiftData
import UIKit

@main
struct ForgeApp: App {
  @State private var store = Store()
  static let sharedContainer: ModelContainer = {
    let container = try! ModelContainer(
      for: UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self,
      BodyMeasurement.self, ProgressPhoto.self, CoachMessage.self, CoachNote.self,
      NutritionProfile.self, FoodItem.self, FoodEntry.self, CustomExercise.self)
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
#endif
    CustomExerciseRegistry.reload(container.mainContext)
    WatchSync.shared.configure(container: container)
    SyncEngine.shared.configure(container: container)
    AuthClient.shared.configure(store: store)
    _ = store.listen()
    Keychain.delete("anthropic-api-key")
    if let large = UIFont(name: "InterTight-Bold", size: 30) {
      UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .kern: -0.9]
    }
    if let title = UIFont(name: "InterTight-SemiBold", size: 17) {
      UINavigationBar.appearance().titleTextAttributes = [.font: title, .kern: -0.4]
    }
    if let tab = UIFont(name: "InterTight-Medium", size: 11) {
      UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
    }
    if let seg = UIFont(name: "InterTight-Medium", size: 13) {
      UISegmentedControl.appearance().setTitleTextAttributes([.font: seg], for: .normal)
      UISegmentedControl.appearance().setTitleTextAttributes([.font: seg], for: .selected)
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .font(.forge(16))
        .tint(Theme.accent)
        .environment(store)
        .environment(AuthClient.shared)
        .environment(SyncEngine.shared)
    }
    .modelContainer(container)
  }
}

struct RootView: View {
  @Query private var profiles: [UserProfile]
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(L10n.key) private var appLanguage = "en"

  private var scheme: ColorScheme? {
    switch profiles.first?.theme {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
  }

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
    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    .preferredColorScheme(scheme)
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
        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
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
