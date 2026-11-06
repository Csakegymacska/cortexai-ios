import Foundation

/// App version helpers — `Bundle.main.shortVersion` / `Bundle.main.buildNumber`.
extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}
