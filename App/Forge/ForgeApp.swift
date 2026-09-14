import SwiftUI
import SwiftData

@main
struct ForgeApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .modelContainer(for: [UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self])
  }
}

struct RootView: View {
  @Query private var profiles: [UserProfile]

  var body: some View {
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
}

struct MainTabView: View {
  var body: some View {
    TabView {
      TodayView()
        .tabItem { Label("Today", systemImage: "flame.fill") }
      ProgressTabView()
        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
    }
  }
}
