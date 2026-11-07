import Foundation

/// Account — sign in / register against the CortexAnime backend
/// (`/api/auth/register`, `/api/auth/login`, `/api/auth/me`, `/api/auth/logout`).
/// The session cookie (`cx_session`) is stored by the shared HTTPCookieStorage,
/// so every later call is authenticated automatically.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    struct AccountUser: Codable, Hashable {
        var id: Int?
        var username: String?
        var email: String?
        var avatar: String?
        var credits: Double?
    }

    @Published private(set) var user: AccountUser?
    @Published private(set) var busy = false
    @Published var lastError: String?

    var isLoggedIn: Bool { user != nil }
    var displayName: String { user?.username ?? "Guest" }

    private static let base = "https://cortanime.eu/api/auth"
    private let session: URLSession = .shared

    private static let sessionKey = "cx.session"
    private static let userKey = "cx.user.snapshot"

    private init() {
        // A mentett munkamenet visszatöltése induláskor — ettől marad bejelentkezve.
        if let snap = UserDefaults.standard.data(forKey: Self.userKey),
           let u = try? JSONDecoder().decode(AccountUser.self, from: snap) {
            user = u
        }
        let saved = Keychain.read(Self.sessionKey)
        if !saved.isEmpty {
            let cookie = HTTPCookie(properties: [
                .domain: "cortanime.eu", .path: "/",
                .name: "cx_session", .value: saved,
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(7 * 86400),
            ])
            if let cookie { HTTPCookieStorage.shared.setCookie(cookie) }
        }
    }

    /// Launch call: restores the session and validates it against the server.
    func start() async {
        if !Keychain.read(Self.sessionKey).isEmpty || user != nil {
            await refresh()
        }
    }

    private func persist() {
        if let u = user, let data = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userKey)
        }
    }

    /// Checks whether a session is still valid (called at launch).
    func refresh() async {
        guard let req = request("/me") else { return }
        if let (data, resp) = try? await session.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let u = obj["user"] as? [String: Any] {
                if let d = try? JSONSerialization.data(withJSONObject: u),
                   let decoded = try? JSONDecoder().decode(AccountUser.self, from: d) {
                    user = decoded
                } else {
                    user = AccountUser(id: u["id"] as? Int, username: u["username"] as? String,
                                       email: u["email"] as? String, avatar: u["avatar"] as? String,
                                       credits: (u["credits"] as? Double) ?? (u["credits"] as? Int).map(Double.init))
                }
                persist()
                return
            }
        }
        // A munkamenet már nem érvényes — tiszta állapot.
        if user != nil {
            user = nil
            persist()
        }
    }

    func login(email: String, password: String) async -> Bool {
        await auth("/login", body: ["email": email, "password": password])
    }

    func register(username: String, email: String, password: String) async -> Bool {
        await auth("/register", body: ["username": username, "email": email, "password": password])
    }

    func logout() async {
        _ = try? await session.data(for: {
            var r = request("/logout")!
            r.httpMethod = "POST"
            return r
        }())
        user = nil
        persist()
        Keychain.delete(Self.sessionKey)
        for c in HTTPCookieStorage.shared.cookies(for: URL(string: "https://cortanime.eu")!) ?? []
        where c.name == "cx_session" {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }

    /// Profilkép feltöltése (base64 a szervernek, ami tárolja és kiszolgálja).
    func uploadAvatar(_ data: Data) async -> String? {
        guard var req = request("/me/avatar") else { return "Hiba." }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["image": data.base64EncodedString()])
        do {
            let (respData, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                var u = user
                u?.avatar = "/api/me/avatar"
                user = u
                persist()
                return nil
            }
            let obj = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? [:]
            return (obj["message"] as? String) ?? "A feltöltés nem sikerült (\(code))."
        } catch {
            return "Network error."
        }
    }

    /// A profilkép letöltése megjelenítéshez.
    func fetchAvatar() async -> Data? {
        guard let req = request("/me/avatar") else { return nil }
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func auth(_ path: String, body: [String: String]) async -> Bool {
        busy = true
        defer { busy = false }
        lastError = nil
        guard var req = request(path) else { return false }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if (200..<300).contains(code), let u = obj["user"] as? [String: Any] {
                if let data = try? JSONSerialization.data(withJSONObject: u),
                   let decoded = try? JSONDecoder().decode(AccountUser.self, from: data) {
                    user = decoded
                } else {
                    // 7.4: a dekóder soha ne hallgasson el — kézi kivétel tartaléknak.
                    user = AccountUser(id: u["id"] as? Int, username: u["username"] as? String,
                                       email: u["email"] as? String, avatar: u["avatar"] as? String,
                                       credits: (u["credits"] as? Double) ?? (u["credits"] as? Int).map(Double.init))
                }
                if user == nil {
                    lastError = "Sign-in succeeded but the account could not be read."
                    return false
                }
                persist()
                // A bejelentkezési cookie mentése — ettől marad meg a munkamenet.
                if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://cortanime.eu")!) {
                    for c in cookies where c.name == "cx_session" {
                        Keychain.write(Self.sessionKey, c.value)
                    }
                }
                return true
            }
            lastError = (obj["error"] as? String) ?? (obj["message"] as? String) ?? "Sign-in failed (\(code))."
            return false
        } catch {
            lastError = "Network error."
            return false
        }
    }

    private func request(_ path: String) -> URLRequest? {
        guard let url = URL(string: Self.base + path) else { return nil }
        var r = URLRequest(url: url)
        r.setValue("CortexApp/7.3", forHTTPHeaderField: "User-Agent")
        return r
    }
}
