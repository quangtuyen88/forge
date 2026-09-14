import SwiftUI

@main
struct ForgeWatchApp: App {
  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .environment(WatchStore.shared)
    }
  }
}
