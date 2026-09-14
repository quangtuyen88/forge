import SwiftUI
import SwiftData

@main
struct ForgeApp: App {
  @State private var store = Store()
  private let container: ModelContainer

  init() {
    let container = try! ModelContainer(for: UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self)
    self.container = container
    WatchSync.shared.configure(container: container)
    _ = store.listen()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .tint(Theme.accent)
        .environment(store)
    }
    .modelContainer(container)
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
      CoachView()
        .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
      ProgressTabView()
        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
    }
  }
}
