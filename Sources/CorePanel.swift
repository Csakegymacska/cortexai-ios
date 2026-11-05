import SwiftUI
import Foundation

/// "Cortex Void Core" — the in-house model that trains itself every night.
///
/// The backend only sends numbers, so this panel never names a provider or a base
/// model: it just tells the user how far the core has got and when it trains next.
struct CorePanel: View {
    @State private var core: CortexClient.CoreStatus?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let core {
                progress(core)
                if let parts = core.parts {
                    HStack(spacing: 10) {
                        meter("Identity", parts.identity / 100)
                        meter("Catalogue", parts.catalog / 100)
                        meter("Hungarian", parts.language / 100)
                    }
                }
                footer(core)
            } else if failed {
                Text("Core status is unavailable right now.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textFaint)
            } else {
                ProgressView().tint(Theme.violetSoft)
            }
        }
        .padding(.vertical, 6)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.brand).frame(width: 34, height: 34)
                Image(systemName: "atom")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex Void Core").font(.system(size: 14.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
            if let core {
                Text(core.phase == "ready" ? "Ready" : "Learning")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.violet.opacity(0.16)))
                    .foregroundStyle(core.phase == "ready" ? Theme.success : Theme.violetSoft)
            }
        }
    }

    private var subtitle: String {
        guard let core else { return "The model we build ourselves." }
        if core.selfhost {
            return "Serving your replies from our own cluster."
        }
        return "Nightly round \(core.nextRound) · replies stay on the full Cortex Void stack"
    }

    private func progress(_ core: CortexClient.CoreStatus) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(6, geo.size.width * CGFloat(core.progress) / 100))
                }
            }
            .frame(height: 7)
            HStack {
                Text("Round \(core.version) · \(String(format: "%.1f", core.score)) of \(String(format: "%.0f", core.target)) points")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                if let trained = core.trainedAt, let day = trained.split(separator: "T").first {
                    Text("last \(day)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private func meter(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
            Text("\(Int(value * 100))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(value >= 0.9 ? Theme.success : Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private func footer(_ core: CortexClient.CoreStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = core.history.last {
                Text("Champion v\(last.v) · gate +\(String(format: "%.2f", core.gate)) points to take the crown")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            } else {
                Text("No champion yet — the first passing round takes the crown.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
            Text("Trained on the CortexAnime catalogue and our Hungarian subtitles.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private func load() async {
        do {
            core = try await CortexClient.shared.core()
        } catch {
            failed = true
        }
    }
}
