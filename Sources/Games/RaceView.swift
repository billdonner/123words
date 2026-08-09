import SwiftUI

// The Race! screen — wraps the 5 game panels in a single swipeable
// TabView with a shared timer bar + score counter at the top. Each
// game reports back via an `onCorrect` closure that funnels into the
// RaceSession's score.
struct RaceView: View {
    @ObservedObject var speech: SpeechEngine
    @StateObject var race: RaceSession
    let duration: TimeInterval

    // 0..4 maps into `games`; the kid swipes between these.
    @State private var page: Int = 0
    // Bumped by Play Again so the 5 game subviews get fresh @State.
    @State private var resetToken: Int = 0
    // Animation pulse for the score chip on every +1.
    @State private var scorePulse: CGFloat = 1.0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let games: [HomePage] = [.spell, .scramble, .memory, .quiz, .count]
    private var isIPad: Bool { sizeClass == .regular }
    private var currentGame: HomePage { games[page] }

    // Best score for this duration, persisted across launches.
    @AppStorage private var bestScore: Int

    init(speech: SpeechEngine, duration: TimeInterval) {
        self.speech = speech
        self.duration = duration
        // RaceSession is the wrapper's own; lifecycle ends with the view.
        self._race = StateObject(wrappedValue: RaceSession())
        // Personal best is keyed by duration so 60s and 120s have
        // separate hi-scores.
        self._bestScore = AppStorage(wrappedValue: 0, "raceBest_\(Int(duration))")
    }

    var body: some View {
        ZStack {
            currentGame.color.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: page)

            VStack(spacing: 0) {
                raceBar
                gameTabs
            }

            if race.phase == .finished {
                resultsOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Begin the countdown on first appearance. Subsequent
            // re-presentations get their own RaceView instance.
            race.start(duration: duration)
            applyScreenshotHooksIfAny()
        }
        .onDisappear {
            race.end()
            speech.stopAll()
        }
        .onChange(of: race.phase) { _, new in
            // Hitting zero stops speech mid-utterance to silence the
            // race instantly, matching the visual lock.
            if new == .finished { speech.stopAll() }
        }
        .onChange(of: page) { _, _ in
            // Swiping to a new tab silences whatever the previous tab
            // was speaking. The new tab will schedule its own prompt
            // speak on appear; off-tab deferred speaks are gated by
            // each game's shouldSpeakPrompt closure.
            speech.stopAll()
        }
        .onChange(of: race.scoreToken) { _, _ in
            // Score pulse on each +1.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                scorePulse = 1.35
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                scorePulse = 1.0
            }
        }
    }

    // MARK: - Top bar (shared across all 5 game panels)

    private var raceBar: some View {
        HStack(spacing: 12) {
            Button { race.end(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End race")

            timerBar
                .frame(height: 36)

            scoreChip
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var timerBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(timerColor)
                    .frame(width: max(0, geo.size.width * CGFloat(race.remaining / race.duration)))
                    .animation(.linear(duration: 0.1), value: race.remaining)
                Text("\(Int(ceil(race.remaining)))s")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var timerColor: Color {
        let frac = race.duration > 0 ? race.remaining / race.duration : 0
        if frac > 0.5 { return Color(red: 0.2, green: 0.8, blue: 0.35) }
        if frac > 0.2 { return Color(red: 1.0, green: 0.65, blue: 0.1) }
        return Color(red: 0.95, green: 0.25, blue: 0.25)
    }

    private var scoreChip: some View {
        Text("\(race.score)")
            .font(.system(size: 26, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 56, minHeight: 36)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(.white.opacity(0.22))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            )
            .scaleEffect(scorePulse)
            .accessibilityLabel("Score: \(race.score)")
    }

    // MARK: - Swipeable game ring

    private var gameTabs: some View {
        TabView(selection: $page) {
            ForEach(Array(games.enumerated()), id: \.element.id) { idx, g in
                gameView(g)
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        // Fresh game state for each Play Again.
        .id(resetToken)
    }

    @ViewBuilder
    private func gameView(_ g: HomePage) -> some View {
        let bump = { race.registerCorrect(for: g) }
        // Live tab-active check — closures read `games[page]` through
        // the persistent State storage, so the closure stays accurate
        // even after a swipe. Stops off-screen tabs from audibly
        // speaking their prompts (the kid was hearing math while on
        // Spell because all 5 tabs fired their deferred speak at
        // race start).
        let activeNow: () -> Bool = { g == games[page] }
        switch g {
        case .spell:    SpellItGame(speech: speech, inRace: true, onCorrect: bump, shouldSpeakPrompt: activeNow)
        case .scramble: WordScrambleGame(speech: speech, inRace: true, onCorrect: bump, shouldSpeakPrompt: activeNow)
        case .memory:   MemoryMatchGame(speech: speech, inRace: true, onCorrect: bump)
        case .quiz:     WordQuizGame(speech: speech, inRace: true, onCorrect: bump, shouldSpeakPrompt: activeNow)
        case .count:    CountItGame(speech: speech, inRace: true, onCorrect: bump, shouldSpeakPrompt: activeNow)
        case .read:     EmptyView()   // Practice is not in the race ring
        }
    }

    // MARK: - End-of-race results

    private var resultsOverlay: some View {
        let stars = starCount(for: race.score)
        let isPB  = race.score > bestScore
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(stars >= 1 ? "⭐️" : "🏁")
                    .font(.system(size: isIPad ? 110 : 84))

                Text("Time's up!")
                    .font(.system(size: isIPad ? 40 : 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(race.score)")
                    .font(.system(size: isIPad ? 110 : 88, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Stars")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Text(i < stars ? "⭐️" : "☆")
                            .font(.system(size: isIPad ? 44 : 34))
                            .foregroundStyle(i < stars ? .yellow : .white.opacity(0.45))
                    }
                }

                if isPB {
                    Text("New best!")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                } else if bestScore > 0 {
                    Text("Best: \(bestScore)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }

                if !race.perGame.isEmpty {
                    breakdown
                        .padding(.top, 6)
                }

                HStack(spacing: 14) {
                    overlayButton(label: "Play again", filled: true) {
                        if isPB { bestScore = race.score }
                        race.reset()
                        resetToken &+= 1
                        race.start(duration: duration)
                    }
                    overlayButton(label: "Done", filled: false) {
                        if isPB { bestScore = race.score }
                        dismiss()
                    }
                }
                .padding(.top, 12)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 26)
            .frame(maxWidth: isIPad ? 520 : .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(currentGame.color.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(.white.opacity(0.55), lineWidth: 4)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 8)
            )
            .padding(.horizontal, 22)
        }
        .contentShape(Rectangle())   // Backdrop swallows taps to the games.
    }

    private var breakdown: some View {
        let entries = games.compactMap { g -> (HomePage, Int)? in
            let n = race.perGame[g, default: 0]
            return n > 0 ? (g, n) : nil
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(entries, id: \.0.id) { g, n in
                HStack {
                    Text(g.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Spacer()
                    Text("\(n)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func overlayButton(label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(filled ? currentGame.color : .white)
                .padding(.vertical, 14)
                .padding(.horizontal, 26)
                .background(
                    Capsule()
                        .fill(filled ? Color.white : Color.white.opacity(0.15))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: filled ? 0 : 2))
                )
        }
        .buttonStyle(.plain)
    }

    /// Reads `screenshotRace*` UserDefaults set by the capture script
    /// and freezes the race in a compelling state (preset score,
    /// remaining time, results overlay, starting page). Each key is
    /// consumed (removed) so the next launch behaves normally.
    private func applyScreenshotHooksIfAny() {
        let d = UserDefaults.standard
        // Tab to land on inside the race ring.
        if let tabName = d.string(forKey: "screenshotRaceTab"),
           let target = HomePage(rawValue: tabName),
           let idx = games.firstIndex(of: target) {
            page = idx
            d.removeObject(forKey: "screenshotRaceTab")
        }
        // Freeze in mid-race or results state if any of these are set.
        let frozen = d.object(forKey: "screenshotRaceScore") != nil
                  || d.object(forKey: "screenshotRaceRemaining") != nil
                  || d.bool(forKey: "screenshotRaceFinished")
        guard frozen else { return }
        let score = d.object(forKey: "screenshotRaceScore") as? Int ?? 0
        let remaining = d.object(forKey: "screenshotRaceRemaining") as? Double ?? duration / 2
        let finished = d.bool(forKey: "screenshotRaceFinished")
        // Plausible per-game breakdown for the results overlay.
        let perGame: [HomePage: Int] = finished
            ? [.spell: max(1, score / 4), .scramble: max(0, score / 5),
               .quiz:  max(1, score / 3), .count: max(0, score / 5),
               .memory: max(0, score - (score / 4 + score / 5 + score / 3 + score / 5))]
                .filter { $0.value > 0 }
            : [:]
        race.freezeForScreenshot(score: score,
                                 remaining: remaining,
                                 perGame: perGame,
                                 finished: finished)
        d.removeObject(forKey: "screenshotRaceScore")
        d.removeObject(forKey: "screenshotRaceRemaining")
        d.removeObject(forKey: "screenshotRaceFinished")
    }

    private func starCount(for score: Int) -> Int {
        if score >= 30 { return 3 }
        if score >= 20 { return 2 }
        if score >= 10 { return 1 }
        return 0
    }
}
