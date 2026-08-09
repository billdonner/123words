import SwiftUI
import UIKit

private enum CardFace { case word, picture }

private struct MatchCard: Identifiable {
    let id = UUID()
    let word: String
    let face: CardFace
    var matched: Bool = false
    var flipped: Bool = false
}

struct MemoryMatchGame: View {
    @ObservedObject var speech: SpeechEngine
    /// True when launched inside a Race; suppresses celebration overlays.
    var inRace: Bool = false
    /// Called once per matched pair.
    var onCorrect: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var cards: [MatchCard] = []
    @State private var firstFlipped: Int? = nil
    @State private var locked = false
    @State private var colorIndex = randomGameColor()
    @State private var showCheer = false
    // Bumped on every new round / dismiss; delayed callbacks bail if stale.
    @State private var roundGen = 0
    @AppStorage("memoryBoardSize") private var boardSize: Int = 4  // 4 = 4 pairs, 8 = 8 pairs

    private var isIPad: Bool { sizeClass == .regular }
    private var bg: Color { gameColors[colorIndex % gameColors.count] }
    private var pairCount: Int { boardSize }
    private var columns: Int { boardSize == 8 ? 4 : 2 }   // EASY: 2×4 tall, HARD: 4×4
    private var rows: Int { (pairCount * 2) / columns }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                bg.ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: colorIndex)

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 4)

                    sizePicker

                    Spacer(minLength: 8)

                    let spacing: CGFloat = boardSize == 8 ? 10 : 18
                    let hPad: CGFloat = 16
                    let availW = geo.size.width - hPad * 2 - spacing * CGFloat(columns - 1)
                    // Also cap by available height so a tall 2×4 grid fits without scrolling
                    let availH = geo.size.height - 220 - spacing * CGFloat(rows - 1)
                    let tileByW = availW / CGFloat(columns)
                    let tileByH = availH / CGFloat(rows)
                    let tile = max(60, min(tileByW, tileByH))
                    let cols = Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: columns)
                    LazyVGrid(columns: cols, spacing: spacing) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                            cardView(card, idx: idx, size: tile)
                        }
                    }
                    .padding(.horizontal, hPad)

                    Spacer()
                }

                if showCheer { GameCheer(message: "All matched!\nGreat job!") }
            }
        }
        .onAppear { newRound() }
        .onDisappear {
            roundGen &+= 1
            speech.stopAll()
        }
    }

    private var sizePicker: some View {
        HStack(spacing: 10) {
            ForEach([4, 8], id: \.self) { n in
                Button {
                    guard boardSize != n else { return }
                    boardSize = n
                    newRound()
                } label: {
                    Text(n == 4 ? "EASY · 8" : "HARD · 16")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(.white.opacity(boardSize == n ? 0.32 : 0.14))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(boardSize == n ? 0.6 : 0.3),
                                                  lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
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
            Text("Memory Match")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button { newRound() } label: {
                Image(systemName: "arrow.clockwise")
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

    private func cardView(_ card: MatchCard, idx: Int, size: CGFloat) -> some View {
        let revealed = card.flipped || card.matched
        let corner = size * 0.18
        return ZStack {
            // Back face — visible when face-down
            ZStack {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                    )
                Text("?")
                    .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .opacity(revealed ? 0 : 1)

            // Front face — visible when face-up
            ZStack {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                    )
                if card.face == .word {
                    Text(card.word.uppercased())
                        .font(.system(size: size * 0.32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(6)
                } else {
                    GameWordImage(word: card.word, size: size * 0.85)
                }
            }
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.85)
        }
        .frame(width: size, height: size)
        .opacity(card.matched ? 0.55 : 1.0)
        .scaleEffect(card.matched ? 0.94 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: card.flipped)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: card.matched)
        .onTapGesture { flip(idx) }
    }

    private func flip(_ idx: Int) {
        guard !locked else { return }
        guard !cards[idx].matched, !cards[idx].flipped else { return }
        cards[idx].flipped = true

        // Queued so rapid flipping doesn't reduce every word to a syllable.
        if cards[idx].face == .word { speech.speak(cards[idx].word, interrupting: false) }

        if let first = firstFlipped {
            locked = true
            let a = cards[first], b = cards[idx]
            let g = roundGen
            if a.word == b.word && a.face != b.face {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard g == roundGen else { return }
                    cards[first].matched = true
                    cards[idx].matched = true
                    firstFlipped = nil
                    locked = false
                    if inRace {
                        // Pair matched — +1 to the shared race score.
                        // Skip the on-match speak: the kid already heard
                        // the word when they flipped the word card.
                        onCorrect()
                    } else {
                        speech.speak(a.word)
                    }
                    if cards.allSatisfy({ $0.matched }) {
                        if inRace {
                            // No cheer overlay — reshuffle a fresh board
                            // straight away so the kid can keep scoring.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                guard g == roundGen else { return }
                                newRound()
                            }
                        } else {
                            withAnimation { showCheer = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                guard g == roundGen else { return }
                                withAnimation { showCheer = false }
                                newRound()
                            }
                        }
                    }
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard g == roundGen else { return }
                    cards[first].flipped = false
                    cards[idx].flipped = false
                    firstFlipped = nil
                    locked = false
                }
            }
        } else {
            firstFlipped = idx
        }
    }

    private func newRound() {
        roundGen &+= 1
        let words = GameWordPool.randomDistinct(count: pairCount)
        var deck: [MatchCard] = []
        for w in words {
            deck.append(MatchCard(word: w, face: .word))
            deck.append(MatchCard(word: w, face: .picture))
        }
        deck.shuffle()
        cards = deck
        firstFlipped = nil
        locked = false
        colorIndex = randomGameColor(excluding: colorIndex)
    }
}
