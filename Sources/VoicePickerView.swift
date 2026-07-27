import AVFoundation
import SwiftUI

// MARK: - Voice Picker Page

struct VoicePickerView: View {
    @ObservedObject var speechEngine: SpeechEngine
    @Environment(\.dismiss) var dismiss

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            // Purple → pink gradient — distinct from the main orange palette
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.15, blue: 0.85),
                    Color(red: 0.88, green: 0.25, blue: 0.62),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──
                ZStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(16)
                        }
                        Spacer()
                    }
                    VStack(spacing: 2) {
                        Text("🗣️")
                            .font(.system(size: 44))
                        Text("Pick a Voice")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)

                Text("Tap a face to hear them say hello!")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 12)

                // ── Voice grid ──
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        // System Default
                        VoiceCard(
                            face: "🔊",
                            flag: "",
                            name: "Default",
                            subtitleLines: ["System", "Voice"],
                            quality: nil,
                            isSelected: speechEngine.selectedVoiceIdentifier.isEmpty
                        ) {
                            speechEngine.speakHello(with: nil)
                            speechEngine.selectVoice("")
                        }

                        ForEach(SpeechEngine.availableVoices, id: \.identifier) { voice in
                            let parts = voice.language.split(separator: "-")
                            let region = parts.count > 1 ? String(parts[1]) : ""
                            VoiceCard(
                                face: faceEmoji(for: voice.name),
                                flag: flagEmoji(for: voice.language),
                                name: voice.name,
                                subtitleLines: [accentLabel(for: voice.language), region],
                                quality: voice.quality,
                                isSelected: speechEngine.selectedVoiceIdentifier == voice.identifier
                            ) {
                                speechEngine.speakHello(with: voice)
                                speechEngine.selectVoice(voice.identifier)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func faceEmoji(for name: String) -> String {
        // Strip the "(Enhanced)" / "(Premium)" / "(2)" suffixes iOS
        // appends to download variants so the dict lookup hits.
        let base = name.components(separatedBy: " (").first ?? name
        let known: [String: String] = [
            // Apple's classic English voices — warmer/more expressive
            // variants than the generic adult head we used before.
            "Samantha": "👩🏽",     "Alex":    "🧔🏾",     "Fred":    "🧓🏻",
            "Ava":      "👩🏿‍🦱",  "Joanna":  "👩🏽‍🦰",  "Kathy":   "👵🏼",
            "Allison":  "👩🏾‍🦰",  "Susan":   "👩🏼‍🦳",  "Tom":     "🧔🏽",
            "Aaron":    "👨🏿",     "Nora":    "👩🏾‍🦱",  "Zoe":     "👩🏻‍🦰",
            "Serena":   "👩🏽‍🦱",
            // GB / Irish
            "Daniel":   "👨🏼",     "Kate":    "👩🏻",     "Arthur":  "🧓🏻",
            "Moira":    "👩🏻‍🦱",  "Fiona":   "👩🏻‍🦰",
            // Australian / NZ
            "Karen":    "👩🏽‍🦰",  "Lee":     "👨🏽‍🦱",
            "Matilda":  "👩🏼‍🦰",  "Oliver":  "👦🏼",
            // South African / Indian / Nigerian / other
            "Tessa":    "👩🏿",     "Rishi":   "👨🏽",
            "Gordon":   "🧔🏾",     "Helena":  "👩🏾",
            "Victoria": "👩🏿‍🦱",  "Martha":  "👵🏽",
            // iOS 17+ personality voices — the names themselves are
            // strong hints, so these match accordingly.
            "Grandma":  "👵🏼",     "Grandpa": "🧓🏻",
            "Junior":   "👦🏼",     "Eddy":    "🧑🏼‍🦰",
            "Flo":      "💁🏽‍♀️",  "Reed":    "🧑🏻",
            "Rocko":    "🧑🏻‍🎤",  "Sandy":   "👩🏼",
            "Shelley":  "👩🏻‍🦱",
            "Siri":     "🤖",
        ]
        if let face = known[base] { return face }
        // Fallback pool — friendlier mix of smileys and diverse people
        // instead of the old all-adult-heads set. Unfamiliar voices
        // get something warm rather than a serious face.
        let pool = [
            "😊", "🥰", "🤩", "🥳", "😎", "🤓", "🤠",
            "👧🏻", "👦🏾", "🧒🏽", "🧓🏻", "🧓🏿",
            "👩🏽‍🦰", "👨🏻‍🦱", "👩🏾‍🦱", "👨🏿‍🦳", "👩🏼‍🦳",
        ]
        let hash = base.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return pool[abs(hash) % pool.count]
    }

    private func flagEmoji(for lang: String) -> String {
        switch lang {
        case "en-US": return "🇺🇸"
        case "en-GB": return "🇬🇧"
        case "en-AU": return "🇦🇺"
        case "en-IE": return "🇮🇪"
        case "en-ZA": return "🇿🇦"
        case "en-IN": return "🇮🇳"
        case "en-NZ": return "🇳🇿"
        case "en-SG": return "🇸🇬"
        case "en-CA": return "🇨🇦"
        case "en-NG": return "🇳🇬"
        case "en-PH": return "🇵🇭"
        default:      return "🌍"
        }
    }

    private func accentLabel(for lang: String) -> String {
        switch lang {
        case "en-US": return "American"
        case "en-GB": return "British"
        case "en-AU": return "Australian"
        case "en-IE": return "Irish"
        case "en-ZA": return "South African"
        case "en-IN": return "Indian"
        case "en-NZ": return "New Zealand"
        case "en-SG": return "Singaporean"
        case "en-CA": return "Canadian"
        case "en-NG": return "Nigerian"
        case "en-PH": return "Filipino"
        default:      return "English"
        }
    }
}

// MARK: - Voice Card

struct VoiceCard: View {
    let face: String
    let flag: String
    let name: String
    let subtitleLines: [String]
    let quality: AVSpeechSynthesisVoiceQuality?
    let isSelected: Bool
    let onTap: () -> Void

    private var stars: String {
        switch quality {
        case .premium:  return "★★★"
        case .enhanced: return "★★"
        default:        return "★"
        }
    }

    private var starColor: Color {
        switch quality {
        case .premium:  return .yellow
        case .enhanced: return Color(red: 1, green: 0.85, blue: 0.4)
        default:        return .white.opacity(0.5)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {

                // Face + flag badge
                ZStack(alignment: .bottomTrailing) {
                    Text(face)
                        .font(.system(size: 62))
                        .frame(height: 72)

                    if !flag.isEmpty {
                        Text(flag)
                            .font(.system(size: 30))
                            .offset(x: 12, y: 12)
                    }
                }
                .padding(.top, 12)

                // Name
                Text(name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Accent label
                if let accent = subtitleLines.first, !accent.isEmpty {
                    Text(accent)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                // Quality stars
                Text(stars)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(starColor)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(isSelected
                          ? Color.yellow.opacity(0.28)
                          : Color.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(
                        isSelected ? Color.yellow : Color.white.opacity(0.22),
                        lineWidth: isSelected ? 3.5 : 1.5
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
