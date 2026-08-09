import SwiftUI
import UIKit

// The one palette for the whole app — backgrounds for the reader and
// every game. Each colour is tuned to a relative luminance of ≤0.27 so
// that solid white text clears the WCAG 3:1 bar for large text (every
// kid-facing string here is ≥18pt and bold). The old palette ran as
// bright as L=0.56 (yellow), which put white at 1.71:1 — illegible.
//
// Corollary, and the reason the numbers stay honest: white at 0.9 alpha
// is already only ~3.0:1 on these, and 0.8 fails outright. Kid-facing
// text must be solid white. Use `.opacity()` on white for decoration
// (borders, fills) — never for words a child has to read.
let gameColors: [Color] = [
    Color(red: 0.949, green: 0.332, blue: 0.332),   // red
    Color(red: 0.788, green: 0.473, blue: 0.079),   // orange
    Color(red: 0.248, green: 0.620, blue: 0.289),   // green
    Color(red: 0.250, green: 0.550, blue: 1.000),   // blue
    Color(red: 0.700, green: 0.300, blue: 0.900),   // purple
    Color(red: 0.955, green: 0.287, blue: 0.573),   // pink
    Color(red: 0.085, green: 0.595, blue: 0.722),   // cyan
    Color(red: 0.670, green: 0.529, blue: 0.071),   // yellow
]

func randomGameColor(excluding: Int? = nil) -> Int {
    var idx: Int
    repeat { idx = Int.random(in: 0..<gameColors.count) }
    while idx == excluding && gameColors.count > 1
    return idx
}

/// Scales a tap target down on press. Children get no audio for up to
/// half a second after a tap (and none at all while a round is locked),
/// so without this a tap that landed and a tap that missed look
/// identical. Doubles as the `isButton` trait for VoiceOver, which bare
/// `.onTapGesture` never provided.
struct KidTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

// A 123words-style letter tile — white-on-color rounded square
struct GameLetterTile: View {
    let letter: String
    var size: CGFloat = 80
    var highlighted: Bool = false
    var dimmed: Bool = false
    var wrong: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: { face }
            .buttonStyle(KidTileButtonStyle())
            .disabled(onTap == nil)
            .accessibilityLabel(letter)
            .accessibilityValue(dimmed ? "used" : "")
    }

    private var face: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(highlighted ? Color.yellow
                      : (wrong ? Color.red.opacity(0.85)
                                : (dimmed ? Color.black.opacity(0.28)
                                          : Color.white.opacity(0.25))))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .strokeBorder(.white.opacity(dimmed ? 0.3 : 0.45), lineWidth: 3)
                )
            // A used tile used to be white-at-0.25 on white-at-0.08 —
            // 1.09:1, i.e. invisible. Knowing which letters are spent is
            // the whole mechanic in Scramble, so a used tile now goes
            // dark and takes a check mark rather than just fading.
            if dimmed {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text(letter)
                    .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                    .foregroundStyle(highlighted ? .black : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(highlighted ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: highlighted)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: wrong)
    }
}

// A close (X) button styled like TopBarButton
struct GameCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.22))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

// A celebration overlay that briefly shows on a correct answer
struct GameCheer: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Text("⭐️")
                .font(.system(size: 80))
            Text(message)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// Word pool helpers — only words that have pictures
enum GameWordPool {
    static var withImages: [String] {
        WordStore.words.filter {
            UIImage(named: $0) != nil || wordDefinitiveSymbol[$0] != nil
        }
    }
    static func random(length: Int? = nil, excluding: String? = nil) -> String {
        var pool = withImages
        if let length { pool = pool.filter { $0.count == length } }
        if pool.isEmpty { pool = withImages }
        var pick: String
        repeat { pick = pool.randomElement() ?? "cat" }
        while pick == excluding && pool.count > 1
        return pick
    }
    /// Returns exactly `n` words (callers size grids/boards for `n`, so this
    /// must never silently return fewer). Prefers distinct words; the length
    /// filter is only applied if it can still satisfy `n`; if the asset pool
    /// is too small it pads by cycling rather than under-filling.
    static func randomDistinct(count n: Int, length: Int? = nil) -> [String] {
        let need = max(n, 1)
        var pool = withImages
        if let length {
            let filtered = pool.filter { $0.count == length }
            if filtered.count >= need { pool = filtered }
        }
        guard !pool.isEmpty else { return Array(repeating: "cat", count: need) }
        pool.shuffle()
        var result = Array(pool.prefix(need))
        var i = 0
        while result.count < need {
            result.append(pool[i % pool.count])
            i += 1
        }
        return result
    }
}

// The picture for a word — reuses the same provenance lookups as ContentView
struct GameWordImage: View {
    let word: String
    var size: CGFloat = 160

    var body: some View {
        ZStack {
            if let icon = wordDefinitiveSymbol[word] {
                if let bg = icon.bg {
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .fill(bg.opacity(0.88))
                }
                Image(systemName: icon.symbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(icon.bg != nil ? icon.fg : icon.fg.opacity(0.85))
                    .padding(size * 0.18)
            } else if UIImage(named: word) != nil {
                Image(word)
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .resizable().scaledToFit()
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(size * 0.25)
            }
        }
        .frame(width: size, height: size)
    }
}
