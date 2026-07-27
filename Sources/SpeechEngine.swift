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
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: .duckOthers
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }
    }

    func selectVoice(_ identifier: String) {
        selectedVoiceIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "selectedVoiceID")
    }

    func speak(_ word: String) {
        stopAll()
        isSpeaking = true
        isInSpellingMode = false
        let utterance = AVSpeechUtterance(string: word)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        utterance.voice = resolvedVoice()
        synthesizer.speak(utterance)
    }

    func spell(_ word: String) {
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.15
        utterance.volume = 1.0
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func speakThenSpell(_ word: String) {
        stopAll()
        spellingWord = word
        pendingSpell = true
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: word)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0
        utterance.voice = resolvedVoice()
        synthesizer.speak(utterance)
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
                let utterance = AVSpeechUtterance(string: word)
                utterance.rate = 0.48
                utterance.pitchMultiplier = 1.1
                utterance.volume = 1.0
                utterance.voice = self.resolvedVoice()
                self.synthesizer.speak(utterance)
            }
            return
        }
        highlightedLetterIndex = currentLetterIndex
        let letter = spellingLetters[currentLetterIndex]
        currentLetterIndex += 1

        let utterance = AVSpeechUtterance(string: letter)
        utterance.rate = spellingSpeed.rate
        utterance.pitchMultiplier = 1.2
        utterance.volume = 1.0
        utterance.voice = resolvedVoice()
        synthesizer.speak(utterance)
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
                self.isSpeaking = false
            }
        }
    }
}
