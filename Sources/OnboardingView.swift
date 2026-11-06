import SwiftUI

/// Three black pages: the promise, the profiles, the privacy note.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0

    private let pages: [Page] = [
        Page(symbol: "sparkles",
             title: "Cortex Void",
             body: "The AI by OmegaTech and CortexAnime. Ask anything: code, ideas, anime, learning — in Hungarian or English.",
             accent: Theme.violetSoft),
        Page(symbol: "person.2.fill",
             title: "Your profiles",
             body: "You can create separate profiles for coding, learning or anime recommendations. Each gets its own voice and model.",
             accent: Theme.cyan),
        Page(symbol: "lock.shield.fill",
             title: "Private by default",
             body: "Conversations stay on this device. No account, no ads — and Cortex Void never reveals what technology it runs on.",
             accent: Theme.magenta)
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    pageView(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.violetSoft : Theme.textFaint.opacity(0.4))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }
            .padding(.bottom, 22)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    state.hasOnboarded = true
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Start chatting")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: Theme.violet.opacity(0.5), radius: 22, y: 10)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Button("Skip") { state.hasOnboarded = true }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textFaint)
                .padding(.bottom, 18)
        }
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(item.accent.opacity(0.12))
                    .frame(width: 132, height: 132)
                Circle()
                    .strokeBorder(item.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: item.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(item.accent)
            }
            VStack(spacing: 12) {
                Text(item.title)
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.text)
                Text(item.body)
                    .font(Theme.body(15.5))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
            }
            Spacer()
            Spacer()
        }
    }

    struct Page {
        let symbol: String
        let title: String
        let body: String
        let accent: Color
    }
}
