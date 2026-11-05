import SwiftUI

// MARK: - Napi keret sáv
//
// A szerveroldali átszervezés után a legfontosabb szám a napi tokenkeret: enélkül a
// felhasználó csak akkor szembesül vele, amikor 429-et kap. Ez a vékony sáv a fejléc
// alatt ül, minden szélességen elfér, és koppintásra kinyitja az előfizetést.
//
// A keret a FIÓKHOZ tartozik, ezért itt soha nem számolunk — a szám a /api/v1/usage-ból
// jön, és minden válasz után frissül.

@MainActor
struct UsageStrip: View {
    @StateObject private var store = SubscriptionStore.shared
    @State private var showPlans = false

    private var used: Int? { store.usedTokens }

    private var fraction: Double {
        guard let used else { return 0 }
        return min(1, Double(used) / Double(max(1, store.tier.dailyTokens)))
    }

    private var tight: Bool { used != nil && fraction >= 0.9 }
    private var exhausted: Bool { used != nil && fraction >= 0.995 }
    private var tint: Color { exhausted ? Theme.danger : (tight ? Theme.magenta : Theme.violet) }

    private var caption: String {
        guard used != nil else { return store.tier.label }
        return store.tier.label + " · " + store.remainingText
    }

    var body: some View {
        Button {
            showPlans = true
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.hairlineStrong)
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(used == nil ? 0 : 4, geo.size.width * fraction))
                            .animation(CortexMotion.snappy, value: fraction)
                    }
                }
                .frame(height: 3)

                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(exhausted ? Theme.danger : Theme.textFaint)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(used == nil)
        .accessibilityIdentifier("chat.usage")
        .accessibilityLabel(used == nil ? "\(store.tier.label) plan" : "\(store.tier.label) plan, \(store.remainingText)")
        .sheet(isPresented: $showPlans) { SubscriptionView() }
        .task {
            // Indításkor egyszer lekérjük; utána minden válasz után frissül.
            if store.usedTokens == nil { await store.refreshUsage() }
        }
    }
}

// MARK: - Elfogyott keret

/// A beszélgetés tetején megjelenő sáv, amikor a napi keret elfogyott. Nem hibaüzenet:
/// a helyzetet mutatja, és a megoldást kínálja. Magától eltűnik, ha a szerver szerint
/// mégis van keret (másik kulcs, új nap).
@MainActor
struct QuotaBanner: View {
    @StateObject private var store = SubscriptionStore.shared
    @State private var showPlans = false

    private var visible: Bool {
        store.usedTokens != nil && store.usageFraction >= 0.995
    }

    var body: some View {
        if visible {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.magenta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily allowance used up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("It resets at midnight UTC. A bigger plan lifts the ceiling now.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Button("Plans") {
                    showPlans = true
                    Haptics.tap()
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.violetSoft)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .cortexGlass(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous),
                         tint: Theme.magenta.opacity(0.18))
            .sheet(isPresented: $showPlans) { SubscriptionView() }
        }
    }
}
