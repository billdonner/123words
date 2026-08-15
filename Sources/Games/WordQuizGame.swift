import SwiftUI
import UIKit

struct WordQuizGame: View {
    @ObservedObject var speech: SpeechEngine
    /// True when launched inside a Race; suppresses the long celebration
    /// and post-answer replay so the kid can rack up more attempts.
    var inRace: Bool = false
    /// Called every time the kid taps the correct picture. The race
    /// session owner uses this to bump the shared score counter.
    var onCorrect: () -> Void = {}
    /// Live check: is this game the currently-visible tab? In race
    /// mode all 5 game views are mounted at once and each schedules a
    /// deferred `speech.speak(prompt)` after a round starts. If the
    /// kid has swiped away (or rapid-tapped before the +0.4s fires),
    /// that speak would belong to an off-screen game and the kid hears
    /// the wrong prompt. RaceView passes a live closure that reads the
    /// current page; freeform mode defaults to true.
    var shouldSpeakPrompt: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var answer: String = "cat"
    @State private var choices: [String] = []
    @State private var wrongIndex: Int? = nil
    @State private var rightIndex: Int? = nil
    @State private var locked = false
    @State private var misses = 0
    @State private var hintIndex: Int? = nil
    @State private var colorIndex = randomGameColor()
    @State private var showCheer = false
    // Bumped on every new round / dismiss; delayed callbacks bail if stale.
    @State private var roundGen = 0

    private var isIPad: Bool { sizeClass == .regular }
    private var bg: Color { gameColors[colorIndex % gameColors.count] }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            bg.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: colorIndex)

            // The four choices were a 2-column grid of aspect-ratio-1
            // squares, which on a landscape iPad wanted ~660pt per tile —
            // two rows needing 1320pt against ~1024 of screen. The top
            // bar, the prompt and the replay button were pushed entirely
            // off the top and the game was unplayable. Size the tiles to
            // what's actually left, and go to a single row of four when
            // the screen is wide.
            let landscape = geo.size.width > geo.size.height
            let cols = landscape ? 4 : 2
            let rows = 4 / cols
            let gap: CGFloat = 16
            let chrome: CGFloat = 300 * KidMetrics.textScale
            let byW = (geo.size.width - 44 - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let byH = (geo.size.height - chrome - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let tile = max(90, min(byW, byH))

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 6)

                Text("Tap the picture you hear")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

                Button {
                    speech.speak(answer)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: isIPad ? 56 : 44, weight: .black))
                        // The answer used to be printed here in 28pt
                        // under the words "Tap the picture you hear",
                        // which hands the answer to any child who can
                        // read and is noise to one who can't. It now
                        // appears only once they've chosen correctly, as
                        // the sound-to-print pairing payoff.
                        Text(rightIndex == nil ? "Tap to hear again" : kidCase(answer))
                            .font(.system(size: rightIndex == nil
                                          ? (isIPad ? 20 : 16)
                                          : (isIPad ? 38 : 28),
                                          weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 32)
                    .background(.white.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                Spacer(minLength: 10)

                let grid = Array(repeating: GridItem(.fixed(tile), spacing: gap), count: cols)
                LazyVGrid(columns: grid, spacing: gap) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { idx, word in
                        choiceTile(word: word, idx: idx, side: tile)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }

            if showCheer { GameCheer(message: "Yes!\nThat's \(kidCase(answer))!") }
        }
        }
        .onAppear { newRound(initial: true) }
        .onDisappear {
            roundGen &+= 1
            speech.stopAll()
        }
    }

    private var topBar: some View {
        HStack {
            // In Race mode the wrapper provides a shared Close button.
            if inRace {
                Color.clear.frame(width: 44, height: 44)
            } else {
                GameCloseButton { dismiss() }
            }
            Spacer()
            Text("Listen & Pick")
                .font(.system(size: 22 * KidMetrics.textScale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func choiceTile(word: String, idx: Int, side: CGFloat) -> some View {
        let mark: AnswerMark.State =
            wrongIndex == idx ? .wrong : (rightIndex == idx ? .right : .none)
        return Button { pick(idx) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(hintIndex == idx ? Color.white.opacity(0.5)
                                           : Color.white.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                    )
                GameWordImage(word: word, size: side * 0.78)
            }
            .frame(width: side, height: side)
            .answerMark(mark)
        }
        .buttonStyle(KidTileButtonStyle())
        // These tiles were pure image with no label at all, so VoiceOver
        // announced nothing for any of the four answers — the game was
        // unusable rather than merely awkward.
        .accessibilityLabel(word)
    }

    private func pick(_ idx: Int) {
        guard !locked else { return }
        let g = roundGen
        if choices[idx] == answer {
            locked = true
            rightIndex = idx
            hintIndex = nil
            Haptics.success()
            WordProgress.shared.recordCorrect(answer)
            if inRace {
                // "Correct!" + race bump, then advance. Was 0.85s, which
                // is under the beat a child needs to register what they
                // just got right.
                speech.speak("Correct!")
                onCorrect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard g == roundGen else { return }
                    newRound(initial: false)
                }
            } else {
                withAnimation { showCheer = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    guard g == roundGen else { return }
                    withAnimation { showCheer = false }
                    newRound(initial: false)
                }
            }
        } else {
            // No skip, no apology — see SpellItGame.tap. After a second
            // miss the correct picture is highlighted and the prompt
            // repeats, but the child still makes the choice.
            wrongIndex = idx
            Haptics.wrong()
            misses += 1
            WordProgress.shared.recordMiss(answer)
            if misses >= 2 {
                hintIndex = choices.firstIndex(of: answer)
                speech.speak(answer)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard g == roundGen else { return }
                wrongIndex = nil
            }
        }
    }

    private func newRound(initial: Bool) {
        roundGen &+= 1
        let g = roundGen
        let pool = GameWordPool.randomDistinct(count: 4)
        choices = pool
        let fixedAnswer = UserDefaults.standard.string(forKey: "screenshotQuizAnswer")
        answer = fixedAnswer.flatMap { pool.contains($0) ? $0 : nil }
            ?? pool.randomElement() ?? "cat"
        wrongIndex = nil
        rightIndex = nil
        locked = false
        misses = 0
        hintIndex = nil
        Haptics.prepare()
        colorIndex = randomGameColor(excluding: colorIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard g == roundGen, shouldSpeakPrompt() else { return }
            speech.speak(answer)
        }
    }
}
