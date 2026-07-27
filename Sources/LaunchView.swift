import SwiftUI

struct LaunchView: View {
    @Binding var isShowing: Bool
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    private let tileColors: [Color] = [
        Color(red: 0.95, green: 0.25, blue: 0.30),
        Color(red: 0.20, green: 0.72, blue: 0.35),
        Color(red: 0.20, green: 0.48, blue: 0.95),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.14, blue: 0.28)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Three letter tiles
                HStack(spacing: 16) {
                    ForEach(Array(zip(["1","2","3"], tileColors)), id: \.0) { digit, color in
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(color)
                                .frame(width: 88, height: 88)
                                .shadow(color: color.opacity(0.5), radius: 12, y: 6)
                            Text(digit)
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Spacer().frame(height: 32)

                Text("WORDS")
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(2)

                Text("swipe · hear · learn")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)

                Spacer()

                Text("for little readers")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 48)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                isShowing = false
            }
        }
    }
}
