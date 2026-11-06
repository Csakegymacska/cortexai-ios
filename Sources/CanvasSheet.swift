import SwiftUI
import UIKit

/// Canvas: a hosszú válasz külön lapon, szerkeszthetően. Nem másolás — itt át is
/// lehet írni, és onnan mehet tovább megosztásba vagy jegyzetbe.
struct CanvasSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var copied = false

    init(text: String) {
        _text = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .padding(Theme.gutter)
                .background(Theme.ink)
                .navigationTitle("Canvas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            UIPasteboard.general.string = text
                            Haptics.success()
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                            Button("Done") { dismiss() }
                        }
                    }
                }
        }
    }
}
