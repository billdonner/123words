import SwiftUI

/// "My Words" — every word the child has mastered, in colour; the rest as
/// grey outlines waiting to be filled in.
///
/// This is the counterweight to the race score. A single number that
/// resets to zero every run is a poor reward for this age: it's
/// comparative, it vanishes, and a child who scores 6 against a 10-point
/// threshold is told they failed. A collection only ever grows, nobody
/// scores zero, and it's the same data the Leitner scheduler already
/// keeps — so it doubles as the progress report parents had no way to see.
struct StickerBookView: View {
    @ObservedObject var speech: SpeechEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Alphabetical rather than teaching order: a child looking for the
    // one they just earned should find it in a stable place.
    private static let words: [String] = WordStore.wordsAlphabetical.filter {
        UIImage(named: $0) != nil || wordDefinitiveSymbol[$0] != nil
    }

    private var isIPad: Bool { sizeClass == .regular }
    private var mastered: [String] { Self.words.filter { WordProgress.shared.isMastered($0) } }

    var body: some View {
        let side: CGFloat = 96 * KidMetrics.scale
        let columns = [GridItem(.adaptive(minimum: side, maximum: side * 1.5),
                                spacing: isIPad ? 18 : 12)]
        NavigationStack {
            ScrollView {
                header
                LazyVGrid(columns: columns, spacing: isIPad ? 18 : 12) {
                    ForEach(Array(Self.words.enumerated()), id: \.element) { idx, word in
                        StickerCell(
                            word: word,
                            color: gameColors[idx % gameColors.count],
                            earned: WordProgress.shared.isMastered(word),
                            side: side
                        ) {
                            speech.speak(word, interrupting: false)
                        }
                    }
                }
                .padding(isIPad ? 22 : 14)
            }
            .navigationTitle("My Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("⭐️ \(mastered.count)")
                .font(.system(size: isIPad ? 56 : 44, weight: .black, design: .rounded))
            Text(mastered.isEmpty
                 ? "Play a game to start collecting!"
                 : "words you know, out of \(Self.words.count)")
                .font(.system(size: isIPad ? 18 : 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .padding(.horizontal, 20)
    }
}

private struct StickerCell: View {
    let word: String
    let color: Color
    let earned: Bool
    let side: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: side * 0.18)
                        .fill(earned ? color : Color.secondary.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: side * 0.18)
                                .strokeBorder(earned ? .white.opacity(0.5)
                                                     : Color.secondary.opacity(0.3),
                                              lineWidth: 3)
                        )
                    GameWordImage(word: word, size: side * 0.74)
                        // Not-yet-earned stickers keep their shape but
                        // lose their colour, so the child can see what's
                        // still out there without it reading as a failure.
                        .saturation(earned ? 1 : 0)
                        .opacity(earned ? 1 : 0.35)
                    if earned {
                        Text("⭐️")
                            .font(.system(size: side * 0.24))
                            .offset(x: side * 0.32, y: -side * 0.32)
                    }
                }
                .frame(height: side)

                Text(kidCase(word))
                    .font(.system(size: side * 0.16, weight: .black, design: .rounded))
                    .foregroundStyle(earned ? .primary : .secondary)
            }
        }
        .buttonStyle(KidTileButtonStyle())
        .accessibilityLabel(word)
        .accessibilityValue(earned ? "collected" : "not collected yet")
    }
}
