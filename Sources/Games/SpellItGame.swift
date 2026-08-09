import SwiftUI
import UIKit

struct SpellItGame: View {
    @ObservedObject var speech: SpeechEngine
    /// True when launched inside a Race; suppresses the long celebration
    /// and post-answer replay.
    var inRace: Bool = false
    /// Called every time the kid completes a word correctly.
    var onCorrect: () -> Void = {}
    /// Live check: is this game the currently-visible tab in race
    /// mode? Guards the deferred prompt-speak so an off-screen game
    /// doesn't audibly call out its word while the kid is on another
    /// tab. See WordQuizGame.shouldSpeakPrompt for the full story.
    var shouldSpeakPrompt: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var word: String = GameWordPool.random()
    @State private var typed: [Int] = []          // indices into keyboard
    @State private var keyboard: [String] = []
    @State private var wrongIndex: Int? = nil
    @State private var colorIndex = randomGameColor()
    @State private var showCheer = false
    @State private var streak = 0
    // Bumped on every new round / dismiss; delayed callbacks bail if stale.
    @State private var roundGen = 0
    // True during the brief lock-out after a wrong letter in race mode
    // (and during the post-completion advance window). Prevents further
    // taps so the kid can't mash letters until they hit the right one.
    @State private var locked = false
    // Wrong taps on the current letter, and the tile to light up once the
    // child has missed twice (prompt fade — see `tap`).
    @State private var misses = 0
    @State private var hintIndex: Int? = nil

    private var isIPad: Bool { sizeClass == .regular }
    private var bg: Color { gameColors[colorIndex % gameColors.count] }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            bg.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: colorIndex)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)

                GameWordImage(word: word, size: isIPad ? 220 : 150)
                    .id(word)
                    .transition(.scale.combined(with: .opacity))

                Text("Spell the word")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 10)

                Spacer(minLength: 8)

                // Answer slots
                HStack(spacing: 10) {
                    ForEach(0..<word.count, id: \.self) { i in
                        slot(at: i)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 12)

                // Keyboard of letters (word letters + distractors).
                // The tile size has to come from the real column width:
                // a hard 60pt tile overflowed a 48.2pt column on 375pt
                // devices, so tiles overlapped by ~1.8pt each side and
                // the later tile in the ForEach won the hit test — a tap
                // on one letter's visible edge registered as its
                // neighbour's, which in Race mode ended the word.
                let hPad: CGFloat = 18
                let gap: CGFloat = 10
                let cols = min(keyboard.count, isIPad ? 7 : 6)
                let avail = geo.size.width - hPad * 2 - gap * CGFloat(cols - 1)
                let tile = min(isIPad ? 80 : 60, floor(avail / CGFloat(cols)))
                let kbCols = Array(repeating: GridItem(.fixed(tile), spacing: gap), count: cols)
                LazyVGrid(columns: kbCols, spacing: gap) {
                    ForEach(Array(keyboard.enumerated()), id: \.offset) { idx, letter in
                        GameLetterTile(
                            letter: kidCase(letter),
                            size: tile,
                            highlighted: hintIndex == idx,
                            dimmed: typed.contains(idx),
                            wrong: wrongIndex == idx,
                            onTap: { tap(idx) }
                        )
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.bottom, 30)
            }

            if showCheer { GameCheer(message: "Yay!\nYou spelled \(kidCase(word))!") }
        }
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
            Text("Spell It")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                speech.speak(word)
            } label: {
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
        let letters = Array(kidCase(word))
        let revealed = i < typed.count
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
        guard !typed.contains(idx) else { return }
        let nextNeeded = Array(word.lowercased())[typed.count]
        let pressed = Character(keyboard[idx])
        if pressed == nextNeeded {
            misses = 0
            hintIndex = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                typed.append(idx)
            }
            // Queue rather than interrupt — fast tapping used to clip
            // every letter to its first phoneme.
            speech.speak(String(pressed), interrupting: false)
            if typed.count == word.count {
                streak += 1
                locked = true
                Haptics.success()
                WordProgress.shared.recordCorrect(word)
                let g = roundGen
                if inRace {
                    onCorrect()
                    // Let the final letter speech finish (~0.4s), then
                    // say "Correct!", then advance. stopAll inside the
                    // next speak() handles the chain naturally.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard g == roundGen else { return }
                        speech.speak("Correct!")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
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
            // A wrong letter used to end the word outright in Race mode:
            // lock out, say "Sorry. The correct answer is cat", and swap
            // in a new word 1.9s later. The child never produced the
            // right answer, so the trial was terminated on the error —
            // the opposite of model → lead → test, where the trial is
            // completed by the learner's own correct response.
            //
            // Now: the tile shakes, nothing is taken away, and on a
            // second miss the correct tile lights up and says its name.
            // The child still has to tap it themselves.
            wrongIndex = idx
            Haptics.wrong()
            misses += 1
            WordProgress.shared.recordMiss(word)
            let g = roundGen
            if misses >= 2 {
                hintIndex = keyboard.indices.first {
                    Character(keyboard[$0]) == nextNeeded && !typed.contains($0)
                }
                speech.speak(String(nextNeeded))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard g == roundGen else { return }
                wrongIndex = nil
            }
        }
    }

    private func startRound(initial: Bool) {
        roundGen &+= 1
        let g = roundGen
        locked = false
        wrongIndex = nil
        misses = 0
        hintIndex = nil
        Haptics.prepare()
        // Heart words are irregular, so they never appear in a game that
        // asks the child to build them letter by letter.
        let new = GameWordPool.random(excluding: initial ? nil : word, decodableOnly: true)
        word = new
        typed = []
        colorIndex = randomGameColor(excluding: colorIndex)
        keyboard = makeKeyboard(for: new)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard g == roundGen, shouldSpeakPrompt() else { return }
            speech.speak(new)
        }
    }

    // Word letters + a few distractors, shuffled
    private func makeKeyboard(for w: String) -> [String] {
        var letters = w.lowercased().map { String($0) }
        let alphabet = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        let needed = max(0, (w.count <= 2 ? 4 : 6) - letters.count)
        for letter in alphabet.shuffled() where letters.count < letters.count + needed {
            if !letters.contains(letter) { letters.append(letter) }
            if letters.count >= w.count + needed { break }
        }
        return letters.shuffled()
    }
}
