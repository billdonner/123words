import SwiftUI

// Third copy of the palette, now folded into the one in GameKit.swift.
private let kidGalleryColors = gameColors

struct KidGalleryView: View {
    @ObservedObject var speech: SpeechEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static var words: [String] = {
        WordStore.words
            .filter { UIImage(named: $0) != nil || wordDefinitiveSymbol[$0] != nil }
            .sorted()
    }()

    private var isIPad: Bool { sizeClass == .regular }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: isIPad ? 180 : 110,
                                          maximum: isIPad ? 260 : 150), spacing: isIPad ? 20 : 12)]
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: isIPad ? 20 : 12) {
                    ForEach(Array(Self.words.enumerated()), id: \.element) { idx, word in
                        KidGalleryCell(word: word, color: kidGalleryColors[idx % kidGalleryColors.count],
                                       cellHeight: isIPad ? 180 : 110, fontSize: isIPad ? 22 : 15) {
                            speech.speak(word, interrupting: false)
                        }
                    }
                }
                .padding(isIPad ? 24 : 14)
            }
            .navigationTitle("Picture Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}

private struct KidGalleryCell: View {
    let word: String
    let color: Color
    var cellHeight: CGFloat = 110
    var fontSize: CGFloat = 15
    // A wall of ~200 pictures that did nothing when tapped. Children tap
    // every one of them, so each now says its word.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.85))
                    KidGalleryImage(word: word)
                        .padding(cellHeight * 0.09)
                }
                .frame(height: cellHeight)

                Text(kidCase(word))
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(KidTileButtonStyle())
        .accessibilityLabel(word)
        .accessibilityHint("Say this word")
    }
}

private struct KidGalleryImage: View {
    let word: String

    var body: some View {
        if let icon = wordDefinitiveSymbol[word] {
            Image(systemName: icon.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
        } else if UIImage(named: word) != nil {
            Image(word)
                .resizable()
                .scaledToFit()
        }
    }
}
