import Foundation
import Combine

// Shared state for a "Race!" session: one timer + one score that spans
// all 5 game panels. Kids swipe between games freely and every correct
// answer in any game pushes +1 into the same score.
//
// Practice (the reader) lives outside the race; if the kid swipes to it
// from a race view the wrapper calls pause()/resume() so the clock
// doesn't tick down while they're in the safe zone.
final class RaceSession: ObservableObject {

    enum Phase: Equatable {
        case idle       // pre-race; controls visible on the hub
        case running    // clock ticking
        case paused     // kid is on Practice or the system paused us
        case finished   // time up, score frozen, results overlay shown
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var score: Int = 0
    @Published private(set) var perGame: [HomePage: Int] = [:]
    @Published private(set) var remaining: TimeInterval = 60
    @Published private(set) var duration: TimeInterval = 60

    // Bumped on every +1; views can drive a small score-pulse animation
    // off `.onChange(of: race.scoreToken)`.
    @Published private(set) var scoreToken: Int = 0

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var timer: Timer?

    /// Start a fresh race. Resets score, perGame breakdown, and timer.
    func start(duration: TimeInterval) {
        stopTimer()
        self.duration = duration
        self.remaining = duration
        self.score = 0
        self.perGame = [:]
        self.scoreToken = 0
        self.pausedRemaining = nil
        self.endDate = Date().addingTimeInterval(duration)
        self.phase = .running
        startTimer()
    }

    /// Pause the clock without ending the race (kid swiped to Practice).
    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining
        phase = .paused
        stopTimer()
    }

    /// Resume after a pause; safe to call when already running (no-op).
    func resume() {
        guard phase == .paused, let r = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(r)
        pausedRemaining = nil
        phase = .running
        startTimer()
    }

    /// End immediately (kid hit Done, or external lifecycle end).
    func end() {
        stopTimer()
        remaining = 0
        phase = .finished
    }

    /// Return to idle so the hub can show race controls again.
    func reset() {
        stopTimer()
        phase = .idle
        score = 0
        perGame = [:]
        scoreToken = 0
        remaining = duration
        pausedRemaining = nil
        endDate = nil
    }

    /// Called by each game when the kid completes a correct round.
    /// No-op outside of `.running` so end-of-race taps don't leak score.
    func registerCorrect(for game: HomePage) {
        guard phase == .running else { return }
        // Weighted by effort — see HomePage.racePoints.
        let points = game.racePoints
        score += points
        perGame[game, default: 0] += points
        scoreToken &+= 1
    }

    // 10Hz tick is smooth enough for a kid's progress bar without
    // burning CPU; the bar animates between ticks via .animation modifier.
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate else { return }
            let r = max(0, end.timeIntervalSinceNow)
            self.remaining = r
            if r <= 0 {
                self.stopTimer()
                self.phase = .finished
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stopTimer() }

    /// Freeze the session in a synthetic state for App Store screenshots.
    /// Stops the timer so the score/remaining/phase you pass in stay put.
    func freezeForScreenshot(score: Int,
                             remaining: TimeInterval,
                             perGame: [HomePage: Int],
                             finished: Bool = false) {
        stopTimer()
        self.score = score
        self.remaining = remaining
        self.perGame = perGame
        self.phase = finished ? .finished : .running
    }
}
