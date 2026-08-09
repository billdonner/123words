import AVFoundation
import SwiftUI

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
