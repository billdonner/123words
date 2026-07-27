import SwiftUI

// Re-use provenance logic from ContentView without the animation state
private func provenanceFor(_ word: String) -> ImageProvenance {
    if wordDefinitiveSymbol[word] != nil           { return .sfSymbol(definitive: true) }
    if UIImage(named: word) != nil {
        return openMojiWords.contains(word) ? .openMoji : .aiGenerated
    }
    if wordFallbackSymbol[word.lowercased()] != nil { return .sfSymbol(definitive: false) }
    return .noImage
}

private enum GalleryFilter: String, CaseIterable {
    case all      = "All"
    case ai       = "AI"
    case emoji    = "Emoji"
    case symbol   = "Symbol"
    case missing  = "Missing"
}

struct GalleryView: View {
    @State private var filter: GalleryFilter = .all
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 10)
    ]

    private var displayedWords: [String] {
        let base: [String]
        switch filter {
        case .all:     base = WordStore.words
        case .ai:      base = WordStore.words.filter { provenanceFor($0) == .aiGenerated }
        case .emoji:   base = WordStore.words.filter { provenanceFor($0) == .openMoji }
        case .symbol:  base = WordStore.words.filter {
            if case .sfSymbol = provenanceFor($0) { return true }; return false
        }
        case .missing: base = WordStore.words.filter { provenanceFor($0) == .noImage }
        }
        if searchText.isEmpty { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            Picker("Filter", selection: $filter) {
                ForEach(GalleryFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Text("\(displayedWords.count) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(displayedWords, id: \.self) { word in
                        GalleryCell(word: word)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("Image Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search words…")
    }
}

private struct GalleryCell: View {
    let word: String

    private var prov: ImageProvenance { provenanceFor(word) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Image area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))

                    GalleryImageContent(word: word)
                        .padding(8)
                }
                .frame(height: 100)

                // Provenance badge
                Text(prov.icon)
                    .font(.system(size: 14))
                    .padding(3)
                    .background(prov.badgeColor.opacity(0.85))
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }

            Text(word)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(prov.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(prov.badgeColor)
        }
    }
}

private struct GalleryImageContent: View {
    let word: String

    var body: some View {
        if let icon = wordDefinitiveSymbol[word] {
            Image(systemName: icon.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(icon.fg.opacity(0.85))
        } else if UIImage(named: word) != nil {
            Image(word)
                .resizable()
                .scaledToFit()
        } else {
            let symbol = wordFallbackSymbol[word.lowercased()] ?? "person.fill"
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.gray.opacity(0.5))
                .overlay(alignment: .topLeading) {
                    Text("?")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
        }
    }
}
