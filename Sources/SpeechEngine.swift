import AVFoundation
import SwiftUI

/// What a letter says when the app spells a word out.
///
/// Names is the default and stays the default: letter-name knowledge is
/// one of the two strongest predictors of later reading, and for most
/// English consonants the name embeds the sound (b /biː/, t /tiː/).
/// Sounds is what decoding actually needs — and is where letter names
/// mislead, for `w` ("double-u" contains no /w/), `y`, `h`, and every
/// vowel (`a` is named /eɪ/ but says /æ/ in `cat`).
enum LetterVoice: String, CaseIterable, Identifiable {
    case names, sounds, both
    var id: String { rawValue }

    var label: String {
        switch self {
        case .names:  return "Names"
        case .sounds: return "Sounds"
        case .both:   return "Both"
        }
    }
    var detail: String {
        switch self {
        case .names:  return #"“see”, “ay”, “tee”"#
        case .sounds: return #"“k”, “a”, “t”"#
        case .both:   return "Name, then sound"
        }
    }
}

/// Default sound for each letter, as IPA.
///
/// The utterance text is always the plain letter, with the IPA supplied
/// as an attribute — so on a voice that doesn't support IPA notation the
/// synthesiser degrades to saying the letter's name rather than failing
/// silently.
///
/// Vowels are the short sounds, which is what they say in the CVC words
/// this mode is restricted to (`cat`, `pig`, `sun`). Note that stop
/// consonants can't be produced in isolation without a trailing vowel;
/// the synthesiser will add a slight one, which is why this mode is a
/// supplement to the blend step rather than a replacement for it.
enum Phonics {
    static let table: [Character: String] = [
        "a": "æ", "b": "b",  "c": "k",  "d": "d",  "e": "ɛ",
        "f": "f", "g": "ɡ",  "h": "h",  "i": "ɪ",  "j": "dʒ",
        "k": "k", "l": "l",  "m": "m",  "n": "n",  "o": "ɑ",
        "p": "p", "q": "kw", "r": "ɹ",  "s": "s",  "t": "t",
        "u": "ʌ", "v": "v",  "w": "w",  "x": "ks", "y": "j",
        "z": "z",
    ]

    static func sound(for letter: Character) -> String? {
        table[Character(letter.lowercased())]
    }
}

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

    /// One thing to say during a spell pass. A single letter can produce
    /// two steps in `.both` mode ("see", then /k/), so the highlight is
    /// driven by `letterIndex` rather than by the step counter.
    fileprivate struct SpellStep {
        let letterIndex: Int
        let text: String
        let ipa: String?
    }

    private var spellingSteps: [SpellStep] = []
    private var stepIndex: Int = 0
    private var spellingLetterCount: Int = 0
    private var spellingWord: String = ""
    private var isInSpellingMode: Bool = false

    @Published var letterVoice: LetterVoice =
        LetterVoice(rawValue: UserDefaults.standard.string(forKey: "letterVoice") ?? "") ?? .names {
        didSet { UserDefaults.standard.set(letterVoice.rawValue, forKey: "letterVoice") }
    }

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
    private var sessionActive = false
    private var deactivateWork: DispatchWorkItem?

    private func activateSession() {
        deactivateWork?.cancel()
        deactivateWork = nil
        guard !sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
    }

    /// Releasing the session the instant speech stops made the *next*
    /// utterance start before the audio route had ramped up, so its first
    /// phoneme was clipped — which is why the first letter of a spell pass
    /// went missing. Hold the session for a few seconds of silence
    /// instead; ducking is still released, just not between every letter.
    private func deactivateSessionIfIdle() {
        deactivateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.synthesizer.isSpeaking, !self.isInSpellingMode,
                  !self.pendingSpell, !self.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
            self.sessionActive = false
        }
        deactivateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
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
        spellingSteps = Self.steps(for: word, voice: letterVoice)
        spellingLetterCount = word.count
        stepIndex = 0
        speakNextLetter()
    }

    /// Build the spell pass for a word.
    ///
    /// Heart words are forced back to letter names whatever the setting:
    /// sounding out `eye` as /ɛ/-/j/-/ɛ/ or `two` as /t/-/w/-/ɑ/ teaches
    /// an active falsehood. They're learned whole, so the app must never
    /// model them as decodable.
    fileprivate static func steps(for word: String, voice: LetterVoice) -> [SpellStep] {
        let effective = WordStore.decodableWords.contains(word) ? voice : .names
        return word.lowercased().enumerated().flatMap { i, ch -> [SpellStep] in
            let name = SpellStep(letterIndex: i, text: String(ch), ipa: nil)
            guard effective != .names, let ipa = Phonics.sound(for: ch) else { return [name] }
            let sound = SpellStep(letterIndex: i, text: String(ch), ipa: ipa)
            return effective == .sounds ? [sound] : [name, sound]
        }
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
        spellingSteps = []
        stepIndex = 0
        deactivateSessionIfIdle()
    }

    private func utterance(_ text: String, rate: Float, pitch: Float,
                           ipa: String? = nil) -> AVSpeechUtterance {
        let u: AVSpeechUtterance
        if let ipa {
            // Text stays the plain letter so an IPA-unaware voice falls
            // back to the letter's name instead of going silent.
            let attributed = NSMutableAttributedString(string: text)
            attributed.addAttribute(
                NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute),
                value: ipa,
                range: NSRange(location: 0, length: attributed.length)
            )
            u = AVSpeechUtterance(attributedString: attributed)
        } else {
            u = AVSpeechUtterance(string: text)
        }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = 1.0
        u.voice = resolvedVoice()
        // A beat of silence in front of every utterance. Single phonemes
        // are only ~0.25–0.4s long, so even a few tens of milliseconds of
        // route ramp-up eats an audible part of the first sound.
        u.preUtteranceDelay = 0.08
        return u
    }

    /// Say a single letter the way the current mode says it — used by the
    /// per-letter tap feedback in the reader and the two spelling games,
    /// which previously always said the letter's name regardless.
    func speakLetter(_ letter: Character, in word: String, interrupting: Bool = false) {
        guard !isMuted else { return }
        let useSounds = letterVoice != .names && WordStore.decodableWords.contains(word)
        let ipa = useSounds ? Phonics.sound(for: letter) : nil
        if interrupting || isInSpellingMode || pendingSpell { stopAll() }
        isSpeaking = true
        activateSession()
        synthesizer.speak(utterance(String(letter), rate: 0.4, pitch: 1.2, ipa: ipa))
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        guard !selectedVoiceIdentifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }

    private func speakNextLetter() {
        guard stepIndex < spellingSteps.count else {
            // All letters done — blend them back into the word.
            //
            // The sequence used to be whole → letters → whole, which skips
            // the step where reading actually happens: running the letters
            // together into the word. Now the tiles sweep left-to-right in
            // time with the word being spoken, so the child sees the parts
            // become the whole rather than just hearing the whole again.
            let word = spellingWord
            let count = spellingLetterCount
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard gen == self.generation else { return }
                self.isSpelling = false
                self.isInSpellingMode = false
                self.activateSession()
                self.synthesizer.speak(self.utterance(word, rate: 0.42, pitch: 1.1))
                self.blendSweep(count: count, gen: gen)
            }
            return
        }
        let step = spellingSteps[stepIndex]
        highlightedLetterIndex = step.letterIndex
        stepIndex += 1
        activateSession()
        synthesizer.speak(utterance(step.text, rate: spellingSpeed.rate, pitch: 1.2, ipa: step.ipa))
    }

    /// Runs the highlight across every tile in about the time it takes to
    /// say the word, then clears it.
    private func blendSweep(count: Int, gen: Int) {
        guard count > 0 else { return }
        let step = 0.15
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                guard gen == self.generation else { return }
                self.highlightedLetterIndex = i
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(count) + 0.1) {
            guard gen == self.generation else { return }
            self.highlightedLetterIndex = -1
        }
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
