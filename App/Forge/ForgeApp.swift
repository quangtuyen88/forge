import SwiftUI
import SwiftData
import UIKit

@main
struct ForgeApp: App {
  @State private var store = Store()
  private let container: ModelContainer

  init() {
    // ponytail: other agents add models here in the next wave
    let container = try! ModelContainer(
      for: UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self,
      BodyMeasurement.self, ProgressPhoto.self, CoachMessage.self,
      NutritionProfile.self, FoodItem.self, FoodEntry.self)
    self.container = container
    WatchSync.shared.configure(container: container)
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
    }
    .modelContainer(container)
  }
}

struct RootView: View {
  @Query private var profiles: [UserProfile]

  private var scheme: ColorScheme? {
    switch profiles.first?.theme {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
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
    .preferredColorScheme(scheme)
    .onAppear {
      Analytics.track("app_open")
      Task { await RemoteConfig.shared.refresh() }
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
      NutritionView()
        .tabItem { Label("Fuel", systemImage: "fork.knife") }
        .tag(3)
    }
  }
}
