import SwiftUI

// LaunchState lives in the App — always fresh on each process start, never restored
class LaunchState: ObservableObject {
    @Published var showLaunch = true
}

@main
struct WordsApp: App {
    @StateObject private var launchState = LaunchState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeHubView()
                    .environmentObject(launchState)

                if launchState.showLaunch {
                    LaunchView(isShowing: $launchState.showLaunch)
                        .zIndex(1)
                        .transition(.opacity)
                }
            }
        }
    }
}
