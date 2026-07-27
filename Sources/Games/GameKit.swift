import SwiftUI
import UIKit

// Shared palette — matches ContentView.bgColors
let gameColors: [Color] = [
    Color(red: 1.0, green: 0.35, blue: 0.35),
    Color(red: 1.0, green: 0.60, blue: 0.10),
    Color(red: 0.30, green: 0.75, blue: 0.35),
    Color(red: 0.25, green: 0.55, blue: 1.00),
    Color(red: 0.70, green: 0.30, blue: 0.90),
    Color(red: 1.00, green: 0.30, blue: 0.60),
    Color(red: 0.10, green: 0.70, blue: 0.85),
    Color(red: 0.95, green: 0.75, blue: 0.10),
]

func randomGameColor(excluding: Int? = nil) -> Int {
    var idx: Int
    repeat { idx = Int.random(in: 0..<gameColors.count) }
    while idx == excluding && gameColors.count > 1
    return idx
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
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(highlighted ? Color.yellow
                      : (wrong ? Color.red.opacity(0.85)
                                : Color.white.opacity(dimmed ? 0.08 : 0.25)))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .strokeBorder(.white.opacity(dimmed ? 0.15 : 0.45), lineWidth: 3)
                )
            Text(letter)
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundStyle(highlighted ? .black : (dimmed ? .white.opacity(0.25) : .white))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .scaleEffect(highlighted ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: highlighted)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: wrong)
        .onTapGesture { onTap?() }
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
