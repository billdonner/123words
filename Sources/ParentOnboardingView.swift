import SwiftUI

/// Shown once, on first launch, from the hub. It used to be presented
/// from inside the reader, so a parent who went straight to a game never
/// saw it at all — including the part explaining where Settings live.
struct ParentOnboardingView: View {
    @AppStorage("hasSeenParentOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hubMode") private var hubModeRaw: String = HubMode.race.rawValue
    @AppStorage("childAge") private var childAge: Int = 0
    @AppStorage("memoryBoardSize") private var memoryBoardSize: Int = 4
    @Environment(\.dismiss) private var dismiss
    @State private var wave = false
    @State private var tileBounce = false

    private let tileColors: [Color] = [
        Color(red: 0.97, green: 0.32, blue: 0.36),
        Color(red: 0.99, green: 0.78, blue: 0.18),
        Color(red: 0.22, green: 0.78, blue: 0.42),
    ]

    private let ageChoices: [(label: String, age: Int, blurb: String)] = [
        ("3–4", 3, "No timer"),
        ("5",   5, "Timer optional"),
        ("6+",  6, "Timed races"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.16, blue: 0.78),
                    Color(red: 0.95, green: 0.32, blue: 0.55),
                    Color(red: 0.99, green: 0.55, blue: 0.28),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text("👋")
                        .font(.system(size: 64))
                        .rotationEffect(.degrees(wave ? 18 : -10), anchor: .bottom)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: wave)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    Text("Hey, grown-ups!")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .padding(.bottom, 8)

                    Text("123 Words turns a swipe into a spelling lesson — bright pictures, friendly voices, and tiles that dance as each letter says its name.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 22)

                    // Animated 1-2-3 tile preview
                    HStack(spacing: 14) {
                        ForEach(Array(zip(["1","2","3"], tileColors)), id: \.0) { digit, color in
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(color)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: color.opacity(0.55), radius: 10, y: 4)
                                Text(digit)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .scaleEffect(tileBounce ? 1.0 : 0.85)
                        }
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.55).repeatForever(autoreverses: true), value: tileBounce)
                    .padding(.bottom, 22)

                    ageCard
                    settingsCard
                    guidedAccessCard

                    Button {
                        applyAge()
                        hasSeenOnboarding = true
                        dismiss()
                    } label: {
                        Text(childAge == 0 ? "Skip for now" : "Let's play! →")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.42, green: 0.16, blue: 0.78))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                            .padding(.horizontal, 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            wave = true
            tileBounce = true
        }
    }

    // A timer, a score and a personal best assume the child can judge
    // elapsed time, hold back a rushed answer, and read a miss as "try
    // again" rather than "I'm bad at this" — none of which is reliably
    // in place before about six. Rather than guess, ask once.
    private var ageCard: some View {
        VStack(spacing: 12) {
            Text("👶  How old is your reader?")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Younger readers get the calm, untimed home screen. You can change this any time in Parent Settings.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            HStack(spacing: 10) {
                ForEach(ageChoices, id: \.age) { choice in
                    Button { childAge = choice.age } label: {
                        VStack(spacing: 2) {
                            Text(choice.label)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                            Text(choice.blurb)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(childAge == choice.age ? 0.38 : 0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(.white.opacity(childAge == choice.age ? 0.9 : 0.3),
                                                      lineWidth: childAge == choice.age ? 3 : 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var settingsCard: some View {
        VStack(spacing: 10) {
            Text("🔧  Where are the settings?")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Hidden on purpose — little fingers can't wander off.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Text("👆").font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Press & hold the picture")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Hold for a moment, then answer one quick question to prove you're a grown-up.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var guidedAccessCard: some View {
        VStack(spacing: 10) {
            Text("🔒  Keep them in the app")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("iOS has a built-in child lock. Turn on Settings → Accessibility → Guided Access, then triple-click the side button once 123 Words is open. Now a stray swipe can't land them in Messages.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
        .padding(.horizontal, 20)
    }

    private func applyAge() {
        guard childAge > 0 else { return }
        hubModeRaw = childAge >= 5 ? HubMode.race.rawValue : HubMode.classic.rawValue
        // 16 cards exceeds a 3–4-year-old's visuospatial span (typically
        // 3–4 items); 8 is correctly sized.
        memoryBoardSize = childAge >= 6 ? 8 : 4
    }
}
