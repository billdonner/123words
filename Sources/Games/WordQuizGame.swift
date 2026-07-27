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
    @State private var colorIndex = randomGameColor()
    @State private var showCheer = false
    // Bumped on every new round / dismiss; delayed callbacks bail if stale.
    @State private var roundGen = 0

    private var isIPad: Bool { sizeClass == .regular }
    private var bg: Color { gameColors[colorIndex % gameColors.count] }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: colorIndex)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 6)

                Text("Tap the picture you hear")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    speech.speak(answer)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: isIPad ? 56 : 44, weight: .black))
                        Text(answer.uppercased())
                            .font(.system(size: isIPad ? 38 : 28, weight: .black, design: .rounded))
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

                let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { idx, word in
                        choiceTile(word: word, idx: idx)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }

            if showCheer { GameCheer(message: "Yes!\nThat's \(answer.uppercased())!") }
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
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func choiceTile(word: String, idx: Int) -> some View {
        let isWrong = wrongIndex == idx
        let isRight = rightIndex == idx
        return ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(isWrong ? Color.red.opacity(0.6)
                      : isRight ? Color.green.opacity(0.55)
                                : Color.white.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                )
            GameWordImage(word: word, size: isIPad ? 140 : 100)
        }
        .aspectRatio(1, contentMode: .fit)
        .onTapGesture { pick(idx) }
    }

    private func pick(_ idx: Int) {
        guard !locked else { return }
        let g = roundGen
        if choices[idx] == answer {
            locked = true
            rightIndex = idx
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if inRace {
                // Verbal "Correct!" + race bump, then snap to the
                // next round. 0.85s is enough for the word to land
                // before the next prompt's stopAll cuts it off.
                speech.speak("Correct!")
                onCorrect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
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
            wrongIndex = idx
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if inRace {
                // One shot per question — verbalize the right answer
                // so the kid learns from the miss, then advance.
                locked = true
                speech.speak("Sorry. The correct answer is \(answer).")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                    guard g == roundGen else { return }
                    newRound(initial: false)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard g == roundGen else { return }
                    wrongIndex = nil
                }
            }
        }
    }

    private func newRound(initial: Bool) {
        roundGen &+= 1
        let g = roundGen
        let pool = GameWordPool.randomDistinct(count: 4)
        choices = pool
        answer = pool.randomElement() ?? "cat"
        wrongIndex = nil
        rightIndex = nil
        locked = false
        colorIndex = randomGameColor(excluding: colorIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard g == roundGen, shouldSpeakPrompt() else { return }
            speech.speak(answer)
        }
    }
}
