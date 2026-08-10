import SwiftUI
import UIKit

struct CountItGame: View {
    @ObservedObject var speech: SpeechEngine
    /// True when launched inside a Race; replaces the big result screen
    /// with a fast auto-advance.
    var inRace: Bool = false
    /// Called every time the kid picks the right number.
    var onCorrect: () -> Void = {}
    /// Live check — see WordQuizGame.shouldSpeakPrompt.
    var shouldSpeakPrompt: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("mathAllowAdd") private var allowAdd = true
    @AppStorage("mathAllowSub") private var allowSub = true
    @AppStorage("mathShowDots") private var showDots = true

    @State private var card: MathCard? = nil
    @State private var answer: Int = 0
    @State private var choices: [Int] = []
    @State private var rightIndex: Int? = nil
    @State private var wrongIndex: Int? = nil
    @State private var locked = false
    @State private var misses = 0
    @State private var hintIndex: Int? = nil
    @State private var colorIndex = randomGameColor()
    @State private var showResult = false
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

                if let c = card {
                    cardView(c)
                } else {
                    Text("No math cards bundled.")
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 16)

                let cols = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { idx, n in
                        choiceTile(n: n, idx: idx)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }

            if showResult, let c = card {
                resultScreen(c)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onAppear { newRound() }
        .onDisappear {
            roundGen &+= 1
            speech.stopAll()
        }
    }

    private func resultScreen(_ c: MathCard) -> some View {
        let lines = c.a.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let equation = String(lines.first ?? "")
        let visual = lines.count > 1 ? String(lines.last ?? "") : ""

        return ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 22) {
                Text("⭐️")
                    .font(.system(size: isIPad ? 130 : 96))
                    .scaleEffect(showResult ? 1 : 0.4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.55), value: showResult)

                Text("That's right!")
                    .font(.system(size: isIPad ? 44 : 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(equation)
                    .font(.system(size: isIPad ? 88 : 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                if !visual.isEmpty && showDots {
                    Text(visual)
                        .font(.system(size: isIPad ? 64 : 44, weight: .black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 24)
                }

                Button { advance() } label: {
                    HStack(spacing: 10) {
                        Text("Next")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 22, weight: .black))
                    }
                    .foregroundStyle(bg)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 44)
                    .background(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 28)
            .frame(maxWidth: isIPad ? 560 : .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(bg.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(.white.opacity(0.55), lineWidth: 4)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 8)
            )
            .padding(.horizontal, 24)
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) { showResult = false }
        let g = roundGen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard g == roundGen else { return }
            newRound()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if inRace {
                Color.clear.frame(width: 44, height: 44)
            } else {
                GameCloseButton { dismiss() }
            }
            Button { showDots.toggle() } label: {
                Text(showDots ? "•••" : "123")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 36)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showDots ? "Hide the counting dots" : "Show the counting dots")
            Spacer()
            Text("Count It")
                .font(.system(size: 22 * KidMetrics.textScale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                if let c = card { speech.speak(MathCardStore.spokenPrompt(from: c)) }
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

    private func cardView(_ c: MathCard) -> some View {
        let lines = c.q.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let equation = String(lines.first ?? "")
        let visual = lines.count > 1 ? String(lines.last ?? "") : ""

        return VStack(spacing: 18) {
            Text(equation)
                .font(.system(size: isIPad ? 72 : 56, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            if !visual.isEmpty && showDots {
                Text(visual)
                    .font(.system(size: isIPad ? 60 : 44, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.white.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                )
        )
        .padding(.horizontal, 18)
        .id(c.q)
    }

    private func choiceTile(n: Int, idx: Int) -> some View {
        let mark: AnswerMark.State =
            wrongIndex == idx ? .wrong : (rightIndex == idx ? .right : .none)
        return Button { pick(n: n, idx: idx) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(hintIndex == idx ? Color.white.opacity(0.5)
                                           : Color.white.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                    )
                Text("\(n)")
                    .font(.system(size: isIPad ? 120 : 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(height: isIPad ? 210 : 110)
            .answerMark(mark)
        }
        .buttonStyle(KidTileButtonStyle())
        .accessibilityLabel("\(n)")
    }

    private func pick(n: Int, idx: Int) {
        guard !locked else { return }
        if n == answer {
            locked = true
            rightIndex = idx
            hintIndex = nil
            Haptics.success()
            if inRace {
                // "Correct!" + race score bump, then the next card. Was
                // 0.85s — too quick for the answer to land.
                speech.speak("Correct!")
                onCorrect()
                let g = roundGen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard g == roundGen else { return }
                    newRound()
                }
            } else {
                if let c = card {
                    let spoken = MathCardStore.spokenPrompt(from: c) + " equals \(n)"
                    speech.speak(spoken)
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    showResult = true
                }
            }
        } else {
            // No skip, no apology — see SpellItGame.tap. After a second
            // miss the right number is highlighted and spoken, but the
            // child still taps it.
            wrongIndex = idx
            Haptics.wrong()
            misses += 1
            let g = roundGen
            if misses >= 2 {
                hintIndex = choices.firstIndex(of: answer)
                speech.speak("\(answer)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard g == roundGen else { return }
                wrongIndex = nil
            }
        }
    }

    private func newRound() {
        roundGen &+= 1
        let g = roundGen
        let pool = MathCardStore.filtered(allowAdd: allowAdd, allowSub: allowSub)
        guard let pick = pool.randomElement(),
              let ans = MathCardStore.answerNumber(from: pick) else {
            card = nil; return
        }
        card = pick
        answer = ans
        rightIndex = nil
        wrongIndex = nil
        locked = false
        misses = 0
        hintIndex = nil
        Haptics.prepare()
        colorIndex = randomGameColor(excluding: colorIndex)

        // 4 distinct choices near the answer
        var set = Set<Int>([ans])
        while set.count < 4 {
            let delta = Int.random(in: -3...3)
            let n = max(0, min(15, ans + delta))
            if n != ans { set.insert(n) }
        }
        choices = Array(set).shuffled()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard g == roundGen, shouldSpeakPrompt() else { return }
            speech.speak(MathCardStore.spokenPrompt(from: pick))
        }
    }
}
