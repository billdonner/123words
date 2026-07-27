import SwiftUI

private let kidGalleryColors: [Color] = [
    Color(red: 1.0, green: 0.35, blue: 0.35),
    Color(red: 1.0, green: 0.60, blue: 0.10),
    Color(red: 0.30, green: 0.75, blue: 0.35),
    Color(red: 0.25, green: 0.55, blue: 1.00),
    Color(red: 0.70, green: 0.30, blue: 0.90),
    Color(red: 1.00, green: 0.30, blue: 0.60),
    Color(red: 0.10, green: 0.70, blue: 0.85),
    Color(red: 0.95, green: 0.75, blue: 0.10),
]

struct KidGalleryView: View {
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
                                       cellHeight: isIPad ? 180 : 110, fontSize: isIPad ? 22 : 15)
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

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.85))
                KidGalleryImage(word: word)
                    .padding(cellHeight * 0.09)
            }
            .frame(height: cellHeight)

            Text(word.uppercased())
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
        }
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
