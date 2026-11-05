import SwiftUI
import UIKit

// MARK: - Beszélgetés exportálása
//
// Három formátum, mert három különböző dologra kell:
//   · Markdown  — jegyzetbe, Notionba, gitbe
//   · sima szöveg — e-mailbe, üzenetbe
//   · JSON      — ha valaki tovább akarja dolgozni
//
// A fájl a Documents könyvtárba kerül (Files appból elérhető), és a share sheet is
// felkínálja. A név beszélgetés-címből + dátumból áll, hogy ne ütközzenek.

struct ExportView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var format: Format = .markdown
    @State private var includeMeta = true
    @State private var includeErrors = false
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var savedName: String?

    enum Format: String, CaseIterable, Identifiable {
        case markdown, plain, json
        var id: String { rawValue }

        var label: String {
            switch self {
            case .markdown: return "Markdown"
            case .plain: return "Plain text"
            case .json: return "JSON"
            }
        }

        var blurb: String {
            switch self {
            case .markdown: return "Headings, layers, sources — for notes and docs."
            case .plain: return "Just the dialogue, one message after another."
            case .json: return "Every field, for scripts and backups."
            }
        }

        var symbol: String {
            switch self {
            case .markdown: return "text.alignleft"
            case .plain: return "doc.plaintext"
            case .json: return "curlybraces"
            }
        }

        var ext: String {
            switch self {
            case .markdown: return "md"
            case .plain: return "txt"
            case .json: return "json"
            }
        }
    }

    private var conversation: Conversation? { state.activeConversation }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let conversation {
                        previewCard(conversation)
                        formatPicker
                        options
                        actions
                        if let savedName {
                            Label("Saved to Files › Cortex AI › \(savedName)",
                                  systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.success)
                        }
                    } else {
                        Text("No conversation open.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(18)
            }
            .background(Theme.ink)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingShare) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
        }
        .presentationBackground(Theme.ink)
    }

    private func previewCard(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conversation.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            HStack(spacing: 12) {
                Label("\(conversation.messages.filter { $0.role == .user }.count) questions",
                      systemImage: "person")
                Label("\(estimatedBytes / 1024) kB", systemImage: "internaldrive")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .textCase(.uppercase)
            ForEach(Format.allCases) { f in
                Button {
                    format = f
                    Haptics.tap()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: f.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(format == f ? Theme.ink : Theme.textMuted)
                            .frame(width: 32, height: 32)
                            .background(
                                format == f ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(f.blurb)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textFaint)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if format == f {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.violetSoft)
                        }
                    }
                    .padding(11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .strokeBorder(format == f ? Theme.violet.opacity(0.4) : Theme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $includeMeta) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Layers and timings")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("Which engine answered, how long it took.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .tint(Theme.violet)
            .padding(13)

            if state.lastError != nil {
                Divider().overlay(Theme.hairline)
                Toggle(isOn: $includeErrors) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Include the last error")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("Useful when reporting a bug.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .tint(Theme.violet)
                .padding(13)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                save()
            } label: {
                Label("Save to Files", systemImage: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                if let url = write() {
                    shareURL = url
                    showingShare = true
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .foregroundStyle(Theme.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
    }

    // MARK: - Írás

    private var estimatedBytes: Int {
        guard let conversation else { return 0 }
        return conversation.messages.reduce(0) { $0 + $1.text.count } * 2 / 3
    }

    private func fileName() -> String {
        let raw = conversation?.title ?? "cortex-chat"
        let safe = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(60)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(safe)-\(df.string(from: Date())).\(format.ext)"
    }

    private func text() -> String {
        guard let conversation else { return "" }
        let stamp = ISO8601DateFormatter()

        switch format {
        case .markdown:
            var out = "# \(conversation.title)\n\n"
            if includeMeta {
                out += "_Exported \(stamp.string(from: Date())) · Cortex AI \(Bundle.main.shortVersion)_\n\n"
            }
            for message in conversation.messages {
                let who = message.role == .user ? "You" : "Cortex"
                out += "## \(who)\n\n\(message.text)\n\n"
                if includeMeta, let layer = message.layer, !layer.isEmpty {
                    out += "`layer: \(layer)`\n\n"
                }
                if includeMeta, let sources = message.sources, !sources.isEmpty {
                    out += "Sources:\n" + sources.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
                }
                out += "---\n\n"
            }
            if includeErrors, let error = state.lastError {
                out += "> Last error: \(error)\n"
            }
            return out

        case .plain:
            var out = conversation.title + "\n" + String(repeating: "=", count: conversation.title.count) + "\n\n"
            for message in conversation.messages {
                out += (message.role == .user ? "YOU: " : "CORTEX: ") + message.text + "\n\n"
            }
            return out

        case .json:
            let payload: [String: Any] = [
                "title": conversation.title,
                "exported_at": stamp.string(from: Date()),
                "app_version": Bundle.main.shortVersion,
                "tier": conversation.tier,
                "messages": conversation.messages.map { message -> [String: Any] in
                    var row: [String: Any] = [
                        "role": message.role.rawValue,
                        "text": message.text,
                        "at": stamp.string(from: message.createdAt),
                    ]
                    if let layer = message.layer { row["layer"] = layer }
                    if let sources = message.sources, !sources.isEmpty { row["sources"] = sources }
                    return row
                },
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload,
                                                    options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func write() -> URL? {
        let name = fileName()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(name)
        do {
            try text().data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            state.flash("Could not write the file.")
            return nil
        }
    }

    private func save() {
        if let url = write() {
            savedName = url.lastPathComponent
            Haptics.success()
            state.flash("Exported \(url.lastPathComponent)")
        }
    }
}

// MARK: - Share sheet

/// Az UIKit megosztó lapja. A SwiftUI `ShareLink` fájl-URL-lel is megy, de ez
/// a hívás minden iOS-verzión ugyanúgy viselkedik.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
