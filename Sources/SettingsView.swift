import AVFoundation
import SwiftUI

/// Stands between a long press and the settings screens.
///
/// The long press alone was never a gate: it sat on the picture — the
/// largest target on screen — and a child resting a finger while thinking
/// landed in a form with the voice picker and the word filter in it. The
/// onboarding even advertised it as the way in. A single addition problem
/// is the conventional, low-friction way to establish there's an adult
/// holding the phone.
struct ParentGateView: View {
    @Binding var passed: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var a = Int.random(in: 4...9)
    @State private var b = Int.random(in: 4...9)
    @State private var wrongPick: Int? = nil

    private var answer: Int { a + b }

    private var choices: [Int] {
        var set = Set([answer])
        while set.count < 4 {
            let n = answer + Int.random(in: -4...4)
            if n != answer, n > 0 { set.insert(n) }
        }
        // Deterministic order per question so the buttons don't reshuffle
        // on every redraw.
        return set.sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("Grown-ups only")
                    .font(.title2.bold())
                Text("What is \(a) + \(b)?")
                    .font(.system(size: 44, weight: .black, design: .rounded))

                HStack(spacing: 12) {
                    ForEach(choices, id: \.self) { n in
                        Button {
                            if n == answer {
                                passed = true
                                dismiss()
                            } else {
                                wrongPick = n
                                a = Int.random(in: 4...9)
                                b = Int.random(in: 4...9)
                            }
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .frame(minWidth: 64, minHeight: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(wrongPick == n ? Color.red.opacity(0.25)
                                                             : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var wordStore: WordStore
    @ObservedObject var speechEngine: SpeechEngine
    @Environment(\.dismiss) var dismiss
    @AppStorage("isUppercase")     private var isUppercase     = true
    @AppStorage("showPlayButton")  private var showPlayButton  = false
    @AppStorage("showSpellButton") private var showSpellButton = false
    @AppStorage("mathAllowAdd")    private var mathAllowAdd    = true
    @AppStorage("mathAllowSub")    private var mathAllowSub    = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Speed", selection: $speechEngine.spellingSpeed) {
                        ForEach(SpellingSpeed.allCases, id: \.self) { speed in
                            Text(speed.rawValue).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Mute all speech", isOn: $speechEngine.isMuted)
                } header: {
                    Text("Speech")
                } footer: {
                    Text("The app speaks even when the phone's ring/silent switch is set to silent, so this is the way to quiet it.")
                }

                Section {
                    Toggle("Capital letters", isOn: $isUppercase)
                } header: {
                    Text("Letters")
                } footer: {
                    Text("Capitals are easier for beginners to tell apart — no b/d/p/q confusion. Turn this off once your reader is comfortable with lowercase.")
                }

                Section {
                    Toggle("Only words with pictures", isOn: $wordStore.onlyWordsWithImages)
                } header: {
                    Text("Word Filter")
                } footer: {
                    Text("\(WordStore.wordsWithImages.count) of \(WordStore.words.count) words have a real picture. When on, only those words are shown.")
                }

                Section {
                    Toggle("Random Order", isOn: $wordStore.isRandomMode)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("When off, words appear in alphabetical order. Swipe left = next, swipe right = previous.")
                }

                Section {
                    Toggle("Show Play button", isOn: $showPlayButton)
                    Toggle("Show Spell button", isOn: $showSpellButton)
                } header: {
                    Text("Buttons")
                } footer: {
                    Text("Hide buttons to let kids focus on swiping and listening. The word is still spoken automatically on every swipe.")
                }

                Section {
                    Toggle("Addition (+)", isOn: $mathAllowAdd)
                    Toggle("Subtraction (−)", isOn: $mathAllowSub)
                } header: {
                    Text("Count It")
                } footer: {
                    Text("Choose which kinds of problems show up in the Count It game. At least one should be on.")
                }

                Section {
                    Picker("Voice", selection: $speechEngine.selectedVoiceIdentifier) {
                        Text("System Default").tag("")
                        ForEach(SpeechEngine.availableVoices, id: \.identifier) { voice in
                            Text(voiceLabel(voice))
                                .tag(voice.identifier)
                        }
                    }
                    .onChange(of: speechEngine.selectedVoiceIdentifier) { _, id in
                        speechEngine.selectVoice(id)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Premium and Enhanced voices sound more natural. Download extras in Settings → Accessibility → Spoken Content → Voices.")
                }

                Section {
                    HStack {
                        Text("Words mastered")
                        Spacer()
                        Text("\(WordProgress.shared.masteredCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Words in rotation")
                        Spacer()
                        Text("\(WordProgress.activeSetSize)")
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        WordProgress.shared.reset()
                    } label: {
                        Label("Start the word list over", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Progress")
                } footer: {
                    Text("Only a handful of words are in play at once, and a word is only retired after three correct answers — a word has to come round many times before it sticks. New words are introduced as earlier ones are mastered.")
                }

                Section {
                    HStack {
                        Text("Active words")
                        Spacer()
                        Text("\(wordStore.activeWords.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total in library")
                        Spacer()
                        Text("\(WordStore.words.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Words with pictures")
                        Spacer()
                        Text("\(WordStore.wordsWithImages.count)")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        GalleryView()
                    } label: {
                        Label("Image Gallery", systemImage: "photo.stack")
                    }
                    #if DEBUG
                    NavigationLink {
                        AltGalleryView()
                    } label: {
                        Label("Alternative Images", systemImage: "photo.on.rectangle.angled")
                    }
                    #endif
                } header: {
                    Text("Word List")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let lang = voice.language // e.g. "en-US", "en-GB"
        let locale = lang.dropFirst(3) // "US", "GB"
        let quality: String
        switch voice.quality {
        case .premium:  quality = " ★★"
        case .enhanced: quality = " ★"
        default:        quality = ""
        }
        return "\(voice.name) (\(locale))\(quality)"
    }
}
