import SwiftUI

// Parental-settings-only view: browse 3 AI-generated alternatives for each word image.
// Alternatives are bundled as {word}_a1, {word}_a2, {word}_a3 in the asset catalog.

struct AltGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    private static var words: [String] = {
        WordStore.words
            .filter { hasAnyAlt($0) }
            .sorted()
    }()

    private static func hasAnyAlt(_ word: String) -> Bool {
        UIImage(named: "\(word)_a1") != nil ||
        UIImage(named: "\(word)_a2") != nil ||
        UIImage(named: "\(word)_a3") != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if Self.words.isEmpty {
                    ContentUnavailableView(
                        "No Alternatives Yet",
                        systemImage: "photo.stack",
                        description: Text("Alternative images haven't been added to the app yet.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Self.words, id: \.self) { word in
                                AltWordRow(word: word)
                                Divider().padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Alternative Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct AltWordRow: View {
    let word: String

    private let altKeys = ["a1", "a2", "a3"]
    private let altLabels = ["Flat", "3D", "Watercolor"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Original
                    AltCell(imageName: word, label: "Current", isOriginal: true)

                    Divider().frame(height: 120)

                    // Alternatives
                    ForEach(Array(zip(altKeys, altLabels)), id: \.0) { key, label in
                        let name = "\(word)_\(key)"
                        if UIImage(named: name) != nil {
                            AltCell(imageName: name, label: label, isOriginal: false)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct AltCell: View {
    let imageName: String
    let label: String
    let isOriginal: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isOriginal
                          ? Color(.systemGray5)
                          : Color(red: 0.93, green: 0.96, blue: 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isOriginal ? Color.clear : Color.blue.opacity(0.3),
                                          lineWidth: 1.5)
                    )

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
            .frame(width: 120, height: 120)

            Text(label)
                .font(.system(size: 11, weight: isOriginal ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isOriginal ? .primary : Color.blue)
        }
    }
}
