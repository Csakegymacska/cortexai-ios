import SwiftUI
import UIKit

/// The screen that says how someone else gets this app onto a phone.
/// Two ways, both honest: AltStore/SideStore signs with the user's own Apple ID,
/// or they download the IPA and sign it on a signer of their choosing.
struct InstallView: View {
    private let installPage = URL(string: "https://cortanime.eu/api/cortexai/app/install")!
    private let ipaURL = URL(string: "https://cortanime.eu/api/cortexai/app/ipa")!
    private let signerURL = URL(string: "https://applejr.net/#signer")!
    private let sourceURL = "https://cortanime.eu/api/cortexai/app/source.json"

    @State private var copied: String?
    @State private var showCopied = false

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.6)
            Form {
                Section {
                    header
                }

                Section {
                    Text(sourceURL)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(3)

                    Button {
                        copy(sourceURL, tag: "source")
                    } label: {
                        Label(copied == "source" ? "Source address copied" : "Copy the source address",
                              systemImage: copied == "source" ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(copied == "source" ? Theme.success : Theme.violetSoft)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        step(1, "Install AltStore or SideStore from their own sites.")
                        step(2, "In that app open Sources, paste the address and add it.")
                        step(3, "Open CortexAnime, tap Cortex AI, then Install.")
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("AltStore or SideStore")
                } footer: {
                    Text("Your phone signs the app with your own Apple ID — nothing is uploaded to us, and no certificate of ours is involved. A free Apple ID signs for seven days; AltStore refreshes it on the same Wi-Fi.")
                }

                Section {
                    Link(destination: ipaURL) {
                        Label("Download CortexAI-\(Bundle.main.shortVersion).ipa",
                              systemImage: "arrow.down.circle")
                            .foregroundStyle(Theme.violetSoft)
                    }
                    Link(destination: signerURL) {
                        Label("Sign it at applejr.net", systemImage: "signature")
                            .foregroundStyle(Theme.violetSoft)
                    }
                } header: {
                    Text("Sign it yourself")
                } footer: {
                    Text("Upload the file to the signer, sign with your own certificate, install the result. That step happens between you and the signer — the file is the same one everyone gets.")
                }

                Section {
                    ShareLink(item: installPage) {
                        Label("Share the install page", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Theme.violetSoft)
                    }
                    Link(destination: installPage) {
                        Label("Open the install page in a browser", systemImage: "safari")
                            .foregroundStyle(Theme.violetSoft)
                    }
                    Link(destination: URL(string: "https://github.com/dv7vdbjs8q-spec/cortex-anime")!) {
                        Label("GitHub — builds and notes", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Theme.violetSoft)
                    }
                } footer: {
                    Text("The application's source code is private and is not published anywhere. The build and this page are all that is distributed.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Get Cortex AI")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("Copied")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CortexMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex AI \(Bundle.main.shortVersion)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Build \(Bundle.main.buildNumber) · iOS 27 or newer · about 4 MB")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.vertical, 4)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.violetSoft)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ value: String, tag: String) {
        UIPasteboard.general.string = value
        copied = tag
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeIn(duration: 0.2)) { showCopied = false }
            copied = nil
        }
    }
}
