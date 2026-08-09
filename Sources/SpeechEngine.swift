import AVFoundation
import SwiftUI

enum SpellingSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"

    var rate: Float {
        switch self {
        case .slow:   return 0.35
        case .medium: return 0.48
        case .fast:   return 0.58
        }
    }

    var pauseDuration: TimeInterval {
        switch self {
        case .slow:   return 0.6
        case .medium: return 0.3
        case .fast:   return 0.1
        }
    }
}

class SpeechEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    @Published var highlightedLetterIndex: Int = -1
    @Published var isSpelling: Bool = false
    @Published var isSpeaking: Bool = false

    // Persisted across launches
    @Published var spellingSpeed: SpellingSpeed = SpellingSpeed(rawValue: UserDefaults.standard.string(forKey: "spellingSpeed") ?? "") ?? .medium {
        didSet { UserDefaults.standard.set(spellingSpeed.rawValue, forKey: "spellingSpeed") }
    }
    @Published var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "selectedVoiceID") ?? ""

    /// Parent-facing kill switch. The session category is `.playback`, so
    /// the hardware ring/silent switch does NOT silence this app — that is
    /// deliberate (a talking app that goes mute when the phone is on
    /// silent reads as broken), but it means parents need an in-app mute
    /// and there wasn't one.
    @Published var isMuted: Bool = UserDefaults.standard.bool(forKey: "speechMuted") {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "speechMuted")
            if isMuted { stopAll() }
        }
    }

    private var spellingLetters: [String] = []
    private var spellingWord: String = ""
    private var currentLetterIndex: Int = 0
    private var isInSpellingMode: Bool = false

    // Bumped by every stopAll(); delayed callbacks capture the value at
    // schedule time and bail if it no longer matches (word/round changed,
    // view dismissed, voice previewed, etc).
    private var generation: Int = 0
    @Published var pendingSpell: Bool = false  // speak → spell chain in progress
    @Published var isPending: Bool = false     // locked during pre-speech countdown

    var isActive: Bool { isSpeaking || isSpelling || pendingSpell || isPending }

    // English voices sorted: premium → enhanced → default, then alphabetically
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name < $1.name
            }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        configureSession()
        observeSessionEvents()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Audio session

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: .duckOthers
            )
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }
    }

    /// The session is activated around utterances rather than once at
    /// launch. `.duckOthers` used to be applied for the whole foreground
    /// lifetime of the app, so a parent's podcast stayed ducked through
    /// every silent gap — including the multi-second ones between words.
    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func deactivateSessionIfIdle() {
        guard !synthesizer.isSpeaking, !isInSpellingMode, !pendingSpell else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    private func observeSessionEvents() {
        let nc = NotificationCenter.default
        // Without this the app permanently loses its voice: a phone call,
        // Siri, or an alarm deactivates the session and nothing ever
        // reactivates it, so speech silently stops for the rest of the
        // session and only a force-quit brings it back.
        nc.addObserver(self,
                       selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance())
        // Yanking headphones out mid-word would otherwise blast the
        // built-in speaker at volume 1.0.
        nc.addObserver(self,
                       selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification,
                       object: AVAudioSession.sharedInstance())
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            stopAll()
        case .ended:
            configureSession()
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable { stopAll() }
    }

    // MARK: - Speaking

    func selectVoice(_ identifier: String) {
        selectedVoiceIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "selectedVoiceID")
    }

    /// Speak `text`.
    ///
    /// `interrupting: true` (the default) cuts whatever is playing — right
    /// for a new word or a new round. `interrupting: false` lets the
    /// utterance fall in behind what's already playing, which is what
    /// per-letter tap feedback needs: every call used to begin with
    /// `stopAll()`, so a child tapping C-A-T at any speed heard
    /// "k…", "æ…", "tee" — the letter sounds the app exists to teach were
    /// exactly what fast tapping destroyed.
    func speak(_ word: String, interrupting: Bool = true) {
        guard !isMuted else { return }
        // A queued utterance can't be spliced into the middle of a
        // spelling chain without corrupting it, so those still interrupt.
        if interrupting || isInSpellingMode || pendingSpell {
            stopAll()
        }
        isSpeaking = true
        isInSpellingMode = false
        activateSession()
        synthesizer.speak(utterance(word, rate: 0.48, pitch: 1.1))
    }

    func spell(_ word: String) {
        guard !isMuted else { return }
        stopAll()
        isInSpellingMode = true
        isSpelling = true
        spellingWord = word
        spellingLetters = word.lowercased().map { String($0) }
        currentLetterIndex = 0
        speakNextLetter()
    }

    // Preview a voice — says "Hello, I am [name]". Fully resets engine state
    // first so interrupting an in-progress spell can't leave the reader stuck
    // in a busy/spelling state when the picker is dismissed.
    func speakHello(with voice: AVSpeechSynthesisVoice?) {
        stopAll()
        let text: String
        if let voice {
            let baseName = voice.name.components(separatedBy: " (").first ?? voice.name
            text = "Hello, I am \(baseName)."
        } else {
            text = "Hello!"
        }
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.48
        u.pitchMultiplier = 1.15
        u.volume = 1.0
        u.voice = voice
        activateSession()
        synthesizer.speak(u)
    }

    func speakThenSpell(_ word: String) {
        guard !isMuted else { return }
        stopAll()
        spellingWord = word
        pendingSpell = true
        isSpeaking = true
        activateSession()
        synthesizer.speak(utterance(word, rate: 0.48, pitch: 1.1))
    }

    func stopAll() {
        generation &+= 1
        isPending = false
        pendingSpell = false
        isInSpellingMode = false
        synthesizer.stopSpeaking(at: .immediate)
        highlightedLetterIndex = -1
        isSpelling = false
        isSpeaking = false
        spellingLetters = []
        currentLetterIndex = 0
        deactivateSessionIfIdle()
    }

    private func utterance(_ text: String, rate: Float, pitch: Float) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = 1.0
        u.voice = resolvedVoice()
        return u
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        guard !selectedVoiceIdentifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }

    private func speakNextLetter() {
        guard currentLetterIndex < spellingLetters.count else {
            // All letters done — clear highlight then speak the whole word
            let word = spellingWord
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard gen == self.generation else { return }
                self.highlightedLetterIndex = -1
                self.isSpelling = false
                self.isInSpellingMode = false
                self.activateSession()
                self.synthesizer.speak(self.utterance(word, rate: 0.48, pitch: 1.1))
            }
            return
        }
        highlightedLetterIndex = currentLetterIndex
        let letter = spellingLetters[currentLetterIndex]
        currentLetterIndex += 1
        activateSession()
        synthesizer.speak(utterance(letter, rate: spellingSpeed.rate, pitch: 1.2))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let pause = spellingSpeed.pauseDuration
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            guard gen == self.generation else { return }
            if self.isInSpellingMode {
                self.speakNextLetter()
            } else if self.pendingSpell {
                // First speak finished — now spell letter by letter
                self.pendingSpell = false
                self.isSpeaking = false
                self.spell(self.spellingWord)
            } else {
                // Queued utterances (letter-tap feedback) mean "one
                // finished" is not "all finished" — ask the synthesizer.
                self.isSpeaking = self.synthesizer.isSpeaking
                self.deactivateSessionIfIdle()
            }
        }
    }
}
