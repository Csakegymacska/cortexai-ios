import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state
    @State private var daily: CortexClient.Daily?
    @FocusState private var composerFocused: Bool
    @State private var showJump = false
    @State private var lastAutoScroll = Date.distantPast
    /// Görgetéskor a keret-sáv összecsuklik, hogy a beszélgetésé legyen a hely.
    @State private var stripCollapsed = false
    @Environment(\.scenePhase) private var scenePhase

    private var conversation: Conversation? { state.activeConversation }

    /// A Shortcuts / Siri által otthagyott kérdés. Egyszer fut le, utána törlődik.
    private func drainPendingPrompt() {
        // Vezérlőközpontból: „Ma mi jön ki” — a napi kártya az üres képernyőn van,
        // ezért ha a beszélgetés nem üres, újat nyitunk.
        if UserDefaults.standard.bool(forKey: "cortex.openDaily") {
            UserDefaults.standard.removeObject(forKey: "cortex.openDaily")
            if let conversation, !conversation.messages.isEmpty { state.newConversation() }
        }
        guard let prompt = PendingPrompt.take() else { return }
        state.send(prompt)
    }

    private var headerSubtitle: String {
        let profile = conversation.map { state.profile(for: $0) } ?? state.defaultProfile
        let tier = CortexTier.named(conversation?.tier ?? state.settings.defaultTier)
        return profile.name + " · " + tier.label
    }

    /// A beszélgetés Markdownban: fejléc, időpontok, réteg és források is benne vannak,
    /// hogy a mentés önmagában is érthető legyen.
    private func exportText(_ conversation: Conversation) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "hu_HU")
        stamp.dateFormat = "yyyy. MM. dd. HH:mm"
        var out = "# \(conversation.title)\n\n_ Cortex AI · \(stamp.string(from: Date())) _\n"
        for message in conversation.messages {
            let who = message.role == .user ? "Te" : "Cortex"
            out += "\n## \(who)\n\n\(message.text)\n"
            if let step = message.steps, !step.isEmpty {
                out += "\n" + step.map { "- [\($0.ok ? "x" : " ")] \($0.label): \($0.detail) (\($0.ms) ms)" }.joined(separator: "\n") + "\n"
            }
            if let sources = message.sources, !sources.isEmpty {
                out += "\nSources:\n" + sources.map { "- \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    private var auraMode: AuraMode {
        state.isStreaming ? state.phase.aura : .idle
    }

    var body: some View {
        @Bindable var state = state
        ZStack {
            AmbientAura(mode: auraMode)
            VStack(spacing: 0) {
                header
                UsageStrip()
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, stripCollapsed ? 0 : 8)
                    .frame(height: stripCollapsed ? 0 : nil, alignment: .top)
                    .clipped()
                    .opacity(stripCollapsed ? 0 : 1)
                Divider().overlay(Theme.hairline)
                transcript
                if state.phase != .idle || state.researchMode || state.compareMode || state.agentMode || state.activeProject != nil {
                    HStack(spacing: 7) {
                        if state.phase != .idle { PhasePill(phase: state.phase) }
                        if state.researchMode { ModeChip(title: "Deep research", symbol: "binoculars") { state.researchMode = false } }
                        if state.compareMode { ModeChip(title: "Two voices", symbol: "rectangle.split.2x1") { state.compareMode = false } }
                        if state.agentMode { ModeChip(title: "Agent", symbol: "point.3.connected.trianglepath.dotted") { state.agentMode = false } }
                        if let project = state.activeProject { ModeChip(title: project.name, symbol: "square.stack.3d.up", tint: Color(hex: project.tintHex)) { } }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ComposerView(focused: $composerFocused) { text, images, files, research, wantsImage in
                    if wantsImage {
                        state.sendImage(text.isEmpty ? "A nice picture" : text)
                    } else if state.compareMode {
                        state.compare(text.isEmpty ? "Compare the options." : text)
                    } else {
                        state.send(text, images: images, files: files,
                                   research: research || state.researchMode,
                                   agent: state.agentMode)
                    }
                }
            }
            .animation(CortexMotion.snappy, value: state.phase)

            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.ink)
        .task { drainPendingPrompt() }
        .onOpenURL { url in
            guard url.scheme == "cortexai" else { return }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let question = items.first(where: { $0.name == "q" })?.value,
               !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.send(question)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { drainPendingPrompt() }
        }
        .sheet(item: $state.sheet) { sheet in
            sheetView(sheet)
        }
        .task {
            if daily == nil { daily = try? await CortexClient.shared.daily() }
        }
        .onAppear {
            // Új verzió első indítása: egyszer megmutatjuk, mi az új. Utána csendben marad.
            let seen = UserDefaults.standard.string(forKey: "cortex.seen.features")
            let current = Bundle.main.shortVersion
            if seen != current {
                UserDefaults.standard.set(current, forKey: "cortex.seen.features")
                state.sheet = .features
            }
        }
    }

    // MARK: Header

    // MARK: Sheets

    /// Egy helyen dől el, melyik lap jön be. A parancspaletta is ide ír, ezért
    /// nincs 10 külön sheet-modifier.
    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .library:
            LibraryView(onPick: { id in
                state.select(id)
                state.sheet = nil
            })
            .presentationBackground(Theme.ink)
        case .settings:
            SettingsView().presentationBackground(Theme.ink)
        case .profiles:
            ProfilesView().presentationBackground(Theme.ink)
        case .studio:
            ImageStudioView()
        case .features:
            FeaturesView().presentationBackground(Theme.ink)
        case .projects:
            ProjectsView().presentationBackground(Theme.ink)
        case .tasks:
            TasksView().presentationBackground(Theme.ink)
        case .knowledge:
            KnowledgeView().presentationBackground(Theme.ink)
        case .subscription:
            SubscriptionView().presentationBackground(Theme.ink)
        case .prompts:
            PromptsView { text in
                state.composerDraft = text
                state.sheet = nil
            }
            .presentationBackground(Theme.ink)
        case .export:
            ExportView().presentationBackground(Theme.ink)
        case .commands:
            CommandPalette().presentationBackground(Theme.ink)
        }
    }

    private var header: some View {
        // A fejléc üvegfelületei egy csoportban vannak: közel kerülve összeolvadnak,
        // és a rendszer egy menetben rajzolja őket — ez az iOS 26 ajánlott mintája.
        CortexGlassGroup(spacing: 10) {
            HStack(spacing: 12) {
            Button { state.sheet = .library } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .cortexGlass(Circle(), interactive: true)
            }
            .accessibilityLabel("Chats")
            .accessibilityIdentifier("chat.library")

            Button { state.sheet = .profiles } label: {
                HStack(spacing: 8) {
                    CortexMark(size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(conversation?.title ?? "Cortex AI")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(headerSubtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(LiquidPress())
            .accessibilityIdentifier("chat.profile")

            Spacer(minLength: 4)

            Menu {
                ForEach(CortexTier.all) { tier in
                    Button {
                        if let id = state.activeConversationID { state.setTier(tier.id, for: id) }
                    } label: {
                        Label(tier.label, systemImage: tier.symbol)
                    }
                }
            } label: {
                // Csak jelölő ikon: a hosszú modellnevek („Cortex Phantom" stb.)
                // soha nem törhetnek meg egy telefont, a név a menüben látszik.
                Image(systemName: CortexTier.named(conversation?.tier ?? "void").symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34)
                    .cortexGlass(Circle(), interactive: true)
            }
            .accessibilityIdentifier("chat.tier")

            Button {
                state.sheet = .commands
                Haptics.tap()
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, height: 34)
                    .cortexGlass(Circle(), interactive: true)
                    .foregroundStyle(Theme.text)
            }
            .buttonStyle(LiquidPress())
            .accessibilityLabel("Command palette")
            .accessibilityIdentifier("chat.commands")

            Menu {
                Button { state.sheet = .knowledge } label: { Label("Knowledge base", systemImage: "brain.head.profile") }
                Button { state.sheet = .projects } label: { Label("Projektek", systemImage: "square.stack.3d.up") }
                Button { state.sheet = .tasks } label: {
                    Label(state.tasks.isEmpty ? "Feladatok" : "Feladatok (\(state.tasks.count))", systemImage: "alarm")
                }
                Button {
                    state.agentMode.toggle()
                    Haptics.tap()
                } label: {
                    Label(state.agentMode ? "Agent mode on" : "Agent mode", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Button {
                    state.researchMode.toggle()
                    if state.researchMode { state.compareMode = false }
                } label: {
                    Label(state.researchMode ? "Deep research be" : "Deep research", systemImage: "binoculars")
                }
                Button {
                    state.compareMode.toggle()
                    if state.compareMode { state.researchMode = false }
                } label: {
                    Label(state.compareMode ? "Two voices be" : "Two voices", systemImage: "rectangle.split.2x1")
                }
                Divider()
                if let conversation, !conversation.messages.isEmpty {
                    ShareLink(item: exportText(conversation)) {
                        Label("Beszélgetés mentése (.md)", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    state.composerDraft = "kép: "
                } label: { Label("Generate image in chat", systemImage: "photo.badge.plus") }
                Button { state.sheet = .studio } label: { Label("Image studio (advanced)", systemImage: "wand.and.stars") }
                Button { state.sheet = .prompts } label: { Label("Saved prompts", systemImage: "text.book.closed") }
                Button { state.sheet = .settings } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                Button { state.sheet = .export } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button { state.sheet = .subscription } label: { Label("Subscription", systemImage: "creditcard") }
                Button { state.sheet = .features } label: { Label("What's new", systemImage: "sparkles") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34)
                    .cortexGlass(Circle(), interactive: true)
            }
            .accessibilityLabel("Tools")
            .accessibilityIdentifier("chat.canvas")

        }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let conversation, conversation.messages.isEmpty {
                        EmptyChatState(profile: state.profile(for: conversation),
                                       tier: CortexTier.named(conversation.tier)) { prompt in
                            state.send(prompt)
                        }
                        if let daily {
                            DailyCard(daily: daily) { prompt in state.send(prompt) }
                                .transition(.opacity)
                        }
                    }
                    QuotaBanner()
                    ForEach(Array((conversation?.messages ?? []).enumerated()), id: \.element.id) { index, message in
                        MessageRow(message: message, showTimestamp: state.settings.showTimestamps, index: index)
                            .id(message.id)
                    }
                    if let error = state.lastError {
                        ErrorRow(text: error) { state.retryLast() }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .cortexScrollEdge()
            .overlay(alignment: .bottomTrailing) { jumpButton(proxy) }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height) > 280
            } action: { _, far in
                withAnimation(CortexMotion.snappy) { showJump = far }
            }
            // A keret-sáv csak akkor tűnik el, ha már lefelé görgetett az ember:
            // a beszélgetés tetején mindig látszik.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 44
            } action: { _, past in
                guard past != stripCollapsed else { return }
                withAnimation(CortexMotion.gentle) { stripCollapsed = past }
            }
            .onChange(of: conversation?.messages.count ?? 0) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversation?.messages.last?.text ?? "") { _, _ in
                // Folyó válasznál a delta másodpercenként tucatszor jön. Csak akkor görgetünk,
                // ha a lap alján vagyunk, és legfeljebb 12-szer másodpercenként — különben
                // a görgetés maga lenne a lassulás oka hosszú beszélgetésben.
                guard !showJump else { return }
                let now = Date()
                guard now.timeIntervalSince(lastAutoScroll) > 0.08 else { return }
                lastAutoScroll = now
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Appears when the reader scrolls away from the live edge of the conversation.
    private func jumpButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(CortexMotion.gentle) { proxy.scrollTo("bottom", anchor: .bottom) }
            Haptics.tap()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(LiquidPress())
        .padding(.trailing, 18)
        .padding(.bottom, 12)
        .opacity(showJump ? 1 : 0)
        .scaleEffect(showJump ? 1 : 0.8)
        .allowsHitTesting(showJump)
        .accessibilityLabel("Jump to the newest message")
    }
}

// MARK: - Empty state

struct EmptyChatState: View {
    let profile: PersonaProfile
    let tier: CortexTier
    let onPrompt: (String) -> Void

    private let prompts = [
        "Explain in 5 sentences what Cortex Void can do.",
        "Write a SwiftUI card with a 3D tilt.",
        "Which 3 anime episodes are worth watching today?",
        "Help me plan my week."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                CortexMark(size: 54)
                Text(tier.label)
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.text)
                Text(tier.id == "phantom"
                     ? "Az OmegaTech és a CortexAnime csúcsmodellje. Három menetben gondolkodik, mielőtt válaszol — kód, matek, hosszú kérdés."
                     : "Az OmegaTech és a CortexAnime AI-ja. Kérdezz bármit — kód, ötletek, anime, tanulás.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                    Button { onPrompt(prompt) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.violetSoft)
                            Text(prompt)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(CortexPressStyle(scale: 0.98))
                    .cortexEntrance(index: index + 1)
                }
            }
            Spacer(minLength: 20)
        }
    }
}

// MARK: - Error row

struct ErrorRow: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: retry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.violetSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.danger.opacity(0.25), lineWidth: 1))
    }
}

/// Kis címke a beviteli sáv fölött: milyen módban megy a következő üzenet.
struct ModeChip: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.violetSoft
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(LiquidPress())
    }
}
