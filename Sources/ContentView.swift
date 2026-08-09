import SwiftUI

// The reader draws from the same palette as the games — see
// `gameColors` in GameKit.swift for the contrast rationale.
private let bgColors = gameColors

struct ContentView: View {
    @StateObject private var wordStore   = WordStore()
    // Shared with the hub and every game. The reader used to build its
    // own, so two AVSpeechSynthesizers existed with two competing audio
    // session configurations and stopAll() on one could not silence the
    // other.
    @ObservedObject var speechEngine: SpeechEngine
    @AppStorage("showPlayButton")  private var showPlayButton  = false
    @AppStorage("showSpellButton") private var showSpellButton = false
    @State private var showSettings     = false
    @State private var showParentGate   = false
    @State private var gatePassed       = false
    @State private var showVoicePicker  = false
    @State private var showKidGallery   = false
    @Environment(\.dismiss) private var dismissReader
    @State private var colorIndex    = Int.random(in: 0..<bgColors.count)
    @State private var wordScale     : CGFloat = 1.0
    @State private var wordOpacity   : Double  = 1.0
    // Was a top-bar "ABC/abc" button — a text control in an app for
    // children who cannot read text. It's a grown-up setting, so it
    // moved to Settings and now persists.
    @AppStorage("isUppercase") private var isUppercase = true
    @State private var showImage     = false
    // True during the deliberate beat between the word appearing and the
    // picture confirming it.
    @State private var awaitingReveal = false
    // Bumped on every word change / disappear; delayed reveal+speech
    // callbacks bail if the token no longer matches.
    @State private var revealGen     = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var bgColor: Color { bgColors[colorIndex % bgColors.count] }
    private var isIPad: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            let hasButtons = showPlayButton || showSpellButton
            let imgH   = geo.size.height * (hasButtons ? 0.34 : 0.44)
            let tileH  = geo.size.height * (isIPad ? 0.18 : 0.22)
            let btnW   = min(geo.size.width * 0.38, isIPad ? 300.0 : 200.0)
            let btnH   = min(geo.size.height * 0.13, isIPad ? 180.0 : 140.0)

            ZStack {
                // Background bleeds to all edges; content stays inside safe area
                bgColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: colorIndex)

                VStack(spacing: 0) {

                    // ── Top bar: ABC | title | Voices ──
                    // Three icon buttons, 60pt tall, 12pt apart. Was four
                    // 36pt-tall pills 6pt apart labelled "ABC", "PIC" and
                    // "VOX" — below the 44pt minimum, far below what a
                    // 4-year-old's finger needs, and captioned in a code
                    // the target user cannot read.
                    HStack(spacing: 12) {
                        TopBarButton(systemImage: "chevron.backward",
                                     isIPad: isIPad,
                                     accessibilityLabel: "Back to home") {
                            dismissReader()
                        }
                        TopBarButton(systemImage: "photo.on.rectangle.angled",
                                     isIPad: isIPad,
                                     accessibilityLabel: "Picture gallery") {
                            showKidGallery = true
                        }

                        Spacer()

                        Text("123 Words")
                            .font(.system(size: isIPad ? 28 : 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        TopBarButton(systemImage: "person.wave.2.fill",
                                     isIPad: isIPad,
                                     accessibilityLabel: "Voice picker") {
                            showVoicePicker = true
                        }
                    }
                    .padding(.horizontal, isIPad ? 28 : 18)
                    .padding(.top, 8)

                    Spacer(minLength: 4)

                    // ── Word image + letter tiles + hint ──
                    VStack(spacing: geo.size.height * 0.012) {
                        if showImage {
                            WordImageView(word: wordStore.currentWord, targetHeight: imgH,
                                          onLongPress: { showParentGate = true })
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        } else if awaitingReveal {
                            RevealTeaser(height: imgH) { revealNow() }
                        } else {
                            Color.clear.frame(height: imgH)
                        }

                        WordDisplayView(
                            word: wordStore.currentWord,
                            highlightedIndex: speechEngine.highlightedLetterIndex,
                            tileHeight: tileH,
                            isUppercase: isUppercase,
                            // The handler was fully written and simply
                            // never passed in — children tapped giant
                            // letters and nothing happened.
                            onLetterTap: { i in
                                let word = wordStore.currentWord
                                let letters = Array(word)
                                guard i < letters.count else { return }
                                speechEngine.speakLetter(letters[i], in: word)
                            }
                        )

                        SwipeHintView(fontSize: max(26, geo.size.width * 0.07))
                    }
                    .scaleEffect(wordScale)
                    .opacity(wordOpacity)

                    Spacer(minLength: 12)

                    // ── Play + Spell buttons (optional per parental settings) ──
                    if hasButtons {
                        HStack(spacing: geo.size.width * 0.06) {
                            if showPlayButton {
                                ActionButton(
                                    icon: "speaker.wave.3.fill",
                                    label: "Play",
                                    color: .white,
                                    width: btnW, height: btnH,
                                    disabled: speechEngine.isActive
                                ) {
                                    guard !speechEngine.isActive else { return }
                                    speechEngine.isPending = true
                                    speechEngine.speak(wordStore.currentWord)
                                }
                            }
                            if showSpellButton {
                                ActionButton(
                                    icon: "character.cursor.ibeam",
                                    label: "Spell",
                                    color: .white,
                                    width: btnW, height: btnH,
                                    disabled: speechEngine.isActive
                                ) {
                                    guard !speechEngine.isActive else { return }
                                    speechEngine.isPending = true
                                    speechEngine.spell(wordStore.currentWord)
                                }
                            }
                        }
                        .padding(.bottom, max(40, geo.safeAreaInsets.bottom + 20))
                    } else {
                        Spacer().frame(height: max(40, geo.safeAreaInsets.bottom + 20))
                    }
                }
            }
        }
        .onAppear {
            // Screenshot-mode hooks — consumed on first read
            if UserDefaults.standard.bool(forKey: "screenshotShowVoicePicker") {
                UserDefaults.standard.removeObject(forKey: "screenshotShowVoicePicker")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showVoicePicker = true }
            }
            if UserDefaults.standard.bool(forKey: "screenshotShowSettings") {
                UserDefaults.standard.removeObject(forKey: "screenshotShowSettings")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showSettings = true }
            }
            if UserDefaults.standard.bool(forKey: "screenshotShowGallery") {
                UserDefaults.standard.removeObject(forKey: "screenshotShowGallery")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showKidGallery = true }
            }
            if UserDefaults.standard.string(forKey: "screenshotWord") != nil {
                showImage = true
                speechEngine.isPending = true
                speechEngine.spell(wordStore.currentWord)
            } else {
                beginWord(delay: Self.revealDelay)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    // Preschool swipes run diagonally, so requiring
                    // |dx| > |dy| threw away a lot of genuine intent.
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > abs(dy) * 0.7 else { return }
                    // No isActive guard. A swipe used to be silently
                    // dropped for the whole ~6s speak-and-spell cycle,
                    // which taught the child their input does nothing.
                    // A swipe now always means "next word" and simply
                    // interrupts whatever is playing.
                    speechEngine.stopAll()
                    if dx < 0 { wordStore.nextWord() } else { wordStore.previousWord() }
                    advanceColor()
                    animateWordChange()
                    beginWord(delay: Self.revealDelay)
                }
        )
        .onDisappear {
            // Leaving the reader: silence speech and invalidate any
            // pending reveal so it can't speak/animate after dismissal.
            revealGen &+= 1
            awaitingReveal = false
            speechEngine.stopAll()
        }
        .sheet(isPresented: $showParentGate, onDismiss: {
            if gatePassed { gatePassed = false; showSettings = true }
        }) {
            ParentGateView(passed: $gatePassed)
        }
        .popover(isPresented: $showSettings, isIPad: isIPad) {
            SettingsView(wordStore: wordStore, speechEngine: speechEngine)
        }
        .popover(isPresented: $showVoicePicker, isIPad: isIPad) {
            VoicePickerView(speechEngine: speechEngine)
        }
        .popover(isPresented: $showKidGallery, isIPad: isIPad) {
            KidGalleryView(speech: speechEngine)
        }
    }

    // MARK: - Word reveal

    /// How long the word sits alone before the picture confirms it. Was
    /// 2.0s, which is past the point where a preschooler stops reading the
    /// delay as a consequence of their own swipe.
    private static let revealDelay: Double = 1.2

    /// Show the new word, hold the beat, then reveal + speak.
    private func beginWord(delay: Double) {
        revealGen &+= 1
        let gen = revealGen
        let word = wordStore.currentWord
        showImage = false
        awaitingReveal = true
        speechEngine.isPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard gen == revealGen else { return }
            revealNow(word)
        }
    }

    /// Reveal immediately — from the timer, or because the child tapped
    /// the teaser card rather than waiting.
    private func revealNow(_ word: String? = nil) {
        guard awaitingReveal else { return }
        revealGen &+= 1
        awaitingReveal = false
        speechEngine.isPending = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showImage = true
        }
        speechEngine.speakThenSpell(word ?? wordStore.currentWord)
    }

    // MARK: - Helpers
    private func advanceColor() {
        var idx: Int
        repeat { idx = Int.random(in: 0..<bgColors.count) }
        while idx == colorIndex && bgColors.count > 1
        colorIndex = idx
    }

    private func animateWordChange() {
        withAnimation(.easeIn(duration: 0.1)) { wordScale = 0.8; wordOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                wordScale = 1.0; wordOpacity = 1.0
            }
        }
    }
}

// MARK: - Top Bar Button

struct TopBarButton: View {
    let systemImage: String
    var isIPad: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    private var side: CGFloat { isIPad ? 76 : 60 }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isIPad ? 30 : 24, weight: .black))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(KidTileButtonStyle())
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

/// Replaces the written instruction "swipe for a new word", which was set
/// in 14pt white at 0.6 alpha — 1.37:1 on the old yellow background, and
/// addressed to children who cannot read.
struct SwipeHintView: View {
    var fontSize: CGFloat = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var slide = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left").opacity(0.45)
            Image(systemName: "chevron.left").opacity(0.7)
            Image(systemName: "hand.point.up.left.fill")
            Image(systemName: "chevron.left").opacity(0)
        }
        .font(.system(size: fontSize, weight: .black))
        .foregroundStyle(.white)
        .offset(x: slide ? -14 : 14)
        .animation(reduceMotion ? nil
                   : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                   value: slide)
        .onAppear { slide = true }
        .accessibilityLabel("Swipe sideways for a new word")
    }
}

/// The gap between the word appearing and the picture confirming it is
/// deliberate — it gives the child a beat to attempt the word before the
/// answer arrives. It just used to be 2.0s of blank screen with input
/// silently dropped, which reads as a broken app. Now it is visible,
/// shorter, and tappable to skip.
struct RevealTeaser: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: height * 0.12)
                    .fill(.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.12)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 3)
                    )
                Text("?")
                    .font(.system(size: height * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(height: height)
            .padding(.horizontal, 40)
            .scaleEffect(pulse ? 1.0 : 0.94)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                       value: pulse)
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
        .accessibilityLabel("Show the picture")
    }
}

// MARK: - Word Display

struct WordDisplayView: View {
    let word: String
    let highlightedIndex: Int
    var tileHeight: CGFloat = 200
    var isUppercase: Bool = true
    var onLetterTap: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let count    = CGFloat(max(word.count, 1))
            let hPad: CGFloat = 32
            let gap      = max(8, geo.size.width * 0.02)
            let rawWidth = (geo.size.width - hPad - gap * (count - 1)) / count
            let maxBox: CGFloat = geo.size.width > 700 ? 320 : 200
            let boxWidth = min(rawWidth, maxBox)
            let fontSize = boxWidth * 0.72
            let boxHeight = tileHeight
            // Never lower-case the pronoun "I" — it used to render as "i".
            let displayWord = word == "I" ? "I"
                : (isUppercase ? word.uppercased() : word.lowercased())

            HStack(spacing: gap) {
                ForEach(Array(displayWord.enumerated()), id: \.offset) { index, letter in
                    LetterBoxView(
                        letter: String(letter),
                        fontSize: fontSize,
                        boxWidth: boxWidth,
                        boxHeight: boxHeight,
                        isHighlighted: highlightedIndex == index,
                        onTap: onLetterTap.map { cb in { cb(index) } }
                    )
                }
            }
            .frame(width: geo.size.width, alignment: .center)
        }
        .frame(height: tileHeight)
        .padding(.horizontal, 16)
    }
}

struct LetterBoxView: View {
    let letter: String
    let fontSize: CGFloat
    let boxWidth: CGFloat
    let boxHeight: CGFloat
    let isHighlighted: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(isHighlighted ? Color.yellow : Color.white.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(isHighlighted ? 0 : 0.4), lineWidth: 3)
                )

            Text(letter)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(isHighlighted ? Color.black : Color.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: boxWidth, height: boxHeight)
        .scaleEffect(isHighlighted ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isHighlighted)
        .onTapGesture { onTap?() }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    var width: CGFloat = 150
    var height: CGFloat = 120
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: height * 0.08) {
                Image(systemName: icon)
                    .font(.system(size: min(height * 0.28, 48), weight: .semibold))
                Text(label)
                    .font(.system(size: min(height * 0.18, 28), weight: .bold, design: .rounded))
            }
            .foregroundStyle(color.opacity(disabled ? 0.35 : 1.0))
            .frame(width: width, height: height)
            .background(Color.white.opacity(disabled ? 0.08 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: height * 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.2)
                    .strokeBorder(Color.white.opacity(disabled ? 0.15 : 0.4), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Word Image

// Definitive icons — shown cleanly, no ? overlay
// bg: nil = transparent; non-nil = filled rounded-rect background
struct WordIcon {
    let symbol: String
    let fg: Color
    let bg: Color?
    init(_ symbol: String, _ fg: Color, _ bg: Color? = nil) {
        self.symbol = symbol; self.fg = fg; self.bg = bg
    }
}
let wordDefinitiveSymbol: [String: WordIcon] = [
    "sum": WordIcon("plus",                    .green),
    "I":   WordIcon("person.crop.circle.fill", .purple),
    "won": WordIcon("trophy.fill",             .yellow, Color(red: 0.2, green: 0.5, blue: 0.9)),
    "dig": WordIcon("shovel.fill",             .brown, Color(red: 0.55, green: 0.35, blue: 0.17)),
]

// Fallback icons — shown with ? overlay to indicate no real photo
let wordFallbackSymbol: [String: String] = [:]

// Words whose images come from OpenMoji (open-source emoji library)
let openMojiWords: Set<String> = [
    "go","hi","me","no","up","we",
    "ant","ape","arm","art","bag","bat","bed","box","boy","bug","bus",
    "can","cap","car","cat","cow","cup","cut","day","dig","dog","dot",
    "ear","eat","egg","eye","fan","fly","fog","fox","fun",
    "hat","hay","hen","hop","hot","hug","hut",
    "ice","jam","jar","jaw","jet","joy","jug",
    "key","kid","kit","leg","lid","lip","log",
    "mad","man","map","mom","mug","nap","net","new","nut",
    "oak","pad","pan","paw","pea","pen","pie","pig","pin","pop","pot",
    "ran","rat","red","rib","rod","row","run",
    "sad","saw","say","sea","sip","six","sky","sob","son","sub","sun",
    "tap","ten","tie","tin","toe","toy","tub","tug","two",
    "van","web","wed","wet","win","won","wow",
    "yam","yes","zap","zip","zoo",
]

// Shared across ContentView and GalleryView
enum ImageProvenance: Equatable {
    case openMoji
    case aiGenerated
    case sfSymbol(definitive: Bool)  // definitive = intentional, false = placeholder ?
    case noImage

    var label: String {
        switch self {
        case .openMoji:              return "OpenMoji"
        case .aiGenerated:           return "AI Generated"
        case .sfSymbol(true):        return "SF Symbols"
        case .sfSymbol(false):       return "Placeholder"
        case .noImage:               return "No Image"
        }
    }
    var detail: String {
        switch self {
        case .openMoji:              return "Open-source emoji\nopenmoji.org"
        case .aiGenerated:           return "DALL·E 3 by OpenAI\nGenerated for this app"
        case .sfSymbol(true):        return "Apple SF Symbols\nSystem icon"
        case .sfSymbol(false):       return "Apple SF Symbols\n(no real picture yet)"
        case .noImage:               return "—"
        }
    }
    var badgeColor: Color {
        switch self {
        case .openMoji:              return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .aiGenerated:           return Color(red: 0.5, green: 0.2, blue: 0.9)
        case .sfSymbol(true):        return Color(red: 0.1, green: 0.5, blue: 0.9)
        case .sfSymbol(false):       return Color.gray
        case .noImage:               return Color.gray
        }
    }
    var icon: String {
        switch self {
        case .openMoji:              return "😊"
        case .aiGenerated:           return "✨"
        case .sfSymbol(true):        return "🍎"
        case .sfSymbol(false):       return "❓"
        case .noImage:               return "❓"
        }
    }
}

// MARK: - Image gesture UIKit bridge (parent long press)
//
// This used to also carry a 2-finger tap that flipped the picture over to
// an image-provenance card ("DALL·E 3 by OpenAI"). It was exactly
// backwards for the audience: a child palming the screen fired it
// constantly and lost the picture they were looking at, while no
// 4-year-old would ever perform a deliberate two-finger tap. Provenance
// now lives only in the parent-facing GalleryView.
private struct ImageGestureView: UIViewRepresentable {
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.longPressed(_:)))
        lp.minimumPressDuration = 1.5
        lp.numberOfTouchesRequired = 1
        v.addGestureRecognizer(lp)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLongPress = onLongPress
    }

    class Coordinator: NSObject {
        var onLongPress: () -> Void
        init(onLongPress: @escaping () -> Void) { self.onLongPress = onLongPress }
        @objc func longPressed(_ gr: UILongPressGestureRecognizer) {
            if gr.state == .began { onLongPress() }
        }
    }
}

// MARK: - Word Image

struct WordImageView: View {
    let word: String
    var targetHeight: CGFloat = 240
    var onLongPress: (() -> Void)? = nil

    @State private var floatOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var provenance: ImageProvenance {
        if wordDefinitiveSymbol[word] != nil     { return .sfSymbol(definitive: true) }
        if UIImage(named: word) != nil {
            return openMojiWords.contains(word) ? .openMoji : .aiGenerated
        }
        if wordFallbackSymbol[word.lowercased()] != nil { return .sfSymbol(definitive: false) }
        return .noImage
    }

    private var isAI: Bool { provenance == .aiGenerated }

    var body: some View {
        frontImage
            .frame(height: targetHeight)
            .frame(maxWidth: .infinity)
            .offset(y: floatOffset)
            .overlay(ImageGestureView(onLongPress: { onLongPress?() }))
            .onAppear { startFloat(delay: Double.random(in: 0...1.5)) }
            .onChange(of: word) {
                floatOffset = 0
                startFloat(delay: 0.15)
            }
    }

    // The float is a `repeatForever` animation that never idles, so it
    // also held a display link alive for the whole life of the screen.
    private func startFloat(delay: Double) {
        guard isAI, !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(delay)
        ) { floatOffset = -7 }
    }

    @ViewBuilder private var frontImage: some View {
        if let icon = wordDefinitiveSymbol[word] {
            ZStack {
                if let bg = icon.bg {
                    RoundedRectangle(cornerRadius: targetHeight * 0.12)
                        .fill(bg.opacity(0.88))
                        .padding(12)
                }
                Image(systemName: icon.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(icon.bg != nil ? icon.fg : icon.fg.opacity(0.75))
                    .padding(icon.bg != nil ? 40 : 20)
            }
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            .id(word)
        } else if UIImage(named: word) != nil {
            Image(word)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .id(word)
        } else {
            let symbol = wordFallbackSymbol[word.lowercased()] ?? "person.fill"
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.blue.opacity(0.6))
                .overlay(alignment: .top) {
                    Text("?")
                        .font(.system(size: targetHeight * 0.14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, targetHeight * 0.015)
                }
                .padding(24)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .id(word)
        }
    }

}

// MARK: - iPad-aware presentation

extension View {
    @ViewBuilder
    func popover<Content: View>(isPresented: Binding<Bool>,
                                onDismiss: (() -> Void)? = nil,
                                isIPad: Bool,
                                @ViewBuilder content: @escaping () -> Content) -> some View {
        if isIPad {
            self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        } else {
            self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        }
    }
}

#Preview {
    ContentView(speechEngine: SpeechEngine())
}
