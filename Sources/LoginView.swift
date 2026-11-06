import SwiftUI

/// Sign in / Create account — Apple-style auth sheet.
/// Talks to the CortexAnime account backend; the session cookie is kept
/// by the system, so the rest of the app is signed in automatically.
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var account = AccountStore.shared

    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Create Account"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(intensity: 0.7)
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.violetSoft)
                            Text("Your Cortex account")
                                .font(.system(size: 22, weight: .bold))
                            Text("Sign in to sync your subscription, API keys and AI profile.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textFaint)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)

                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 12) {
                            if mode == .signUp {
                                field("Username", text: $username, symbol: "person")
                            }
                            field("Email", text: $email, symbol: "envelope", keyboard: .emailAddress)
                            field("Password", text: $password, symbol: "lock", secure: true)
                        }

                        if let err = account.lastError {
                            Text(err)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task {
                                let ok = mode == .signIn
                                    ? await account.login(email: email, password: password)
                                    : await account.register(username: username, email: email, password: password)
                                if ok { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if account.busy { ProgressView().tint(.white) }
                                Text(mode == .signIn ? "Sign In" : "Create Account")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? Theme.violet : Theme.violet.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .disabled(!canSubmit || account.busy)

                        Text("By continuing you agree that conversations stay on this device and only account data is stored on the server.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textFaint)
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                }
            }
            .navigationTitle(mode == .signIn ? "Sign In" : "Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.tint(Theme.violetSoft)
                }
            }
        }
    }

    private var canSubmit: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passOK = password.count >= 6
        return emailOK && passOK && (mode == .signIn || username.trimmingCharacters(in: .whitespaces).count >= 3)
    }

    private func field(_ title: String, text: Binding<String>, symbol: String,
                       keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Theme.textFaint)
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled()
            }
        }
        .padding(13)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
    }
}
