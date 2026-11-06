import Foundation
import StoreKit

// MARK: - Csomagok
//
// Három szint, a napi tokenkerettel együtt. A keret a FIÓKHOZ tartozik, nem az
// eszközhöz: a szerver méri (cortanime.eu/api/v1/usage), az app csak megjeleníti.
//
//   Free   50 000 000 token / nap   — ingyenes
//   Pro   220 000 000 token / nap   — havi előfizetés
//   Max  2 200 000 000 token / nap  — havi előfizetés (nagyobb)
//
// Az offline (letöltött) modell kikerült: a Phantom kizárólag szerveroldalon fut.

enum CortexPlan: String, CaseIterable, Identifiable {
    case free, pro, max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }

    var blurb: String {
        switch self {
        case .free: return "5 million tokens / day · 2 API keys"
        case .pro: return "50 million tokens / day · 10 API keys"
        case .max: return "500 million tokens / day · 40 API keys"
        }
    }

    /// Napi tokenkeret — ugyanaz a szám, amit a szerver kényszerít ki.
    var dailyTokens: Int {
        switch self {
        case .free: return 5_000_000
        case .pro: return 50_000_000
        case .max: return 500_000_000
        }
    }

    var keyLimit: Int {
        switch self {
        case .free: return 2
        case .pro: return 10
        case .max: return 40
        }
    }

    /// StoreKit termékazonosító (App Store Connectben ugyanezekkel a nevekkel kell létrehozni).
    var productID: String? {
        switch self {
        case .free: return nil
        case .pro: return "eu.cortanime.cortexai.plan.pro.monthly"
        case .max: return "eu.cortanime.cortexai.plan.max.monthly"
        }
    }

    /// Emberi formátum: „50 million", „2,2 billion".
    var quotaText: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "hu_HU")
        f.maximumFractionDigits = 1
        if dailyTokens >= 1_000_000_000 {
            return (f.string(from: NSNumber(value: Double(dailyTokens) / 1_000_000_000)) ?? "?") + " billion"
        }
        return (f.string(from: NSNumber(value: Double(dailyTokens) / 1_000_000)) ?? "?") + " million"
    }
}

// MARK: - Store

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var plan: CortexPlan = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var isPurchasing = false

    /// Szerveroldali használat (a worker méri) — ha még nem jött meg, nil.
    @Published private(set) var usedTokens: Int?
    @Published private(set) var callsToday: Int?

    private var updates: Task<Void, Never>?

    var tier: CortexPlan { plan }

    var remainingText: String {
        guard let used = usedTokens else { return "—" }
        let left = max(0, plan.dailyTokens - used)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "hu_HU")
        if left >= 1_000_000_000 {
            return (f.string(from: NSNumber(value: Double(left) / 1_000_000_000)) ?? "?") + " billion token maradt"
        }
        if left >= 1_000_000 {
            return (f.string(from: NSNumber(value: Double(left) / 1_000_000)) ?? "?") + " million token maradt"
        }
        return (f.string(from: NSNumber(value: left)) ?? "?") + " token maradt"
    }

    var usageFraction: Double {
        guard let used = usedTokens, plan.dailyTokens > 0 else { return 0 }
        return min(1, Double(used) / Double(plan.dailyTokens))
    }

    private init() {}

    /// Indításkor: termékek betöltése, tranzakciók figyelése, aktuális csomag.
    func start() {
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
            await refreshUsage()
        }
    }

    func loadProducts() async {
        do {
            let ids = CortexPlan.allCases.compactMap(\.productID)
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// A csomag a jelenleg érvényes tranzakciókból jön — nem UserDefaults-ból,
    /// hogy visszatérítésnél magától visszaálljon Free-re.
    func refreshEntitlement() async {
        var best: CortexPlan = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if t.revocationDate != nil { continue }
            let p = CortexPlan.allCases.first { $0.productID == t.productID }
            if let p, p.dailyTokens > best.dailyTokens { best = p }
        }
        plan = best
    }

    /// A szerveroldali keret leolvasása (a /api/v1/usage a fiók összes kulcsát számolja).
    func refreshUsage() async {
        guard let url = URL(string: "https://cortanime.eu/api/v1/usage"),
              let token = APIKeyVault.shared.currentKey else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let used = obj["used"] as? Int { usedTokens = used }
        if let calls = obj["calls_today"] as? Int { callsToday = calls }
        if let tierName = obj["tier"] as? String,
           let p = CortexPlan(rawValue: tierName), p.dailyTokens > plan.dailyTokens {
            plan = p
        }
    }

    /// Revolut: beváltókód aktiválása (a szerver emeli a tier-t, utána frissítünk).
    func redeem(code: String) async -> String? {
        guard let url = URL(string: "https://cortanime.eu/api/sub/redeem"),
              let key = APIKeyVault.shared.currentKey else { return "No API key set." }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code.trimmingCharacters(in: .whitespaces)])
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return "Network error." }
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if (resp as? HTTPURLResponse)?.statusCode == 200 {
            await refreshUsage()
            await refreshEntitlement()
            return nil // siker
        }
        return (obj["message"] as? String) ?? (obj["error"] as? [String: Any])?["message"] as? String ?? "This code is not valid."
    }

    static let revolutLink = "https://revolut.me/tibikegh12"

    func purchase(_ plan: CortexPlan) async {
        guard let id = plan.productID,
              let product = products.first(where: { $0.id == id }) else {
            purchaseError = "This plan is not available for purchase right now."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    await refreshEntitlement()
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "The purchase is awaiting approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}

// MARK: - API-kulcs tároló
//
// A kulcsot a WEBEN hozod létre (cortanime.eu/api-keys). Az app csak azt tárolja,
// amit ide bemásolsz — így a kulcs soha nem megy át az appon.

@MainActor
final class APIKeyVault: ObservableObject {
    static let shared = APIKeyVault()
    private let storageKey = "cortex.api.key"

    @Published private(set) var currentKey: String?

    private init() {
        // A kulcsot Keychainben tartjuk, nem UserDefaults-ban.
        currentKey = Keychain.read(storageKey)
    }

    func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("cx_"), trimmed.count > 12 else { return }
        Keychain.write(storageKey, trimmed)
        currentKey = trimmed
    }

    func clear() {
        Keychain.delete(storageKey)
        currentKey = nil
    }
}

enum Keychain {
    private static let service = "eu.cortanime.cortexai"

    static func write(_ account: String, _ value: String) {
        delete(account)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
