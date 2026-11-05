import SwiftUI

/// Cortex Void Canvas — the image studio.
///
/// The backend starts an async job (`POST /image`) and the app polls `GET /image/{id}`
/// until the CDN url appears. Nothing here names an upstream provider: the studio is
/// "Cortex Void Canvas" and that is all the UI ever says.
@MainActor
@Observable
final class CanvasState {
    enum Phase: Equatable {
        case idle
        case starting
        case rendering(seconds: Int)
        case done(String)
        case failed(String)
    }

    var prompt: String = ""
    var style: String = "auto"
    var phase: Phase = .idle
    var gallery: [String] = []          // newest first, CDN urls
    private var task: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .starting, .rendering: return true
        default: return false
        }
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    func generate() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        phase = .starting
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await CortexClient.shared.createImage(prompt: text, style: self.style)
                let started = Date()
                for _ in 0..<90 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(2.5))
                    let elapsed = Int(Date().timeIntervalSince(started))
                    self.phase = .rendering(seconds: elapsed)
                    let job = try await CortexClient.shared.imageStatus(id: id)
                    if job.status == "succeeded", let url = job.url {
                        self.gallery.insert(url, at: 0)
                        self.phase = .done(url)
                        return
                    }
                    if job.status == "failed" || job.status == "error" {
                        self.phase = .failed("The render failed. Try a different prompt.")
                        return
                    }
                }
                self.phase = .failed("This one is taking too long. Try again.")
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func reuse(_ url: String) {
        phase = .done(url)
    }
}

struct ImageStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = CanvasState()
    @FocusState private var promptFocused: Bool

    private let styles: [(id: String, label: String, symbol: String)] = [
        ("auto", "Auto", "sparkles"),
        ("anime", "Anime", "wand.and.stars"),
        ("cinema", "Mozi", "film"),
        ("icon", "Ikon", "app.dashed"),
        ("render", "3D", "cube.transparent"),
        ("sketch", "Vázlat", "pencil.and.outline"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    promptBox
                    styleRow
                    generateRow
                    preview
                    if !canvas.gallery.isEmpty { galleryStrip }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 16)
            }
            .background(AuroraBackground().ignoresSafeArea())
            .navigationTitle("Cortex Void Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kész") { dismiss() }
                        .foregroundStyle(Theme.violetSoft)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationBackground(Theme.ink)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kép a szavakból")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("Írd le, mi legyen a képen — a Cortex Void Canvas megfesti.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var promptBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Fekete háttér, lila fénygyűrű, izzó gömb…", text: $canvas.prompt, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .focused($promptFocused)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("image.prompt")
        }
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(styles, id: \.id) { style in
                    let on = canvas.style == style.id
                    Button {
                        canvas.style = style.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: style.symbol).font(.system(size: 11, weight: .bold))
                            Text(style.label).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.hairline, lineWidth: 1))
                        .foregroundStyle(on ? Color.white : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var generateRow: some View {
        HStack(spacing: 10) {
            Button {
                promptFocused = false
                canvas.generate()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: canvas.isBusy ? "hourglass" : "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                    Text(canvas.isBusy ? statusText : "Generálás")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canvas.canGenerate ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised), in: Capsule())
                .foregroundStyle(canvas.canGenerate ? Color.white : Theme.textFaint)
            }
            .buttonStyle(.plain)
            .disabled(!canvas.canGenerate)
            .accessibilityIdentifier("image.generate")

            if canvas.isBusy {
                Button {
                    canvas.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusText: String {
        switch canvas.phase {
        case .starting: return "Indítás…"
        case .rendering(let s): return "Festés… \(s) s"
        case .done: return "Kész"
        default: return "Generálás"
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch canvas.phase {
        case .done(let url):
            VStack(spacing: 10) {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder(text: "A kép nem tölthető be.", symbol: "exclamationmark.triangle")
                    default:
                        placeholder(text: "Betöltés…", symbol: "photo")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                HStack(spacing: 10) {
                    ShareLink(item: URL(string: url)!) {
                        Label("Megosztás", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            .foregroundStyle(Theme.text)
                    }
                    Button {
                        UIPasteboard.general.string = url
                    } label: {
                        Label("Link", systemImage: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            .foregroundStyle(Theme.text)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        case .failed(let message):
            placeholder(text: message, symbol: "exclamationmark.triangle")
        case .starting, .rendering:
            placeholder(text: "A Cortex Void Canvas dolgozik…", symbol: "sparkles")
        case .idle:
            placeholder(text: "Itt jelenik meg a kép.", symbol: "photo.on.rectangle.angled")
        }
    }

    private func placeholder(text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var galleryStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ebben a körben")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(canvas.gallery, id: \.self) { url in
                        Button { canvas.reuse(url) } label: {
                            AsyncImage(url: URL(string: url)) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Theme.surfaceRaised
                                }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
