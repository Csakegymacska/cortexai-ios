import Foundation

/// A widgetek adatforrása. Minden a nyilvános API-ról jön, a telefonról — nincs app group,
/// nincs megosztott konténer, nincs háttérfeladat. Ha a hálózat nem megy, a widget a
/// legutóbbi jó állapotot mutatja, és a következő frissítésnél újrapróbálja.
enum WidgetData {
    struct Health: Decodable {
        let ok: Bool?
        let model: String?
    }

    struct Sandbox: Decodable {
        let ok: Bool?
        let ready: Bool?
        let provider: String?
    }

    struct Ep: Decodable {
        let aid: Int?
        let ep: Int?
        let ts: Double?
        let title: String?
    }

    private struct EpFeed: Decodable {
        let ok: Bool?
        let items: [Ep]?
    }

    private static func get<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        guard let url = URL(string: path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("CortexAI-Widget/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    static func health() async -> Health? {
        await get("https://cortanime.eu/api/cortexai/health", as: Health.self)
    }

    static func sandbox() async -> Sandbox? {
        await get("https://cortanime.eu/api/cortexai/sandbox/status", as: Sandbox.self)
    }

    static func episodes() async -> [Ep] {
        let feed = await get("https://cortanime.eu/api/app/epfeed", as: EpFeed.self)
        return feed?.items ?? []
    }

    /// A következő adások, a legközelebbitől.
    static func upcoming(_ items: [Ep], limit: Int = 3, now: Date = Date()) -> [Ep] {
        items
            .filter { ($0.ts ?? 0) / 1000 > now.timeIntervalSince1970 - 6 * 3600 }
            .sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Formázás

enum WidgetFormat {
    // Számított tulajdonság: a DateFormatter nem küldhető át szálak között, így nem
    // lehet megosztott globális példány (Swift 6). Egy widgetben ez a költség jelentéktelen.
    static var hu: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = TimeZone(identifier: "Europe/Budapest")
        f.dateFormat = "MM. dd. HH:mm"
        return f
    }

    static var huShort: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = TimeZone(identifier: "Europe/Budapest")
        f.dateFormat = "HH:mm"
        return f
    }

    static func when(_ epochMilliseconds: Double?) -> String {
        guard let value = epochMilliseconds else { return "—" }
        let date = Date(timeIntervalSince1970: value / 1000)
        let calendar = Calendar(identifier: .gregorian)
        if calendar.isDateInToday(date) { return "ma " + huShort.string(from: date) }
        if calendar.isDateInTomorrow(date) { return "holnap " + huShort.string(from: date) }
        return hu.string(from: date)
    }

    static func countdown(_ epochMilliseconds: Double?) -> String {
        guard let value = epochMilliseconds else { return "" }
        let seconds = value / 1000 - Date().timeIntervalSince1970
        if seconds <= 0 { return "most" }
        if seconds < 3600 { return "\(Int(seconds / 60)) perc" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) óra" }
        return "\(Int(seconds / 86_400)) nap"
    }
}

// MARK: - Napi kérés

enum DailyPrompt {
    static let all: [String] = [
        "Magyarázd el 3 mondatban, mi az a DNS.",
        "Számold ki: mennyi 15% 4 800-ból, és mennyi marad?",
        "Írj Python kódot, ami kiírja az összes prímszámot 100-ig.",
        "Melyik a legjobb akció sorozat a kínálatban?",
        "Mennyi 24 perces részekkel 13 rész, órában?",
        "Fordítsd angolra: Kedvenc részem a negyedik.",
        "Mi a különbség a TCP és az UDP között?",
        "Oldd meg: 3x + 5 = 20.",
        "Mennyi 250 euró forintban, nagyságrendileg?",
        "Sorolj 3 okot, miért jó a Re:Zero."
    ]

    /// A nap sorszáma — minden nap ugyanaz, minden eszközön ugyanaz.
    static func today(_ date: Date = Date()) -> String {
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
        return all[day % all.count]
    }
}
