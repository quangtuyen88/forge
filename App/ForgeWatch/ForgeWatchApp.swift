import SwiftUI

@main
struct ForgeWatchApp: App {
  init() { WatchTheme.registerFonts() }

  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .tint(WatchTheme.accent)
        .environment(WatchStore.shared)
    }
  }
}
