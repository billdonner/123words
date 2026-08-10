import SwiftUI

enum HomePage: String, Identifiable, CaseIterable {
    case read, spell, scramble, memory, quiz, count
    var id: String { rawValue }

    var title: String {
        switch self {
        case .read:     return "Read"
        case .spell:    return "Spell It"
        case .scramble: return "Word Scramble"
        case .memory:   return "Memory Match"
        case .quiz:     return "Listen & Pick"
        case .count:    return "Count It"
        }
    }
    var blurb: String {
        switch self {
        case .read:     return "Swipe through words.\nHear them spelled."
        case .spell:    return "See the picture, tap the letters."
        case .scramble: return "Put the letters in order."
        case .memory:   return "Find the matching pairs."
        case .quiz:     return "Hear a word, pick its picture."
        case .count:    return "Add and take away.\nPick the right number."
        }
    }
    // Letters on the splash tile
    var letters: String {
        switch self {
        case .read:     return "ABC"
        case .spell:    return "SPL"
        case .scramble: return "MIX"
        case .memory:   return "MEM"
        case .quiz:     return "QUZ"
        case .count:    return "123"
        }
    }
    // Picture from the word-image pack used as the page's big icon
    var iconWord: String {
        switch self {
        case .read:     return "eye"
        case .spell:    return "key"
        case .scramble: return "egg"
        case .memory:   return "two"
        case .quiz:     return "ear"
        case .count:    return "six"
        }
    }
    // Distinct tint per page
    var color: Color {
        switch self {
        case .read:     return gameColors[1]   // orange
        case .spell:    return gameColors[3]   // blue
        case .scramble: return gameColors[4]   // purple
        case .memory:   return gameColors[2]   // green
        case .quiz:     return gameColors[5]   // pink
        case .count:    return gameColors[7]   // yellow
        }
    }
    var buttonLabel: String {
        switch self {
        case .read: return "Open"
        default:    return "Play"
        }
    }

    /// What one correct answer in this game is worth in a race.
    ///
    /// Every game used to pay a flat +1, which made Memory Match by far
    /// the best way to score: a matched pair is +1, an EASY board is 8
    /// pairs, and matching a picture to a word you can't read needs no
    /// literacy at all. A child optimising for score would correctly
    /// learn to sit on Memory Match and never spell anything. Points now
    /// track how much work the answer actually took.
    var racePoints: Int {
        switch self {
        case .spell, .scramble: return 3   // built a whole word
        case .quiz, .count:     return 2   // one considered choice
        case .memory:           return 1   // one pair
        case .read:             return 0   // not in the race ring
        }
    }
}

// Race durations the kid can pick on the hub.
private let raceDurations: [TimeInterval] = [60, 120]

// Parent-controlled hub layout — Race is the default; Classic restores
// the original per-game swipe-through-splashes hub for parents who
// prefer the un-timed flow.
enum HubMode: String {
    case race
    case classic
}

struct HomeHubView: View {
    @StateObject private var speech = SpeechEngine()
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("hubMode") private var hubModeRaw: String = HubMode.race.rawValue
    private var hubMode: HubMode { HubMode(rawValue: hubModeRaw) ?? .race }

    // Race controls
    @AppStorage("raceDuration") private var raceDurationRaw: Double = 60
    @State private var displayedBest: Int = 0
    @State private var showRace: Bool = false
    @State private var raceDurationLaunched: TimeInterval = 60

    // Practice + classic-mode swipe state
    @State private var showReader: Bool = false
    @State private var activeGame: HomePage? = nil
    @State private var classicPage: Int = 0

    // Parental settings sheet, behind the grown-up gate
    @State private var showParentalSettings: Bool = false
    @State private var showParentGate: Bool = false
    @State private var gatePassed: Bool = false

    // First-run onboarding now lives here rather than inside the reader,
    // where a parent who went straight to a game never saw it.
    @AppStorage("hasSeenParentOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding: Bool = false
    @State private var showStickers: Bool = false

    private let classicPages: [HomePage] = HomePage.allCases
    private var isIPad: Bool { sizeClass == .regular }
    private var raceDuration: TimeInterval { raceDurationRaw }

    var body: some View {
        ZStack {
            switch hubMode {
            case .race:    raceHubBody
            case .classic: classicHubBody
            }
        }
        .onAppear {
            refreshBest()
            consumeScreenshotHooks()
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .onChange(of: raceDurationRaw) { _, _ in refreshBest() }
        .fullScreenCover(isPresented: $showReader) {
            ContentView(speechEngine: speech)
        }
        .fullScreenCover(isPresented: $showRace, onDismiss: refreshBest) {
            RaceView(speech: speech, duration: raceDurationLaunched)
        }
        .fullScreenCover(item: $activeGame) { p in
            // Freeform single-game launch — used by the classic hub's
            // Play buttons and the screenshot tooling pipeline.
            switch p {
            case .read:     ContentView(speechEngine: speech)
            case .spell:    SpellItGame(speech: speech)
            case .scramble: WordScrambleGame(speech: speech)
            case .memory:   MemoryMatchGame(speech: speech)
            case .quiz:     WordQuizGame(speech: speech)
            case .count:    CountItGame(speech: speech)
            }
        }
        .sheet(isPresented: $showParentGate, onDismiss: {
            if gatePassed { gatePassed = false; showParentalSettings = true }
        }) {
            ParentGateView(passed: $gatePassed)
        }
        .sheet(isPresented: $showParentalSettings) {
            HubSettingsView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            ParentOnboardingView()
        }
        .sheet(isPresented: $showStickers) {
            StickerBookView(speech: speech)
        }
    }

    // MARK: - Race hub (default)

    private var raceHubBody: some View {
        ZStack {
            // Soft brand gradient — distinct from any single game's tint
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.32, blue: 0.78),
                    Color(red: 0.46, green: 0.18, blue: 0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                Spacer(minLength: 6)
                practiceCard
                Spacer(minLength: 12)
                raceCard
                Spacer(minLength: 12)
                versionTag
            }
            .padding(.horizontal, isIPad ? 32 : 18)
            .padding(.vertical, 12)
        }
    }

    private var titleBar: some View {
        HStack {
            Text("123 Words")
                .font(.system(size: isIPad ? 36 : 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            stickerButton
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    /// Entry to the collection. Replaces a decorative 🏁 that did nothing.
    private var stickerButton: some View {
        Button { showStickers = true } label: {
            HStack(spacing: 6) {
                Text("⭐️").font(.system(size: isIPad ? 26 : 22))
                Text("\(WordProgress.shared.masteredCount)")
                    .font(.system(size: isIPad ? 22 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Capsule().fill(.white.opacity(0.22))
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My words — \(WordProgress.shared.masteredCount) collected")
    }

    private var practiceCard: some View {
        Button { showReader = true } label: {
            HStack(spacing: 16) {
                GameWordImage(word: HomePage.read.iconWord, size: isIPad ? 110 : 80)
                    .frame(width: isIPad ? 110 : 80, height: isIPad ? 110 : 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Practice")
                        .font(.system(size: isIPad ? 28 : 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Swipe through words.\nHear them spelled out.")
                        .font(.system(size: isIPad ? 17 : 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Practice — open the reader")
    }

    private var raceCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("🏁")
                    .font(.system(size: isIPad ? 44 : 34))
                Text("Race!")
                    .font(.system(size: isIPad ? 34 : 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if displayedBest > 0 {
                    bestChip
                }
            }

            Text("Swipe between 5 games. Answer as many\nas you can before time runs out!")
                .font(.system(size: isIPad ? 17 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)

            durationPicker
            previewRow
            startButton
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                )
        )
    }

    private var bestChip: some View {
        HStack(spacing: 4) {
            Text("⭐️").font(.system(size: 14))
            Text("Best \(displayedBest)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(.white.opacity(0.22))
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1.5)))
    }

    private var durationPicker: some View {
        HStack(spacing: 10) {
            ForEach(raceDurations, id: \.self) { d in
                Button {
                    raceDurationRaw = d
                } label: {
                    Text(d <= 60 ? "1 MIN" : "2 MIN")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(
                            Capsule().fill(raceDuration == d
                                           ? Color.white.opacity(0.32)
                                           : Color.white.opacity(0.10))
                        )
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(raceDuration == d ? 0.7 : 0.3),
                                                   lineWidth: raceDuration == d ? 2 : 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var previewRow: some View {
        HStack(spacing: 10) {
            ForEach(HomePage.allCases.filter { $0 != .read }, id: \.id) { g in
                VStack(spacing: 4) {
                    GameWordImage(word: g.iconWord, size: isIPad ? 56 : 40)
                        .frame(width: isIPad ? 56 : 40, height: isIPad ? 56 : 40)
                    Text(g.letters)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
    }

    private var startButton: some View {
        Button {
            raceDurationLaunched = raceDuration
            showRace = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .black))
                Text("Start Race")
                    .font(.system(size: 26, weight: .black, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.46, green: 0.18, blue: 0.78))
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Classic hub (parent opt-in, original swipe-through layout)

    private var classicHubBody: some View {
        ZStack {
            classicPages[classicPage].color
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: classicPage)

            TabView(selection: $classicPage) {
                ForEach(Array(classicPages.enumerated()), id: \.element.id) { idx, p in
                    classicPageContent(p)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Tiny version tag in the bottom-right; parental long-press lives here.
            VStack {
                HStack {
                    Spacer()
                    stickerButton
                        .padding(.trailing, 18)
                        .padding(.top, 8)
                }
                Spacer()
                HStack {
                    Spacer()
                    versionTag
                        .padding(.trailing, 18)
                        .padding(.bottom, 30)
                }
            }
        }
    }

    private func classicPageContent(_ p: HomePage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            // Big icon — pulled from the word-image pack
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 4))
                GameWordImage(word: p.iconWord, size: isIPad ? 220 : 170)
            }
            .frame(width: isIPad ? 280 : 220, height: isIPad ? 280 : 220)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)

            // 3-letter 123words tile name
            HStack(spacing: 14) {
                ForEach(Array(p.letters), id: \.self) { ch in
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.white.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(.white.opacity(0.55), lineWidth: 4)
                            )
                        Text(String(ch))
                            .font(.system(size: isIPad ? 80 : 64, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: isIPad ? 110 : 88, height: isIPad ? 130 : 104)
                }
            }
            .padding(.top, 26)

            Text(p.title)
                .font(.system(size: isIPad ? 36 : 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 16)

            Text(p.blurb)
                .font(.system(size: isIPad ? 20 : 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 6)

            Spacer()

            Button { activeGame = p } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .black))
                    Text(p.buttonLabel)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                }
                .foregroundStyle(p.color)
                .padding(.vertical, 18)
                .padding(.horizontal, 56)
                .background(.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)

            // Reserve space for page dots
            Spacer().frame(height: 70)
        }
    }

    // MARK: - Version tag (hidden parental settings entry)

    private var versionTag: some View {
        Text(versionString())
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            // Long-press on the tiny version label opens the parental
            // settings sheet — invisible to kids, easy for parents.
            // The label itself is ~50x13pt — too small for a parent to
            // reliably hit — so the tap area is padded out well beyond
            // the visible text while the text stays camouflaged.
            .padding(20)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.5) {
                showParentGate = true
            }
            .accessibilityHint("Long press for parent settings")
    }

    // MARK: - Helpers

    private func refreshBest() {
        let key = "raceBest_\(Int(raceDuration))"
        displayedBest = UserDefaults.standard.integer(forKey: key)
    }

    private func consumeScreenshotHooks() {
        let defaults = UserDefaults.standard
        if let pageName = defaults.string(forKey: "screenshotHomePage"),
           let target = HomePage(rawValue: pageName),
           let idx = classicPages.firstIndex(of: target) {
            classicPage = idx
            defaults.removeObject(forKey: "screenshotHomePage")
        }
        if let gameName = defaults.string(forKey: "screenshotLaunchGame"),
           let target = HomePage(rawValue: gameName) {
            defaults.removeObject(forKey: "screenshotLaunchGame")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                activeGame = target
            }
        }
        if defaults.bool(forKey: "screenshotShowStickers") {
            defaults.removeObject(forKey: "screenshotShowStickers")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showStickers = true }
        }
        // Open the race directly — RaceView reads screenshotRace*
        // defaults to freeze itself in a compelling preset state.
        if defaults.bool(forKey: "screenshotStartRace") {
            defaults.removeObject(forKey: "screenshotStartRace")
            // Honor an optional duration override; default to 60s.
            if let d = defaults.object(forKey: "screenshotRaceDuration") as? Double {
                raceDurationLaunched = d
                defaults.removeObject(forKey: "screenshotRaceDuration")
            } else {
                raceDurationLaunched = 60
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showRace = true
            }
        }
    }

    private func versionString() -> String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
}

// MARK: - Parental settings sheet

private struct HubSettingsView: View {
    @AppStorage("hubMode") private var hubModeRaw: String = HubMode.race.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Home screen", selection: $hubModeRaw) {
                        Text("Race! (timed)").tag(HubMode.race.rawValue)
                        Text("Classic (per-game)").tag(HubMode.classic.rawValue)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Home Screen")
                } footer: {
                    Text("Race mode is a single timed game across all five mini-games — kids race the clock to answer as many as they can. Classic mode is the original layout: swipe between games and tap Play to open one at your own pace, with no timer.")
                }

                Section {
                    let dur60 = UserDefaults.standard.integer(forKey: "raceBest_60")
                    let dur120 = UserDefaults.standard.integer(forKey: "raceBest_120")
                    HStack {
                        Text("1-minute best")
                        Spacer()
                        Text(dur60 > 0 ? "\(dur60)" : "—")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("2-minute best")
                        Spacer()
                        Text(dur120 > 0 ? "\(dur120)" : "—")
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: "raceBest_60")
                        UserDefaults.standard.removeObject(forKey: "raceBest_120")
                    } label: {
                        Label("Reset race best scores", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Race Scores")
                }
            }
            .navigationTitle("Parent Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
