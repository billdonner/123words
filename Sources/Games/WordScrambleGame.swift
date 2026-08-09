import SwiftUI
import UIKit

struct WordScrambleGame: View {
    @ObservedObject var speech: SpeechEngine
    /// True when launched inside a Race; suppresses the long celebration
    /// and post-answer replay.
    var inRace: Bool = false
    /// Called every time the kid unscrambles a word correctly.
    var onCorrect: () -> Void = {}
    /// Live check — see WordQuizGame.shouldSpeakPrompt.
    var shouldSpeakPrompt: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var word: String = GameWordPool.random()
    @State private var scrambled: [String] = []
    @State private var used: [Int] = []
    @State private var wrongIndex: Int? = nil
    @State private var colorIndex = randomGameColor()
    @State private var showCheer = false
    // Bumped on every new round / dismiss; delayed callbacks bail if stale.
    @State private var roundGen = 0
    // True during the brief lock-out after a wrong tile in race mode
    // (and during the post-completion advance window). Prevents the kid
    // from mashing tiles until they hit the right one.
    @State private var locked = false

    private var isIPad: Bool { sizeClass == .regular }
    private var bg: Color { gameColors[colorIndex % gameColors.count] }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: colorIndex)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)

                GameWordImage(word: word, size: isIPad ? 220 : 150)
                    .id(word)
                    .transition(.scale.combined(with: .opacity))

                Text("Unscramble!")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 10)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    ForEach(0..<word.count, id: \.self) { i in
                        slot(at: i)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 24)

                HStack(spacing: 12) {
                    ForEach(Array(scrambled.enumerated()), id: \.offset) { idx, letter in
                        GameLetterTile(
                            letter: letter.uppercased(),
                            size: isIPad ? 90 : 70,
                            dimmed: used.contains(idx),
                            wrong: wrongIndex == idx,
                            onTap: { tap(idx) }
                        )
                    }
                }
                .padding(.bottom, 40)
            }

            if showCheer { GameCheer(message: "Unscrambled!\n\(word.uppercased())") }
        }
        .onAppear { startRound(initial: true) }
        .onDisappear {
            roundGen &+= 1
            speech.stopAll()
        }
    }

    private var topBar: some View {
        HStack {
            if inRace {
                Color.clear.frame(width: 44, height: 44)
            } else {
                GameCloseButton { dismiss() }
            }
            Spacer()
            Text("Word Scramble")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button { speech.speak(word) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func slot(at i: Int) -> some View {
        let letters = Array(word.uppercased())
        let revealed = i < used.count
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.55), lineWidth: 3)
                .frame(width: isIPad ? 72 : 56, height: isIPad ? 86 : 70)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(revealed ? 0.25 : 0.05))
                )
            if revealed {
                Text(String(letters[i]))
                    .font(.system(size: isIPad ? 48 : 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func tap(_ idx: Int) {
        guard !locked else { return }
        guard !used.contains(idx) else { return }
        let needed = Array(word.lowercased())[used.count]
        let pressed = Character(scrambled[idx])
        if pressed == needed {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { used.append(idx) }
            // Queue rather than interrupt — see SpellItGame.
            speech.speak(String(pressed), interrupting: false)
            if used.count == word.count {
                let g = roundGen
                if inRace {
                    locked = true
                    onCorrect()
                    // Let the final letter finish, say "Correct!",
                    // then advance.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard g == roundGen else { return }
                        speech.speak("Correct!")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        guard g == roundGen else { return }
                        startRound(initial: false)
                    }
                } else {
                    withAnimation { showCheer = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        guard g == roundGen else { return }
                        speech.speak(word)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            guard g == roundGen else { return }
                            withAnimation { showCheer = false }
                            startRound(initial: false)
                        }
                    }
                }
            }
        } else {
            wrongIndex = idx
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let g = roundGen
            if inRace {
                // One shot per word — verbalize the right answer.
                locked = true
                speech.speak("Sorry. The correct answer is \(word).")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                    guard g == roundGen else { return }
                    startRound(initial: false)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard g == roundGen else { return }
                    wrongIndex = nil
                }
            }
        }
    }

    private func startRound(initial: Bool) {
        roundGen &+= 1
        let g = roundGen
        locked = false
        wrongIndex = nil
        let new = GameWordPool.random(excluding: initial ? nil : word)
        word = new
        used = []
        colorIndex = randomGameColor(excluding: colorIndex)
        // Scramble — make sure it's not already in correct order
        var letters = new.map { String($0) }
        if letters.count > 1 {
            repeat { letters.shuffle() } while letters.joined() == new
        }
        scrambled = letters
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard g == roundGen, shouldSpeakPrompt() else { return }
            speech.speak(new)
        }
    }
}
