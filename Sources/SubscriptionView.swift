import SwiftUI

// MARK: - Előfizetés
//
// A csomagok és a napi keret egy helyen. Az API-kulcsot a weben kell létrehozni —
// innen egy gombbal nyílik meg a cortanime.eu/api-keys oldal.

@MainActor
struct SubscriptionView: View {
    @State private var redeemCode = ""
    @State private var redeemMessage: String?
    @State private var redeeming = false
    @StateObject private var store = SubscriptionStore.shared
    @StateObject private var vault = APIKeyVault.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var keyDraft: String = ""
    @State private var showingKeyField = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    usageCard
                    plans
                    revolutSection
                    apiKeys
                    footnote
                }
                .padding(18)
            }
            .background(Theme.ink)
            .navigationTitle("Előfizetés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kész") { dismiss() }.tint(Theme.violetSoft)
                }
            }
            .task {
                await store.refreshEntitlement()
                await store.refreshUsage()
            }
        }
    }

    // MARK: Keret

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.plan.label.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.violet.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Theme.violetSoft)
                Spacer()
                Text(store.plan.quotaText + " / nap")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
            ProgressView(value: store.usageFraction)
                .tint(Theme.violet)
            HStack {
                Text(store.remainingText)
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                Spacer()
                if let calls = store.callsToday, calls > 0 {
                    Text("\(calls) hívás ma")
                        .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                }
            }
            Text("A keret a fiókodhoz tartozik, nem az eszközhöz. UTC éjfélkor áll vissza.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textFaint)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
    }

    // MARK: Csomagok

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(CortexPlan.allCases) { plan in
                planRow(plan)
            }
            if let error = store.purchaseError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
            }
            Button {
                Task { await store.restore() }
            } label: {
                Text("Vásárlások visszaállítása")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Revolut fizetés + kód beváltása

    private var revolutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REVOLUT FIZETÉS")
                .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Theme.textFaint)
            Text("Fizess Revoluttal, majd a kapott kóddal aktiváld a csomagot. Az előfizetés azonnal emeli a napi keretet.")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            Link(destination: URL(string: SubscriptionStore.revolutLink)!) {
                Label("Megnyitás Revolutban", systemImage: "creditcard")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Theme.violet.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Theme.violetSoft)
            }
            HStack(spacing: 8) {
                TextField("Beváltó kód (pl. CORTEXPRO1M)", text: $redeemCode)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(10)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    redeeming = true
                    Task {
                        let err = await store.redeem(code: redeemCode)
                        redeemMessage = err ?? "Sikeres aktiválás!"
                        redeeming = false
                    }
                } label: {
                    if redeeming { ProgressView().tint(Theme.violetSoft) }
                    else { Text("Beváltás").font(.system(size: 13, weight: .semibold)) }
                }
                .disabled(redeemCode.trimmingCharacters(in: .whitespaces).isEmpty || redeeming)
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
            }
            if let msg = redeemMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(msg.contains("Sikeres") ? .green : Theme.textMuted)
            }
        }
        .padding(14)
        .background(Theme.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func planRow(_ plan: CortexPlan) -> some View {
        let active = store.plan == plan
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.label).font(.system(size: 14.5, weight: .semibold))
                    if active {
                        Text("AKTÍV")
                            .font(.system(size: 8.5, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Theme.cyan)
                    }
                }
                Text(plan.blurb)
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
            Spacer()
            if let id = plan.productID,
               let product = store.products.first(where: { $0.id == id }) {
                Button {
                    Task { await store.purchase(plan) }
                } label: {
                    Text(product.displayPrice + "/hó")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.violet.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(store.isPurchasing || active)
            } else if plan == .free {
                Text("alapból")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            } else {
                Text("hamarosan")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? Theme.violet.opacity(0.6) : Theme.hairline))
    }

    // MARK: API-kulcs

    private var apiKeys: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API-kulcs")
                .font(.system(size: 13, weight: .semibold))
            Text("A kulcsot a weben hozod létre — ott látod egyszer, és onnan másolod ide.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textFaint)

            Button {
                if let url = URL(string: "https://cortanime.eu/api-keys") { openURL(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                    Text("Kulcs létrehozása a weben")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(12)
                .background(Theme.violet.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.violetSoft)
            }

            if let key = vault.currentKey {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.cyan)
                    Text(masked(key)).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Button("Törlés", role: .destructive) { vault.clear() }
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
            } else if showingKeyField {
                HStack(spacing: 8) {
                    TextField("cx_…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                    Button("Mentés") {
                        vault.save(keyDraft)
                        keyDraft = ""
                        showingKeyField = false
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
            } else {
                Button {
                    showingKeyField = true
                } label: {
                    Text("Már van kulcsom — beillesztés")
                        .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(14)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
    }

    private var footnote: some View {
        Text("A Cortex Phantom a DeepSeek-V4.1-Flash motoron fut (1M token kontextus, kép-bemenet). " +
             "A napi keretet a szerver méri és kényszeríti ki, a válaszok valódi tokenhasználata alapján.")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textFaint)
    }

    private func masked(_ key: String) -> String {
        guard key.count > 12 else { return key }
        return String(key.prefix(6)) + "••••••••" + String(key.suffix(4))
    }
}
