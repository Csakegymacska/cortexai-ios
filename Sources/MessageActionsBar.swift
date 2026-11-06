import SwiftUI
import UIKit

/// The row under a finished reply: copy, regenerate, share, branch. It only appears once
/// the stream has ended — while text is still arriving, the only useful control is Stop.
struct MessageActionsBar: View {
    let message: ChatMessage
    @Environment(AppState.self) private var state
    @State private var copied = false
    @State private var showCanvas = false

    private var isReading: Bool { SpeechEngine.shared.speakingID == message.id }

    var body: some View {
        HStack(spacing: 4) {
            iconButton("doc.on.doc", label: "Copy") {
                UIPasteboard.general.string = message.text
                Haptics.success()
                withAnimation(CortexMotion.snappy) { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    withAnimation(CortexMotion.fade) { copied = false }
                }
            }

            iconButton(isReading ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       label: isReading ? "Stop reading" : "Read aloud") {
                SpeechEngine.shared.toggle(message)
            }
            .foregroundStyle(isReading ? Theme.violetSoft : Theme.textFaint)

            iconButton("arrow.clockwise", label: "Regenerate") {
                state.regenerate()
            }

            ShareLink(item: message.text) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textFaint)
            .accessibilityLabel("Share")

            iconButton("rectangle.expand.vertical", label: "Canvas") {
                showCanvas = true
            }

            iconButton("link", label: "Share with link") {
                state.shareLink(for: message)
            }

            iconButton("arrow.triangle.branch", label: "Branch from here") {
                state.branch(from: message.id)
            }

            if copied {
                Text("Copied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .sheet(isPresented: $showCanvas) {
            CanvasSheet(text: message.text)
                .presentationBackground(Theme.ink)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textFaint)
        .accessibilityLabel(label)
    }
}
