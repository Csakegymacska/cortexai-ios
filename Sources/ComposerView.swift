import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Floating composer: a glass capsule with a gradient hairline, a growing text field,
/// live voice input and a send button that morphs into stop while Cortex is answering.
/// A PhotosPicker címkéje: olvasáskor pörgő, egyébként a kamera-ikon.
private struct PhotoScanLabel: View {
    var busy: Bool
    var body: some View {
        Group {
            if busy {
                ProgressView().controlSize(.mini).tint(Theme.textMuted)
            } else {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(width: 34, height: 34)
        .background { Circle().fill(Theme.surfaceRaised) }
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct ComposerView: View {
    @Environment(AppState.self) private var state
    @StateObject private var dictation = Dictation()
    var focused: FocusState<Bool>.Binding
    let onSend: (String, [ChatImage], [ChatFile], Bool, Bool) -> Void

    /// Egy kiválasztott kép: a bélyegkép a felülethez, a payload a motornak.
    private struct Picked: Identifiable {
        let id = UUID()
        let preview: UIImage
        let payload: ChatImage
    }

    @State private var draft = ""
    @State private var voiceBase = ""
    @State private var sendPulse = false
    @State private var pickedImage: PhotosPickerItem?
    @State private var scanning = false
    @State private var attachments: [Picked] = []
    @State private var documents: [ChatFile] = []
    @State private var importingDocument = false
    @State private var researchMode = false
    @State private var pickPrompt = false
    @State private var imageMode = false

    private var canSend: Bool {
        (!trimmed.isEmpty || !attachments.isEmpty || !documents.isEmpty) && !state.isStreaming
    }

    private var trimmed: String {
        (dictation.isRecording ? voiceBase + dictation.transcript : draft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A parancspalettából vagy a mentett utasításokból jött szöveg. Nem küldi el
    /// magától: bekerül a szerkesztőbe, hogy még lehessen rajta igazítani.
    private func takeDraft(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = draft.isEmpty ? trimmed : draft + "\n\n" + trimmed
        focused.wrappedValue = true
    }

    var body: some View {
        VStack(spacing: 8) {
            if imageMode {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Image generation — Cortex Void Canvas")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(CortexMotion.snappy) { imageMode = false }
                        Haptics.tap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(LiquidPress())
                    .accessibilityLabel("Turn image mode off")
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !attachments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(attachments) { item in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: item.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button {
                                attachments.removeAll { $0.id == item.id }
                                Haptics.tap()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.7))
                            }
                            .buttonStyle(LiquidPress())
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Remove image")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !documents.isEmpty {
                HStack(spacing: 8) {
                    ForEach(documents) { doc in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.cyan)
                            Text(doc.name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                            Button {
                                documents.removeAll { $0.id == doc.id }
                                Haptics.tap()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .buttonStyle(LiquidPress())
                            .accessibilityLabel("Remove document")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let error = dictation.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "mic.slash.fill").font(.system(size: 10, weight: .bold))
                    Text(error).font(.system(size: 11))
                }
                .foregroundStyle(Theme.danger)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 8) {
                if dictation.isRecording {
                    VoiceWaveform(level: dictation.level, active: true)
                        .transition(.scale.combined(with: .opacity))

                    Text(dictation.transcript.isEmpty ? "Listening…" : dictation.transcript)
                        .font(Theme.body(16))
                        .foregroundStyle(dictation.transcript.isEmpty ? Theme.textFaint : Theme.text)
                        .lineLimit(1...6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    TextField("Ask Cortex Void…", text: $draft, axis: .vertical)
                        .focused(focused)
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.text)
                        .tint(Theme.violetSoft)
                        .lineLimit(1...6)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("chat.input")
                        .transition(.opacity)
                }

                // Kevesebb gomb, több hely: minden ritkább eszköz a „+" menüben,
                // a sorban csak a menü, a képolvasás, a mikrofon és a küldés marad.
                Menu {
                    Button { pickPrompt = true; Haptics.tap() } label: {
                        Label("Saved prompts", systemImage: "text.book.closed")
                    }
                    Button { importingDocument = true; Haptics.tap() } label: {
                        Label("Attach document", systemImage: "doc.badge.plus")
                    }
                    Button {
                        imageMode.toggle()
                        if state.settings.hapticsEnabled { Haptics.tap() }
                    } label: {
                        Label(imageMode ? "Image generation on" : "Image generation",
                              systemImage: imageMode ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled")
                    }
                    Button {
                        researchMode.toggle()
                        if state.settings.hapticsEnabled { Haptics.tap() }
                    } label: {
                        Label(researchMode ? "Deep research on" : "Deep research",
                              systemImage: researchMode ? "binoculars.fill" : "binoculars")
                    }
                    Button {
                        state.agentMode.toggle()
                        if state.settings.hapticsEnabled { Haptics.tap() }
                    } label: {
                        Label(state.agentMode ? "Agent mode on" : "Agent mode",
                              systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(imageMode ? Theme.ink : Theme.textMuted)
                        .frame(width: 31, height: 31)
                        .background {
                            Circle().fill(imageMode ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised))
                        }
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(LiquidPress())
                .accessibilityLabel("Tools")
                .accessibilityIdentifier("chat.tools")

                // A PhotosPicker címkéje @Sendable zárójel, ezért @State-et nem olvashat.
                // Az értéket előtte kimentjük, a címke kész Boolt kap.
                let scanBusy = scanning
                PhotosPicker(selection: $pickedImage, matching: .images, photoLibrary: .shared()) {
                    PhotoScanLabel(busy: scanBusy)
                }
                .buttonStyle(LiquidPress())
                .disabled(scanning)
                .accessibilityLabel("Read text from a photo")
                .accessibilityIdentifier("chat.photo")

                Button(action: toggleDictation) {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(dictation.isRecording ? Theme.ink : Theme.textMuted)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(dictation.isRecording ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised))
                        }
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                        .scaleEffect(dictation.isRecording ? 1.06 : 1)
                        .animation(CortexMotion.bouncy, value: dictation.isRecording)
                }
                .buttonStyle(LiquidPress())
                .accessibilityLabel(dictation.isRecording ? "Stop voice input" : "Voice input")
                .accessibilityIdentifier("chat.mic")

                Button(action: submit) {
                    Image(systemName: state.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(state.isStreaming ? Theme.text : (canSend ? .white : Theme.textFaint))
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(state.isStreaming ? AnyShapeStyle(Theme.surfaceRaised) : (canSend ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised)))
                        }
                        .overlay(Circle().strokeBorder(canSend ? Color.white.opacity(0.22) : Theme.hairline, lineWidth: 1))
                        .shadow(color: canSend ? Theme.violet.opacity(0.55) : .clear, radius: sendPulse ? 14 : 6, y: 2)
                        .rotationEffect(.degrees(state.isStreaming ? 0 : (canSend ? 0 : -8)))
                        .scaleEffect(sendPulse && canSend ? 1.04 : 1)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(CortexMotion.bouncy, value: canSend)
                        .animation(CortexMotion.bouncy, value: state.isStreaming)
                }
                .buttonStyle(LiquidPress())
                .disabled(!canSend && !state.isStreaming)
                .accessibilityLabel(state.isStreaming ? "Stop" : "Send")
                .accessibilityIdentifier("chat.send")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            // iOS 26: valódi üveg — a beszélgetés átszűrődik alatta. A tint a márka
            // ibolyája, és amikor küldhető a szöveg, kicsit erősebb, hogy a composer
            // „felébredjen". Korábbi rendszeren ugyanez anyag + tömör háttér.
            .cortexGlass(
                RoundedRectangle(cornerRadius: 24, style: .continuous),
                tint: (canSend || dictation.isRecording) ? Theme.violet.opacity(0.22) : nil,
                interactive: true
            )
            .gradientBorder(radius: 24, width: 1, opacity: canSend || dictation.isRecording ? 0.85 : 0.25)
            .shadow(color: (canSend ? Theme.violet : Theme.cyan).opacity(0.22), radius: 22, y: 8)
            .animation(CortexMotion.gentle, value: dictation.isRecording)

            HStack(spacing: 6) {
                if state.isStreaming {
                    PhaseDots()
                }
                Text(footer)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
                    .contentTransition(.opacity)
            }
            .animation(CortexMotion.fade, value: footer)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.92), Theme.ink], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .onAppear { sendPulse = true }
        .onChange(of: state.composerDraft) { _, new in
            guard let new else { return }
            takeDraft(new)
            state.composerDraft = nil
        }
        .sheet(isPresented: $pickPrompt) {
            PromptsView { text in takeDraft(text) }
                .presentationBackground(Theme.ink)
        }
        .fileImporter(
            isPresented: $importingDocument,
            allowedContentTypes: [.pdf, .plainText, .commaSeparatedText, .json, .rtf, .html],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            // A kiolvasás a készüléken, a fő szálon történik: 40 oldal alatt ez
            // bőven 100 ms, és így nincs szálak közötti átadás.
            if let text = DocIngest.text(from: url), !text.isEmpty, documents.count < 4 {
                documents.append(ChatFile(name: url.lastPathComponent, text: String(text.prefix(24_000))))
                Haptics.success()
            } else {
                state.lastError = "Could not read this file. Try PDF, TXT, MD or CSV."
            }
        }
        .onChange(of: pickedImage) { _, item in
            guard let item else { return }
            scanning = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                var preview: UIImage?
                var payload: ChatImage?
                if let data, let image = UIImage(data: data) {
                    preview = image
                    payload = Self.package(image)
                }
                // A kép megy a motornak, és közben a szövegét is kiolvassuk — így
                // kereshető, másolható lesz, és a modell szöveges kérdésre is válaszol.
                let scanned = if let data { await ImageText.recognize(in: data) } else { "" }
                let clean = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    if let preview, let payload, attachments.count < 3 {
                        attachments.append(Picked(preview: preview, payload: payload))
                        Haptics.success()
                    }
                    if !clean.isEmpty, draft.isEmpty {
                        draft = String(clean.prefix(600))
                    }
                    scanning = false
                    pickedImage = nil
                }
            }
        }
        .onChange(of: dictation.isRecording) { _, recording in
            if !recording, !dictation.transcript.isEmpty {
                let addition = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = voiceBase.isEmpty ? addition : voiceBase + " " + addition
                dictation.reset()
            }
        }
    }

    private var footer: String {
        if dictation.isRecording { return "Listening — tap the microphone to stop." }
        if state.isStreaming {
            return researchMode ? "Cortex is researching — sources are on the way." : "Cortex is answering — tap stop to interrupt."
        }
        if researchMode { return "Deep research — answer comes with numbered sources." }
        return "Cortex AI · OmegaTech × CortexAnime"
    }

    /// A kiválasztott képet a motor méretére hozza: legfeljebb 1280 px, JPEG 0.72.
    /// Egy 12 MP-es fotó így ~200–400 KB lesz, nem 4 MB — gyorsabban megy fel.
    private static func package(_ image: UIImage) -> ChatImage? {
        let maxSide: CGFloat = 1280
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let data = resized.jpegData(compressionQuality: 0.72) else { return nil }
        return ChatImage(mime: "image/jpeg", data: data.base64EncodedString())
    }

    private func toggleDictation() {
        if !dictation.isRecording { voiceBase = draft }
        dictation.toggle()
    }

    private func submit() {
        if state.isStreaming {
            state.stop()
            return
        }
        guard canSend else { return }
        let text = trimmed
        let outgoing = attachments.map(\.payload)
        let attachedDocs = documents
        let research = researchMode
        // Kép-mód: a kapcsoló mellett a szöveg is kiválthatja („kép: …",
        // „generálj egy képet …", „rajzolj …").
        let lower = text.lowercased()
        let autoImage = !imageMode && (
            lower.hasPrefix("kép:") || lower.hasPrefix("kep:") ||
            (lower.contains("kép") && (lower.contains("generál") || lower.contains("rajzol"))) ||
            lower.hasPrefix("image:") || lower.hasPrefix("draw ") ||
            lower.contains("generate an image") || lower.contains("make an image") ||
            lower.contains("draw me") || lower.contains("picture of") ||
            (lower.contains("image") && lower.contains("generat")) ||
            lower.contains("draw me"))
        let wantsImage = imageMode || autoImage
        if dictation.isRecording { dictation.stop() }
        dictation.reset()
        draft = ""
        voiceBase = ""
        focused.wrappedValue = false
        attachments = []
        documents = []
        if state.settings.hapticsEnabled { Haptics.tap() }
        onSend(text, outgoing, attachedDocs, research, wantsImage)
    }
}

/// Dokumentum → szöveg. A PDF-et a PDFKit olvassa (nincs külső szolgáltatás), a
/// többit a rendszer kódoláskezelése. Minden a készüléken történik.
enum DocIngest {
    static func text(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for index in 0..<min(doc.pageCount, 40) {
                if let page = doc.page(at: index), let body = page.string {
                    out += body + "\n"
                }
                if out.count > 24_000 { break }
            }
            let clean = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }

        if let data = try? Data(contentsOf: url) {
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let latin = String(data: data, encoding: .isoLatin2) {
                return latin.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
