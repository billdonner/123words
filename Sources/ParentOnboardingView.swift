import SwiftUI

struct ParentOnboardingView: View {
    @AppStorage("hasSeenParentOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var wave = false
    @State private var tileBounce = false

    private let tileColors: [Color] = [
        Color(red: 0.97, green: 0.32, blue: 0.36),
        Color(red: 0.99, green: 0.78, blue: 0.18),
        Color(red: 0.22, green: 0.78, blue: 0.42),
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

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                Text("👋")
                    .font(.system(size: 72))
                    .rotationEffect(.degrees(wave ? 18 : -10), anchor: .bottom)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: wave)
                    .padding(.bottom, 8)

                Text("Hey, grown-ups!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.bottom, 8)

                Text("123 Words turns a swipe into a spelling lesson — bright pictures, friendly voices, and tiles that dance as each letter says its name.")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                // Animated 1-2-3 tile preview
                HStack(spacing: 14) {
                    ForEach(Array(zip(["1","2","3"], tileColors)), id: \.0) { digit, color in
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(color)
                                .frame(width: 64, height: 64)
                                .shadow(color: color.opacity(0.55), radius: 10, y: 4)
                            Text(digit)
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(tileBounce ? 1.0 : 0.85)
                    }
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.55).repeatForever(autoreverses: true), value: tileBounce)
                .padding(.bottom, 28)

                // Settings access card
                VStack(spacing: 14) {
                    Text("🔧  Where are the settings?")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Hidden on purpose — little fingers can't wander off. To open them yourself:")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    HStack(spacing: 14) {
                        Text("👆")
                            .font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Press & hold the picture")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("That's it — Settings will pop up.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .background(.white.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                .padding(.horizontal, 20)

                Spacer(minLength: 16)

                Button {
                    hasSeenOnboarding = true
                    dismiss()
                } label: {
                    Text("Let's play! →")
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
                .padding(.bottom, 36)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            wave = true
            tileBounce = true
        }
    }
}
