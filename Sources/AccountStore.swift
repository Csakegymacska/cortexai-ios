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

    private init() {}

    /// Checks whether a session is still valid (called at launch).
    func refresh() async {
        guard let req = request("/me") else { return }
        if let (data, resp) = try? await session.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let u = obj["user"] as? [String: Any],
               let d = try? JSONSerialization.data(withJSONObject: u) {
                user = try? JSONDecoder().decode(AccountUser.self, from: d)
            }
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
                if let data = try? JSONSerialization.data(withJSONObject: u) {
                    user = try? JSONDecoder().decode(AccountUser.self, from: data)
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
