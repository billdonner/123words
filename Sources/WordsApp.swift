import SwiftUI

// LaunchState lives in the App — always fresh on each process start, never restored
class LaunchState: ObservableObject {
    @Published var showLaunch = true
}

/// Race points used to be a flat +1 per correct answer in every game;
/// they're now weighted by effort (3 for a whole word, 1 for a memory
/// pair). A best score saved under the old scheme measures something
/// different from one saved under the new one, so comparing them is
/// meaningless — and the old ones are trivially beatable, which would
/// hand out "New best!" for nothing. Retire them once.
private func migrateRaceScoresIfNeeded() {
    let key = "raceScoringVersion"
    let defaults = UserDefaults.standard
    guard defaults.integer(forKey: key) < 2 else { return }
    for d in [60, 120] {
        defaults.removeObject(forKey: "raceBest_\(d)")
        defaults.removeObject(forKey: "raceLast_\(d)")
    }
    defaults.set(2, forKey: key)
}

@main
struct WordsApp: App {
    @StateObject private var launchState = LaunchState()

    init() { migrateRaceScoresIfNeeded() }

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
