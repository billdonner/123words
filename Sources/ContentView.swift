import SwiftUI

// Background color palette — bright and child-friendly
private let bgColors: [Color] = [
    Color(red: 1.0, green: 0.35, blue: 0.35),
    Color(red: 1.0, green: 0.60, blue: 0.10),
    Color(red: 0.30, green: 0.75, blue: 0.35),
    Color(red: 0.25, green: 0.55, blue: 1.00),
    Color(red: 0.70, green: 0.30, blue: 0.90),
    Color(red: 1.00, green: 0.30, blue: 0.60),
    Color(red: 0.10, green: 0.70, blue: 0.85),
    Color(red: 0.95, green: 0.75, blue: 0.10),
]

struct ContentView: View {
    @StateObject private var wordStore   = WordStore()
    @StateObject private var speechEngine = SpeechEngine()
    @AppStorage("hasSeenParentOnboarding") private var hasSeenOnboarding = false
    @AppStorage("showPlayButton")  private var showPlayButton  = false
    @AppStorage("showSpellButton") private var showSpellButton = false
    @State private var showSettings     = false
    @State private var showVoicePicker  = false
    @State private var showOnboarding   = false
    @State private var showKidGallery   = false
    @Environment(\.dismiss) private var dismissReader
    @State private var colorIndex    = Int.random(in: 0..<bgColors.count)
    @State private var wordScale     : CGFloat = 1.0
    @State private var wordOpacity   : Double  = 1.0
    @State private var isUppercase   = true
    @State private var showImage     = false
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
                    HStack(spacing: 0) {
                        TopBarButton(label: "←",
                                     width: isIPad ? 60 : 44, fontSize: isIPad ? 26 : 20,
                                     accessibilityLabel: "Back to home") {
                            dismissReader()
                        }
                        .padding(.trailing, 6)
                        TopBarButton(label: isUppercase ? "ABC" : "abc",
                                     width: isIPad ? 90 : 60, fontSize: isIPad ? 22 : 15,
                                     accessibilityLabel: isUppercase ? "Switch to lowercase letters" : "Switch to uppercase letters") {
                            isUppercase.toggle()
                        }
                        TopBarButton(label: "PIC",
                                     width: isIPad ? 72 : 48, fontSize: isIPad ? 22 : 15,
                                     accessibilityLabel: "Picture gallery") {
                            showKidGallery = true
                        }
                        .padding(.leading, 6)

                        Spacer()

                        Text("123 Words")
                            .font(.system(size: isIPad ? 28 : 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))

                        Spacer()

                        TopBarButton(label: "VOX",
                                     width: isIPad ? 72 : 48, fontSize: isIPad ? 22 : 15,
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
                                          onLongPress: { showSettings = true })
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        } else {
                            Color.clear.frame(height: imgH)
                        }

                        WordDisplayView(
                            word: wordStore.currentWord,
                            highlightedIndex: speechEngine.highlightedLetterIndex,
                            tileHeight: tileH,
                            isUppercase: isUppercase
                        )

                        Text("swipe for a new word")
                            .font(.system(size: max(14, geo.size.width * 0.038),
                                          weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
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
            if !hasSeenOnboarding {
                showOnboarding = true
            }
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
            let gen = revealGen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard gen == revealGen else { return }
                guard !showOnboarding else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showImage = true
                }
                if UserDefaults.standard.string(forKey: "screenshotWord") != nil {
                    speechEngine.isPending = true
                    speechEngine.spell(wordStore.currentWord)
                } else {
                    speechEngine.speakThenSpell(wordStore.currentWord)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard !speechEngine.isActive else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 { wordStore.nextWord() }
                    else { wordStore.previousWord() }
                    advanceColor()
                    showImage = false
                    animateWordChange()
                    speechEngine.isPending = true
                    revealGen &+= 1
                    let gen = revealGen
                    let word = wordStore.currentWord
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        guard gen == revealGen else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showImage = true
                        }
                        speechEngine.isPending = false
                        speechEngine.speakThenSpell(word)
                    }
                }
        )
        .onDisappear {
            // Leaving the reader: silence speech and invalidate any
            // pending reveal so it can't speak/animate after dismissal.
            revealGen &+= 1
            speechEngine.stopAll()
        }
        .popover(isPresented: $showOnboarding, onDismiss: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showImage = true
            }
            let gen = revealGen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard gen == revealGen else { return }
                speechEngine.speakThenSpell(wordStore.currentWord)
            }
        }, isIPad: isIPad) {
            ParentOnboardingView()
        }
        .popover(isPresented: $showSettings, isIPad: isIPad) {
            SettingsView(wordStore: wordStore, speechEngine: speechEngine)
        }
        .popover(isPresented: $showVoicePicker, isIPad: isIPad) {
            VoicePickerView(speechEngine: speechEngine)
        }
        .popover(isPresented: $showKidGallery, isIPad: isIPad) {
            KidGalleryView()
        }
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
    let label: String
    var width: CGFloat = 52
    var fontSize: CGFloat = 15
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: width, height: fontSize * 2.4)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? label)
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
            let displayWord = isUppercase ? word.uppercased() : word.lowercased()

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

// MARK: - Image gesture UIKit bridge (2-finger tap + long press)
private struct ImageGestureView: UIViewRepresentable {
    let onTwoFingerTap: () -> Void
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTwoFingerTap: onTwoFingerTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.twoFingerTapped))
        tap.numberOfTouchesRequired = 2
        v.addGestureRecognizer(tap)

        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.longPressed(_:)))
        lp.minimumPressDuration = 0.8
        lp.numberOfTouchesRequired = 1
        v.addGestureRecognizer(lp)

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTwoFingerTap = onTwoFingerTap
        context.coordinator.onLongPress   = onLongPress
    }

    class Coordinator: NSObject {
        var onTwoFingerTap: () -> Void
        var onLongPress: () -> Void
        init(onTwoFingerTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onTwoFingerTap = onTwoFingerTap
            self.onLongPress    = onLongPress
        }
        @objc func twoFingerTapped() { onTwoFingerTap() }
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

    @State private var showProvenance = false
    @State private var floatOffset: CGFloat = 0

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
        ZStack {
            // ── Front face ──
            frontImage
                .rotation3DEffect(.degrees(showProvenance ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(showProvenance ? 0 : 1)

            // ── Back face (provenance card) ──
            provenanceCard
                .rotation3DEffect(.degrees(showProvenance ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                .opacity(showProvenance ? 1 : 0)
        }
        .frame(height: targetHeight)
        .frame(maxWidth: .infinity)
        .offset(y: floatOffset)
        .overlay(ImageGestureView(
            onTwoFingerTap: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    showProvenance.toggle()
                }
            },
            onLongPress: { onLongPress?() }
        ))
        .onAppear {
            if isAI {
                withAnimation(
                    .easeInOut(duration: 2.8)
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...1.5))
                ) { floatOffset = -7 }
            }
        }
        .onChange(of: word) {
            floatOffset = 0
            showProvenance = false
            if isAI {
                withAnimation(
                    .easeInOut(duration: 2.8)
                    .repeatForever(autoreverses: true)
                    .delay(0.15)
                ) { floatOffset = -7 }
            }
        }
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

    @ViewBuilder private var provenanceCard: some View {
        let prov = provenance
        ZStack {
            RoundedRectangle(cornerRadius: targetHeight * 0.1)
                .fill(.black.opacity(0.55))
                .padding(8)
            VStack(spacing: 10) {
                Text(prov.icon)
                    .font(.system(size: targetHeight * 0.22))
                Text(prov.label)
                    .font(.system(size: targetHeight * 0.1, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(prov.detail)
                    .font(.system(size: targetHeight * 0.075, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .id(word + "_prov")
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
    ContentView()
}
