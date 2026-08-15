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

/// Sizing multiplier relative to a 393pt-wide iPhone.
///
/// Every size in the app was tuned on an iPhone and then bumped once for
/// "iPad" — a single binary guess covering everything from an 8.3-inch
/// mini to a 13-inch Pro. On the big Pro that left near-iPhone-sized
/// artwork adrift in a very large screen. Deriving the multiplier from
/// the real width handles every iPad, and split-screen, on its own.
func kidScale(_ width: CGFloat) -> CGFloat {
    min(max(width / 393.0, 1.0), 2.6)
}

/// One place that decides how big things are, so screens stop each
/// inventing their own answer.
///
/// The rule that matters: scale off the **shorter** screen dimension, so
/// rotating the iPad doesn't change the size of anything. Scaling off the
/// raw width meant a 10.9-inch iPad jumped a whole size class on rotation
/// — text grew ~25% and overflowed the screen.
enum KidMetrics {
    /// Shorter side of the screen — stable across rotation.
    /// (Uses the main screen, so it doesn't track iPad split-screen; the
    /// app is meant to be used full-screen by a child.)
    static var reference: CGFloat {
        let b = UIScreen.main.bounds
        return min(b.width, b.height)
    }

    /// Artwork multiplier against a 393pt iPhone.
    static var scale: CGFloat { kidScale(reference) }

    /// Text multiplier. Half the artwork increase: 2.6x is right for a
    /// picture and shouting for a heading.
    static var textScale: CGFloat { 1 + (scale - 1) * 0.5 }

    /// A comfortable line length for body copy. Capped in absolute points
    /// — scaling the measure *and* the type compounds, which is how the
    /// onboarding ended up running the full width of a 13-inch iPad.
    static var readableWidth: CGFloat { min(700, 560 * textScale) }

    /// Orientation-stable scale from a local geometry, for views that
    /// already have a GeometryReader.
    static func scale(in size: CGSize) -> CGFloat {
        kidScale(min(size.width, size.height))
    }
}

func randomGameColor(excluding: Int? = nil) -> Int {
    if let fixed = UserDefaults.standard.object(forKey: "screenshotColorIndex") as? NSNumber {
        return max(0, min(gameColors.count - 1, fixed.intValue))
    }
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

/// Haptics. The generators are held for the life of the app and kept
/// primed: constructing a `UINotificationFeedbackGenerator` at the tap
/// site (as every game used to) means the first haptic of a session is
/// late or dropped entirely.
enum Haptics {
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() { notify.prepare() }
    static func success() { notify.notificationOccurred(.success); notify.prepare() }
    /// Deliberately `.warning`, not `.error` — a wrong tap by a 4-year-old
    /// is a normal part of learning, not a fault condition.
    static func wrong()   { notify.notificationOccurred(.warning); notify.prepare() }
}

/// Marks a choice tile right or wrong in a way the background can't
/// swallow. The games pick their background at random from `gameColors`,
/// so a green "correct" tint landed on a green background about one round
/// in four at 1.17:1 — feedback the child could not see, on screens that
/// auto-advance in about a second. A white ring plus a glyph reads on all
/// eight backgrounds.
struct AnswerMark: ViewModifier {
    enum State { case none, right, wrong }
    let state: State
    var corner: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white, lineWidth: state == .none ? 0 : 7)
            )
            .overlay(alignment: .topTrailing) {
                if state != .none {
                    Image(systemName: state == .right ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white, state == .right
                                         ? Color(red: 0.05, green: 0.45, blue: 0.15)
                                         : Color(red: 0.6, green: 0.05, blue: 0.05))
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: state)
    }
}

extension View {
    func answerMark(_ state: AnswerMark.State, corner: CGFloat = 22) -> some View {
        modifier(AnswerMark(state: state, corner: corner))
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

/// Renders a word in the case the parent chose, and never lower-cases the
/// pronoun "I" — the reader used to print it as "i", which is a literacy
/// error for an app to be modelling.
///
/// The five games all hard-coded `.uppercased()`, so a child switched to
/// lowercase in the reader was hit with capitals the moment they opened a
/// game, breaking exactly the case-invariance mapping the toggle exists to
/// build. Games are short-lived views, so reading the default directly is
/// enough — the setting can only change while no game is on screen.
func kidCase(_ word: String) -> String {
    if word == "I" { return "I" }
    let upper = UserDefaults.standard.object(forKey: "isUppercase") as? Bool ?? true
    return upper ? word.uppercased() : word.lowercased()
}

// Word pool helpers — only words that have pictures
enum GameWordPool {
    /// One-letter words are excluded: "spelling" a single letter is a null
    /// trial, and both spelling games size their UI off `word.count`.
    static var withImages: [String] {
        WordStore.words.filter {
            $0.count >= 2 && (UIImage(named: $0) != nil || wordDefinitiveSymbol[$0] != nil)
        }
    }

    /// Words the spelling games may use. Heart words (`two`, `eye`, `who`)
    /// are irregular by definition, so asking a child to build them
    /// letter-by-letter teaches a spelling-sound mapping that isn't true.
    static var spellable: [String] {
        withImages.filter { WordStore.decodableWords.contains($0) }
    }

    static func random(length: Int? = nil,
                       excluding: String? = nil,
                       decodableOnly: Bool = false) -> String {
        if let fixed = UserDefaults.standard.string(forKey: "screenshotGameWord"),
           withImages.contains(fixed),
           length.map({ fixed.count == $0 }) ?? true,
           !decodableOnly || spellable.contains(fixed) {
            return fixed
        }
        var pool = decodableOnly ? spellable : withImages
        if let length { pool = pool.filter { $0.count == length } }
        if pool.isEmpty { pool = withImages }
        // Scheduled, not uniform — see WordProgress. Uniform sampling over
        // the whole list meant a child essentially never met a word twice.
        return WordProgress.shared.scheduledWord(from: pool, excluding: excluding)
    }
    /// Returns exactly `n` words (callers size grids/boards for `n`, so this
    /// must never silently return fewer). Prefers distinct words; the length
    /// filter is only applied if it can still satisfy `n`; if the asset pool
    /// is too small it pads by cycling rather than under-filling.
    static func randomDistinct(count n: Int, length: Int? = nil) -> [String] {
        let need = max(n, 1)
        if let fixed = UserDefaults.standard.stringArray(forKey: "screenshotGameWords") {
            let valid = fixed.filter { withImages.contains($0) }
            if valid.count >= need { return Array(valid.prefix(need)) }
        }
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
