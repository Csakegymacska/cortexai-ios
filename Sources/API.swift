import Foundation
import SwiftUI

struct NativeUser: Identifiable, Codable, Equatable {
    var id: Int
    var username: String
    var email: String?
    var bio: String?
    var avatar: String?
    var decoration: String?
    var banner: String?
    var status: String?
    var accent: String?
    /// 1.0.1: a fiókhoz kötött kreditegyenleg (a szerver `users.credits` oszlopa).
    var credits: Int
    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? Int, let name = row["username"] as? String else { return nil }
        self.id = id; username = name; email = row["email"] as? String; bio = row["bio"] as? String
        avatar = row["avatar"] as? String; decoration = row["decoration"] as? String
        banner = row["banner"] as? String
        status = row["status"] as? String; accent = row["accent"] as? String
        credits = (row["credits"] as? Int) ?? Int(row["credits"] as? Double ?? 0)
    }
}

private struct SavedCookie: Codable {
    let name: String, value: String, domain: String, path: String
    let expires: Date?
    let secure: Bool
}

struct HTTPStatusFailure: LocalizedError {
    let status: Int
    var errorDescription: String? {
        [401: "Please sign in to continue.", 403: "This action is not permitted.", 429: "Too many requests. Please try again later.",
         500: "The server hit a problem. Retry in a moment.",
         502: "The server is restarting. Retry in a moment.",
         503: "The server is busy right now. Retry in a few seconds.",
         504: "The server timed out. Retry in a moment."][status]
            ?? "Server returned HTTP \(status)."
    }
}

@MainActor final class APIClient: ObservableObject {
    let base = URL(string: "https://cortanime.eu")!
    let session: URLSession
    @Published var user: NativeUser?
    @Published var accountError: String?
    @Published private(set) var metadataSource = "AniList"
    @Published private(set) var metadataUsingBackup = false
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var sessionValidated = false

    private var metadataRetryAt = Date.distantPast
    private var lastValidation: Date?
    private let validationInterval: TimeInterval = 300

    var signedIn: Bool { user != nil }
    var hasStoredSession: Bool { Vault.read(cookieKey) != nil }

    enum AuthState: Equatable {
        case unknown
        case signedOut
        case signingIn
        case signedIn(NativeUser)
        case sessionExpired
        case error(String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    private let cookieKey = "native-port.session.v1"

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = true; config.httpCookieAcceptPolicy = .always
        self.session = session ?? URLSession(configuration: config)
        if let saved = Vault.read(cookieKey), let data = saved.data(using: .utf8), let rows = try? JSONDecoder().decode([SavedCookie].self, from: data) {
            for row in rows where row.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == base.host {
                if let end = row.expires, end <= Date() { continue }
                var properties: [HTTPCookiePropertyKey: Any] = [.name: row.name, .value: row.value, .domain: row.domain, .path: row.path, .secure: row.secure ? "TRUE" : "FALSE"]
                if let end = row.expires { properties[.expires] = end }
                if let cookie = HTTPCookie(properties: properties) { HTTPCookieStorage.shared.setCookie(cookie) }
            }
            authState = .unknown
            Task { await validateSession() }
        } else {
            authState = .signedOut
        }
    }

    func validateSession() async {
        guard hasStoredSession else {
            authState = .signedOut; sessionValidated = false; return
        }
        let now = Date()
        if let last = lastValidation, now.timeIntervalSince(last) < validationInterval {
            sessionValidated = true; return
        }
        do {
            let row = try await json("/api/auth/me")
            if let userRow = row["user"] as? [String: Any], let account = NativeUser.init(userRow) {
                user = account; authState = .signedIn(account); sessionValidated = true
                CreditStore.shared.syncAccount(account.credits)
                lastValidation = now
                await refreshFavorites()
            } else {
                authState = .sessionExpired; sessionValidated = false
            }
        } catch let failure as HTTPStatusFailure {
            authState = (failure.status == 401 || failure.status == 403) ? .sessionExpired : .error(failure.localizedDescription)
            sessionValidated = false
        } catch {
            if !(error is CancellationError),!Task.isCancelled {
                authState = .error(error.localizedDescription)
                sessionValidated = false
            }
        }
    }

    func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"), var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw AppFailure.message("Invalid API path.") }
        parts.path = path; parts.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = parts.url, result.scheme == "https", result.host == base.host else { throw AppFailure.message("A secure API address is required.") }
        return result
    }

    func data(_ path: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        guard !Connectivity.shared.isOffline else { throw URLError(.notConnectedToInternet) }
        var request = URLRequest(url: try url(path, query: query)); request.httpMethod = method
        if path == "/api/home-live" || path == "/api/metadata/graphql" { request.timeoutInterval = 12 }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 7.4: a session-cookie MINDIG megy a kéréssel — a Vaultból, kézzel is.
        // Az iOS cookie-tárolója néma hibával eldobja; ettől a login „nem megy" állapotba esett.
        if let saved = Vault.read(cookieKey), let sdata = saved.data(using: .utf8),
           let rows = try? JSONDecoder().decode([SavedCookie].self, from: sdata) {
            let live = rows.filter { $0.expires == nil || $0.expires! > Date() }
            if !live.isEmpty {
                request.setValue(live.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.data(for: request)
        // 7.4: Set-Cookie a válaszból → azonnal a Vaultba (ne csak a rendszer cookie-tárolójába).
        if let http = response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { if let ks = k as? String, ks.lowercased() == "set-cookie" { headers[ks] = "\(v)" } }
            if !headers.isEmpty {
                let fresh = HTTPCookie.cookies(withResponseHeaderFields: headers, for: base)
                if !fresh.isEmpty { mergeCookies(fresh) }
            }
        }
        do { try Self.check(response) } catch {
            if let row = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let detail = row["error"] as? String { throw AppFailure.message(String(detail.prefix(200))) }
            throw error
        }
        return bytes
    }

    /// 7.4: a friss cookie-k beírása a Vaultba (a meglévők megtartásával).
    private func mergeCookies(_ fresh: [HTTPCookie]) {
        var rows: [SavedCookie] = []
        if let saved = Vault.read(cookieKey), let sdata = saved.data(using: .utf8),
           let old = try? JSONDecoder().decode([SavedCookie].self, from: sdata) { rows = old }
        for c in fresh {
            rows.removeAll { $0.name == c.name && $0.domain == c.domain }
            rows.append(SavedCookie(name: c.name, value: c.value, domain: c.domain, path: c.path, expires: c.expiresDate, secure: c.isSecure))
            HTTPCookieStorage.shared.setCookie(c)
        }
        if let data = try? JSONEncoder().encode(rows) { try? Vault.save(String(decoding: data, as: UTF8.self), key: cookieKey) }
    }

    func json(_ path: String, method: String = "GET", query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        let bytes = try await data(path, method: method, query: query, body: body)
        guard let row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw AppFailure.message("Unsupported server response.") }
        return row
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AppFailure.message("Invalid server response.") }
        guard (200..<300).contains(http.statusCode) else { throw HTTPStatusFailure(status: http.statusCode) }
    }

    func graph(_ query: String, variables: [String: Any] = [:]) async throws -> [String: Any] {
        guard !Connectivity.shared.isOffline else { throw URLError(.notConnectedToInternet) }
        try Task.checkCancellation()
        if Date() >= metadataRetryAt {
            do {
                var request = URLRequest(url: URL(string:"https://graphql.anilist.co")!)
                request.httpMethod = "POST"; request.timeoutInterval = 12
                request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.setValue("application/json",forHTTPHeaderField:"Accept")
                request.httpShouldHandleCookies = false
                request.httpBody = try JSONSerialization.data(withJSONObject:["query":query,"variables":variables])
                let (bytes,response) = try await session.data(for:request)
                let root = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
                if let http = response as? HTTPURLResponse,MetadataFeedPolicy.canFallback(status:http.statusCode) {
                    metadataRetryAt = Date().addingTimeInterval(60)
                } else {
                    if let errors = root?["errors"] as? [[String:Any]],let message = errors.first?["message"] as? String { throw AppFailure.message("AniList: " + String(message.prefix(200))) }
                    try Self.check(response)
                    guard let data = root?["data"] as? [String:Any] else { throw AppFailure.message("AniList metadata is temporarily unavailable.") }
                    metadataSource = "AniList";metadataUsingBackup = false
                    return data
                }
            } catch {
                guard !Task.isCancelled,Connectivity.isNetworkFailure(error) else { throw error }
                metadataRetryAt = Date().addingTimeInterval(60)
            }
        }
        try Task.checkCancellation()
        let root = try await json("/api/metadata/graphql",method:"POST",body:["query":query,"variables":variables])
        if let errors = root["errors"] as? [[String:Any]],let message = errors.first?["message"] as? String { throw AppFailure.message(String(message.prefix(200))) }
        guard let data = root["data"] as? [String:Any] else { throw AppFailure.message("Backup metadata is temporarily unavailable.") }
        let info = root["extensions"] as? [String:Any]
        let source = info?["metadataSource"] as? String ?? "Saved metadata"
        metadataSource = ["AniList","Kitsu","Saved catalog + Kitsu"].contains(source) ? source : "Saved metadata"
        metadataUsingBackup = info?["fallback"] as? Bool ?? true
        return data
    }

    /// Megvárja a mentett munkamenet érvényesítését, és megadja, hogy be vagyunk-e
    /// jelentkezve. A chat-képernyők ezzel elkerülik azt a versenyhelyzetet, hogy
    /// az érvényesítés befejezése előtt „kijelentkezett"-nek látják a felhasználót,
    /// és üresen maradnak (ez volt a „chat nem működik" hiba gyökere).
    func ensureSession() async -> Bool {
        if hasStoredSession, authState == .unknown { await validateSession() }
        return signedIn
    }

    func refreshAccount() async {
        do {
            let row = try await json("/api/auth/me")
            user = (row["user"] as? [String: Any]).flatMap(NativeUser.init)
            if let account = user { authState = .signedIn(account); accountError = nil; CreditStore.shared.syncAccount(account.credits) } else { authState = .signedOut; accountError = nil }
            await refreshFavorites()
        } catch {
            if !(error is CancellationError),!Task.isCancelled {
                user = nil
                if let failure = error as? HTTPStatusFailure, failure.status == 401 || failure.status == 403 {
                    authState = .sessionExpired
                    accountError = error.localizedDescription
                } else {
                    authState = .error(error.localizedDescription)
                    accountError = error.localizedDescription
                }
            }
        }
    }

    func login(email: String, password: String) async throws {
        authState = .signingIn
        do {
            let row = try await json("/api/auth/login", method: "POST", body: ["email":email,"password":password])
            guard let account = (row["user"] as? [String: Any]).flatMap(NativeUser.init) else { throw AppFailure.message("Sign-in did not return an account.") }
            user = account; authState = .signedIn(account); try? persistSession()
            CreditStore.shared.syncAccount(account.credits)
            await refreshFavorites()
        } catch {
            if !(error is CancellationError),!Task.isCancelled { authState = .error(error.localizedDescription) }
            throw error
        }
    }

    @discardableResult
    func register(username: String, email: String, password: String) async throws -> Bool {
        authState = .signingIn
        do {
            let row = try await json("/api/auth/register", method: "POST", body: ["username":username,"email":email,"password":password])
            if row["requireVerification"] as? Bool == true {
                authState = .signedOut
                return true
            }
            guard let account = (row["user"] as? [String: Any]).flatMap(NativeUser.init) else { throw AppFailure.message("Registration did not return an account.") }
            user = account; authState = .signedIn(account); try? persistSession()
            CreditStore.shared.syncAccount(account.credits)
            await refreshFavorites()
            return false
        } catch {
            if authState == .signingIn { authState = .error(error.localizedDescription) }
            throw error
        }
    }

    private func refreshFavorites() async {
        guard user != nil else { return }
        if let row = try? await json("/api/watchlist"),let items = row["items"] as? [[String:Any]] {
            AnimeLibrary.shared.mergeFavorites(Set(items.compactMap { $0["animeId"] as? Int }))
        }
    }

    func persistSession() throws {
        // 7.4: összefésülés — a rendszer tárolója és a válaszból elkapott cookie-k együtt élnek.
        let fromStore = (HTTPCookieStorage.shared.cookies(for: base) ?? []).map { SavedCookie(name:$0.name,value:$0.value,domain:$0.domain,path:$0.path,expires:$0.expiresDate,secure:$0.isSecure) }
        var rows = fromStore
        if let saved = Vault.read(cookieKey), let sdata = saved.data(using: .utf8),
           let old = try? JSONDecoder().decode([SavedCookie].self, from: sdata) {
            for row in old where !rows.contains(where: { $0.name == row.name && $0.domain == row.domain }) {
                if let end = row.expires, end <= Date() { continue }
                rows.append(row)
            }
        }
        try Vault.save(String(decoding: JSONEncoder().encode(rows), as: UTF8.self), key: cookieKey)
    }

    /// 1.0.1: egyszer használatos kredit-kód beváltása. A szerver ellenőrzi a kódot,
    /// a jogosultságot és a felhasználónkénti egyszeri felhasználást.
    struct RedeemResult { let amount: Int; let balance: Int }

    @discardableResult
    func redeemCreditCode(_ code: String) async throws -> RedeemResult {
        let row = try await json("/api/credits/redeem", method: "POST", body: ["code": code])
        let amount = (row["amount"] as? Int) ?? 0
        let balance = (row["balance"] as? Int) ?? 0
        return RedeemResult(amount: amount, balance: balance)
    }

    func logout() async throws {
        _ = try? await json("/api/auth/logout", method: "POST")
        for cookie in HTTPCookieStorage.shared.cookies(for: base) ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
        Vault.delete(cookieKey); user = nil; authState = .signedOut; sessionValidated = false
    }

    func clearSession() {
        user = nil; authState = .signedOut; sessionValidated = false
        Vault.delete(cookieKey)
    }
}
