import Foundation
import Observation
import SwiftUI
import UIKit

/// Single source of truth: conversations, profiles, settings and the live streaming task.
@Observable
@MainActor
final class AppState {
    var conversations: [Conversation] = []
    var profiles: [PersonaProfile] = PersonaProfile.builtIns
    var settings: CortexSettings = .default
    /// Facts the app keeps about the user. Sent with every request so the model
    /// never has to "remember" them on its own.
    var memories: [MemoryNote] = []
    /// Projektek: saját utasítás és tudás, a beszélgetésektől függetlenül.
    var projects: [Project] = []
    var tasks: [ScheduledTask] = []
    /// Ügynök mód: a következő kérés eszközöket is használ.
    var agentMode = false
    var activeProjectID: UUID?
    /// Rövid visszajelzés a felületnek („link kimásolva”).
    var toast: String?
    /// A következő üzenet módja. Nem mentődik: kikapcsolásig marad.
    var researchMode = false
    var compareMode = false

    /// Melyik lap van nyitva. Egy helyen van a sor, nem nyolc külön @State-ben:
    /// így a parancspalettából is bármelyik lap megnyitható.
    var sheet: AppSheet?

    /// Ide írja a parancspaletta / a mentett utasítás a szöveget, a composer innen veszi át.
    var composerDraft: String?

    var activeConversationID: UUID?
    var isStreaming = false
    /// What the assistant is doing while a reply is on its way: used by the phase pill
    /// above the composer and by the ambient background.
    var phase: CortexPhase = .idle
    var lastError: String?

    /// Set once the user finishes onboarding.
    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Self.onboardKey) }
    }

    private var streamTask: Task<Void, Never>?
    private static let onboardKey = "cortex.onboarded.v1"
    private let storeDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var storeURL: URL { storeDir.appendingPathComponent("cortex-ai-store.json") }
    private var backupURL: URL { storeDir.appendingPathComponent("cortex-ai-store.backup.json") }
    private var lastDeltaSave = Date.distantPast
    private var backupWrites = 0

    init() {
        hasOnboarded = UserDefaults.standard.bool(forKey: Self.onboardKey)
        load()
        resetStuckStreaming()
        if conversations.isEmpty {
            conversations = [Conversation(profileID: defaultProfile.id)]
            activeConversationID = conversations[0].id
        } else if activeConversationID == nil {
            activeConversationID = conversations.first?.id
        }
        // Induláskor a feladatok újraütemeződnek: új telepítés vagy rendszerfrissítés
        // után is szóljanak, ne csak akkor, ha valaki megnyitja a Feladatok lapot.
        TaskNotifications.resync(tasks)
    }

    // MARK: Derived

    var defaultProfile: PersonaProfile {
        profiles.first(where: { $0.isDefault }) ?? profiles[0]
    }

    var activeConversation: Conversation? {
        get { conversations.first(where: { $0.id == activeConversationID }) }
        set {
            guard let newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id }) else { return }
            conversations[index] = newValue
        }
    }

    func profile(for conversation: Conversation) -> PersonaProfile {
        profiles.first(where: { $0.id == conversation.profileID }) ?? defaultProfile
    }

    var sortedConversations: [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: Conversation lifecycle

    @discardableResult
    func newConversation(profile: PersonaProfile? = nil, tier: String? = nil) -> Conversation {
        let chosen = profile ?? defaultProfile
        var conversation = Conversation(profileID: chosen.id)
        conversation.tier = tier ?? (settings.defaultTier.isEmpty ? chosen.tier : settings.defaultTier)
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        save()
        return conversation
    }

    func select(_ id: UUID) { activeConversationID = id }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if activeConversationID == conversation.id {
            activeConversationID = conversations.first?.id
        }
        save()
    }

    func togglePin(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index].pinned.toggle()
        save()
    }

    func rename(_ conversation: Conversation, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index].title = title
        save()
    }

    func setTier(_ tier: String, for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].tier = tier
        save()
    }

    func setProfile(_ profile: PersonaProfile, for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].profileID = profile.id
        save()
    }

    // MARK: Sending

    func send(_ text: String, images: [ChatImage] = [], files: [ChatFile] = [], research: Bool = false, agent: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || !files.isEmpty, let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        if conversations[index].title == "New chat" {
            conversations[index].title = trimmed.isEmpty ? (files.isEmpty ? "Image" : files[0].name) : Conversation.title(from: trimmed)
        }
        if settings.memoryEnabled, !trimmed.isEmpty { remember(from: trimmed) }
        let userMessage = ChatMessage(role: .user, text: trimmed)
        if !images.isEmpty { attachedImages[userMessage.id] = images }
        if !files.isEmpty { attachedFiles[userMessage.id] = files }
        conversations[index].messages.append(userMessage)
        conversations[index].messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        conversations[index].updatedAt = Date()
        save()

        if conversations[index].projectID == nil, let activeProjectID {
            conversations[index].projectID = activeProjectID
        }
        let tier = conversations[index].tier
        var instructions = profile(for: conversations[index]).instructions
        if let project = project(for: conversations[index]) {
            let brief = project.brief
            if !brief.isEmpty {
                instructions = (brief + "\n\n" + instructions).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let history = conversations[index].messages
        let carried = settings.memoryEnabled ? memories.suffix(24).map(\.text) : []

        lastError = nil
        isStreaming = true
        phase = .thinking
        streamTask?.cancel()
        if research {
            streamTask = Task { [weak self] in
                guard let self else { return }
                await self.runResearch(question: trimmed, conversationID: id)
            }
        } else {
            streamTask = Task { [weak self] in
                guard let self else { return }
                await self.run(history: history, tier: tier, instructions: instructions,
                               memory: carried, images: images, files: files, agent: agent,
                               conversationID: id)
            }
        }
    }

    /// Imagegenerálás a chatben: a kérés bekerül a beszélgetésbe, a válasz-buborék
    /// pedig animált hellyel él, amíg a Void Canvas renderel — aztán megkapja a képet.
    func sendImage(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if conversations[index].title == "New chat" {
            conversations[index].title = Conversation.title(from: trimmed)
        }
        conversations[index].messages.append(ChatMessage(role: .user, text: trimmed))
        let placeholder = ChatMessage(role: .assistant, text: "", imageStatus: "pending")
        conversations[index].messages.append(placeholder)
        conversations[index].updatedAt = Date()
        save()
        let messageID = placeholder.id
        lastError = nil
        isStreaming = true
        phase = .thinking
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let jobID = try await CortexClient.shared.createImage(prompt: trimmed, style: "vivid")
                var status = "processing"
                var url: String?
                for _ in 0..<60 {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    let job = try await CortexClient.shared.imageStatus(id: jobID)
                    status = job.status
                    if status == "succeeded" || status == "failed" { url = job.url; break }
                }
                await MainActor.run {
                    self.applyImageResult(messageID: messageID, conversationID: id,
                                          status: status == "succeeded" ? "succeeded" : "failed",
                                          url: url)
                }
            } catch {
                await MainActor.run {
                    self.applyImageResult(messageID: messageID, conversationID: id,
                                          status: "failed", url: nil)
                }
            }
        }
    }

    /// A kép-render vége: a buborék megkapja a képet (vagy a hibaüzenetet).
    private func applyImageResult(messageID: UUID, conversationID: UUID, status: String, url: String?) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else {
            isStreaming = false; phase = .idle; return
        }
        conversations[ci].messages[mi].imageStatus = status
        conversations[ci].messages[mi].imageURL = url
        if status == "failed" {
            conversations[ci].messages[mi].text = "The image could not be generated. Try again in a bit."
        }
        conversations[ci].updatedAt = Date()
        isStreaming = false
        phase = .idle
        save()
    }

    /// A csatolt képek a munkamenet memóriájában élnek: a mentett beszélgetésbe nem
    /// kerülnek bele, mert egy base64 kép több megabájt, és nem kell visszatölteni.
    private(set) var attachedImages: [UUID: [ChatImage]] = [:]

    func images(for messageID: UUID) -> [ChatImage] {
        attachedImages[messageID] ?? []
    }

    /// A csatolt dokumentumok is csak a munkamenetben élnek: a szöveg a kérés része,
    /// nem a mentett beszélgetésé.
    private(set) var attachedFiles: [UUID: [ChatFile]] = [:]

    func files(for messageID: UUID) -> [ChatFile] {
        attachedFiles[messageID] ?? []
    }

    private func run(history: [ChatMessage], tier: String, instructions: String,
                     memory: [String], images: [ChatImage] = [], files: [ChatFile] = [],
                     agent: Bool = false, conversationID: UUID) async {
        do {
            if settings.streamReplies {
                try await CortexClient.shared.stream(
                    messages: history, tier: tier,
                    extraInstructions: instructions, memory: memory, images: images, files: files,
                    agent: agent,
                    onStep: { step in self.attachStep(step, to: conversationID) },
                    onMeta: { meta in self.applyMeta(meta, to: conversationID) },
                    onDelta: { delta in self.appendDelta(delta, to: conversationID) }
                )
            } else {
                let reply = try await CortexClient.shared.complete(messages: history, tier: tier,
                                                                   extraInstructions: instructions, memory: memory,
                                                                   images: images, files: files)
                self.appendDelta(reply, to: conversationID)
            }
            self.finishStreaming(conversationID: conversationID, failed: false)
        } catch is CancellationError {
            self.finishStreaming(conversationID: conversationID, failed: false)
        } catch {
            self.lastError = error.localizedDescription
            self.finishStreaming(conversationID: conversationID, failed: true)
        }
        // A keret a fióknál van, nem itt: minden kör után a szerverről olvassuk vissza,
        // különben a sáv a régi számot mutatná (főleg 429 után).
        Task { await SubscriptionStore.shared.refreshUsage() }
    }


    /// Ügynöklépés („keresem a forrásokat…") beírása a folyó válaszba.
    /// A MessageRow ezeket a buborék alatt, kis sorként mutatja.
    private func attachStep(_ step: AgentStep, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let last = conversations[index].messages.last, last.role == .assistant else { return }
        let slot = conversations[index].messages.count - 1
        if conversations[index].messages[slot].steps == nil {
            conversations[index].messages[slot].steps = []
        }
        conversations[index].messages[slot].steps?.append(step)
        conversations[index].updatedAt = Date()
        if phase != .thinking { phase = .thinking }
        saveSoon()
    }

    private func applyMeta(_ meta: CortexClient.ReplyMeta, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let last = conversations[index].messages.last, last.role == .assistant else { return }
        let slot = conversations[index].messages.count - 1
        if !meta.layer.isEmpty { conversations[index].messages[slot].layer = meta.layer }
        if !meta.sources.isEmpty { conversations[index].messages[slot].sources = meta.sources }
        if meta.milliseconds > 0 { conversations[index].messages[slot].latencyMS = meta.milliseconds }
        if meta.runs > 0 { conversations[index].messages[slot].runs = meta.runs }
        if !meta.suggestions.isEmpty { conversations[index].messages[slot].suggestions = meta.suggestions }
    }

    /// Mély kutatás: a worker több forrásból dolgozik, a válasz egyben jön, a
    /// lépések közben a fázisjelzőn látszanak. Nem keveredik a sima folyammal.
    private func runResearch(question: String, conversationID: UUID) async {
        do {
            let study = try await CortexClient.shared.research(question: question)
            if let index = conversations.firstIndex(where: { $0.id == conversationID }),
               let last = conversations[index].messages.last, last.role == .assistant {
                let slot = conversations[index].messages.count - 1
                conversations[index].messages[slot].text = study.text ?? ""
                conversations[index].messages[slot].layer = "research"
                conversations[index].messages[slot].sources = study.sources
                conversations[index].messages[slot].latencyMS = study.ms
                conversations[index].messages[slot].suggestions = study.suggestions
                conversations[index].messages[slot].isStreaming = false
                conversations[index].updatedAt = Date()
            }
            isStreaming = false
            phase = .idle
            save()
        } catch is CancellationError {
            finishStreaming(conversationID: conversationID, failed: false)
        } catch {
            lastError = error.localizedDescription
            finishStreaming(conversationID: conversationID, failed: true)
        }
    }

    private func appendDelta(_ delta: String, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard let last = conversations[index].messages.last, last.role == .assistant else { return }
        conversations[index].messages[conversations[index].messages.count - 1].text += delta
        conversations[index].updatedAt = Date()
        if phase != .writing { phase = .writing }
        // A reply that is still streaming must survive the app being killed.
        saveSoon()
    }

    private func finishStreaming(conversationID: UUID, failed: Bool) {
        if let index = conversations.firstIndex(where: { $0.id == conversationID }),
           let last = conversations[index].messages.last, last.role == .assistant {
            conversations[index].messages[conversations[index].messages.count - 1].isStreaming = false
            if failed && conversations[index].messages.last!.isEmpty {
                conversations[index].messages[conversations[index].messages.count - 1].text = ""
                conversations[index].messages.removeLast()
            }
        }
        isStreaming = false
        phase = .idle
        save()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let id = activeConversationID { finishStreaming(conversationID: id, failed: false) }
    }

    func retryLast() {
        guard let id = activeConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        // Drop the failed empty assistant bubble and re-send the last user message.
        guard let lastUser = conversation.messages.last(where: { $0.role == .user }) else { return }
        removeTrailingAssistant()
        send(lastUser.text)
    }

    /// Throws away the last reply and asks the same question again.
    func regenerate() {
        guard !isStreaming, let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        while let last = conversations[index].messages.last, last.role == .assistant {
            conversations[index].messages.removeLast()
        }
        guard let last = conversations[index].messages.last, last.role == .user else { return }
        conversations[index].messages.removeLast()
        save()
        Haptics.tap()
        send(last.text)
    }

    /// Copies the conversation up to a message into a new chat, so a different
    /// continuation can be explored without losing the original.
    func branch(from messageID: UUID) {
        guard let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }),
              let cut = conversations[index].messages.firstIndex(where: { $0.id == messageID }) else { return }
        var copy = conversations[index]
        copy.id = UUID()
        copy.messages = Array(conversations[index].messages.prefix(through: cut))
        copy.title = String(copy.title.prefix(36)) + " · branch"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.pinned = false
        conversations.insert(copy, at: 0)
        activeConversationID = copy.id
        save()
        Haptics.tap()
    }

    private func removeTrailingAssistant() {
        guard let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if let last = conversations[index].messages.last, last.role == .assistant, last.isEmpty {
            conversations[index].messages.removeLast()
        }
        if let last = conversations[index].messages.last, last.role == .user {
            conversations[index].messages.removeLast()
        }
    }

    // MARK: Profiles

    func upsert(_ profile: PersonaProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func makeDefault(_ profile: PersonaProfile) {
        for index in profiles.indices { profiles[index].isDefault = profiles[index].id == profile.id }
        save()
    }

    func deleteProfile(_ profile: PersonaProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        if !profiles.contains(where: { $0.isDefault }), !profiles.isEmpty { profiles[0].isDefault = true }
        for index in conversations.indices where conversations[index].profileID == profile.id {
            conversations[index].profileID = defaultProfile.id
        }
        save()
    }

    // MARK: Memory

    /// Stores the sentence if it looks like a durable fact and we do not have it yet.
    func remember(from text: String) {
        for note in MemoryExtractor.notes(from: text) {
            addMemory(note, automatic: true)
        }
    }

    func addMemory(_ text: String, automatic: Bool = false) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, memories.count < 60 else { return }
        let low = clean.lowercased()
        guard !memories.contains(where: { $0.text.lowercased() == low }) else { return }
        memories.append(MemoryNote(text: clean, automatic: automatic))
        save()
    }

    func removeMemory(_ note: MemoryNote) {
        memories.removeAll { $0.id == note.id }
        save()
    }

    func clearMemories() {
        memories.removeAll()
        save()
    }

    func setMemoryEnabled(_ on: Bool) {
        settings.memoryEnabled = on
        save()
    }

    // MARK: Projects

    var activeProject: Project? {
        projects.first { $0.id == activeProjectID }
    }

    func project(for conversation: Conversation) -> Project? {
        if let id = conversation.projectID, let hit = projects.first(where: { $0.id == id }) { return hit }
        return activeProject
    }

    func selectProject(_ id: UUID?) {
        activeProjectID = id
        if let id, let index = conversations.firstIndex(where: { $0.id == activeConversationID }) {
            conversations[index].projectID = id
        }
        save()
    }

    func upsert(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
        save()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if activeProjectID == id { activeProjectID = nil }
        for index in conversations.indices where conversations[index].projectID == id {
            conversations[index].projectID = nil
        }
        save()
    }

    /// Rövid üzenet a felületnek. Magától eltűnik, nem kell külön állapot rá.
    func flash(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: Két hangnem

    /// Ugyanaz a kérdés két stílusban. Nem streamel: két kész válasz jön egyszerre,
    /// így a felület két oszlopban mutathatja.
    func compare(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        if conversations[index].title == "New chat" {
            conversations[index].title = Conversation.title(from: trimmed)
        }
        conversations[index].messages.append(ChatMessage(role: .user, text: trimmed))
        conversations[index].messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        conversations[index].updatedAt = Date()
        save()

        let tier = conversations[index].tier
        lastError = nil
        isStreaming = true
        phase = .thinking
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await CortexClient.shared.compare(question: trimmed, tier: tier)
                if let at = self.conversations.firstIndex(where: { $0.id == id }),
                   let last = self.conversations[at].messages.last, last.role == .assistant {
                    let slot = self.conversations[at].messages.count - 1
                    self.conversations[at].messages[slot].twoUp = rows
                    self.conversations[at].messages[slot].isStreaming = false
                    self.conversations[at].messages[slot].layer = "compare"
                    self.conversations[at].updatedAt = Date()
                }
                self.isStreaming = false
                self.phase = .idle
                self.save()
            } catch is CancellationError {
                self.finishStreaming(conversationID: id, failed: false)
            } catch {
                self.lastError = error.localizedDescription
                self.finishStreaming(conversationID: id, failed: true)
            }
        }
    }

    // MARK: Megosztás

    /// Link a beszélgetéshez (vagy annak addigi részéhez). A link a vágólapra kerül.
    func shareLink(for message: ChatMessage?) {
        guard let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let all = conversations[index].messages
        let cut = message.flatMap { target in all.firstIndex(where: { $0.id == target.id }).map { $0 + 1 } } ?? all.count
        let rows = all.prefix(cut).compactMap { row -> (role: String, text: String)? in
            guard row.role != .system, !row.text.isEmpty else { return nil }
            return (role: row.role == .assistant ? "assistant" : "user", text: row.text)
        }
        guard !rows.isEmpty else { flash("Nincs mit megosztani"); return }
        let title = conversations[index].title

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await CortexClient.shared.share(messages: Array(rows), title: title)
                UIPasteboard.general.string = url.absoluteString
                Haptics.success()
                self.flash("Link copied — valid for 30 days")
            } catch {
                self.flash("Sharing failed")
            }
        }
    }

    /// Called when the app goes to the background — the last word must not be lost.
    // MARK: Feladatok

    func addTask(_ task: ScheduledTask) {
        tasks.append(task)
        tasks.sort { $0.at < $1.at }
        TaskNotifications.schedule(task)
        syncTask(task, method: "POST")
        save()
    }

    func toggleTask(_ task: ScheduledTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isOn.toggle()
        if tasks[index].isOn { TaskNotifications.schedule(tasks[index]) }
        else { TaskNotifications.cancel(tasks[index]) }
        syncTask(tasks[index], method: "PATCH", remoteID: tasks[index].remoteID)
        save()
    }

    func deleteTask(_ task: ScheduledTask) {
        tasks.removeAll { $0.id == task.id }
        TaskNotifications.cancel(task)
        if let remote = task.remoteID { deleteRemoteTask(remote) }
        save()
    }

    /// „Futtatás most”: ugyanaz, mint ha beírtad volna — a válasz a beszélgetésbe kerül.
    func runTask(_ task: ScheduledTask) {
        send(task.prompt)
    }

    /// A feladat a workerben is megvan (eszköz-azonosítóval). Ha a hálózat nem megy,
    /// a helyi ütemezés akkor is él — ezért a hiba itt csendes.
    private func syncTask(_ task: ScheduledTask, method: String, remoteID: String? = nil) {
        var request = URLRequest(url: URL(string: "https://cortanime.eu/api/cortexai/tasks")!)
        request.httpMethod = method
        request.setValue(deviceHeader, forHTTPHeaderField: "X-Cortex-Client")
        if let remoteID { request.url = URL(string: "https://cortanime.eu/api/cortexai/tasks?id=\(remoteID)") }
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let iso = ISO8601DateFormatter()
            let body: [String: Any] = [
                "prompt": task.prompt,
                "title": task.title,
                "at": iso.string(from: task.at),
                "repeat": task.repeats == .daily ? "daily" : "once",
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let localID = task.id
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard method == "POST", let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let row = obj["task"] as? [String: Any],
                  let remote = row["id"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self, let index = self.tasks.firstIndex(where: { $0.id == localID }) else { return }
                self.tasks[index].remoteID = remote
            }
        }.resume()
    }

    private func deleteRemoteTask(_ remoteID: String) {
        var request = URLRequest(url: URL(string: "https://cortanime.eu/api/cortexai/tasks?id=\(remoteID)")!)
        request.httpMethod = "DELETE"
        request.setValue(deviceHeader, forHTTPHeaderField: "X-Cortex-Client")
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Ugyanaz az azonosító, amit a chat-kérések is visznek.
    private var deviceHeader: String {
        UserDefaults.standard.string(forKey: "cortex.client.id") ?? UUID().uuidString
    }

    func flush() {
        save()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var conversations: [Conversation]
        var profiles: [PersonaProfile]
        var settings: CortexSettings
        var activeConversationID: UUID?
        var memories: [MemoryNote] = []
        var projects: [Project] = []
        var activeProjectID: UUID?
        var tasks: [ScheduledTask] = []

        init(conversations: [Conversation], profiles: [PersonaProfile],
             settings: CortexSettings, activeConversationID: UUID?, memories: [MemoryNote],
             projects: [Project] = [], activeProjectID: UUID? = nil, tasks: [ScheduledTask] = []) {
            self.conversations = conversations
            self.profiles = profiles
            self.settings = settings
            self.activeConversationID = activeConversationID
            self.memories = memories
            self.projects = projects
            self.activeProjectID = activeProjectID
            self.tasks = tasks
        }

        /// Every field is optional on the way in: a store written by an older version
        /// still loads, instead of failing and taking the whole chat history with it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            conversations = try c.decodeIfPresent([Conversation].self, forKey: .conversations) ?? []
            profiles = try c.decodeIfPresent([PersonaProfile].self, forKey: .profiles) ?? []
            settings = try c.decodeIfPresent(CortexSettings.self, forKey: .settings) ?? .default
            activeConversationID = try c.decodeIfPresent(UUID.self, forKey: .activeConversationID)
            memories = try c.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
            projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
            activeProjectID = try c.decodeIfPresent(UUID.self, forKey: .activeProjectID)
            tasks = try c.decodeIfPresent([ScheduledTask].self, forKey: .tasks) ?? []
        }
    }

    func save() {
        let snapshot = Snapshot(
            conversations: conversations,
            profiles: profiles,
            settings: settings,
            activeConversationID: activeConversationID,
            memories: memories,
            projects: projects,
            activeProjectID: activeProjectID,
            tasks: tasks
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            let primary = storeURL
            // A második példány (backup) csak minden ötödik írásnál készül el; a lényeg,
            // hogy egy rossz írás soha ne vigye el a beszélgetéseket.
            backupWrites += 1
            let alsoBackup = backupWrites % 5 == 0
            let backup = backupURL
            // Az írás lemezes — nem a fő szálon. Így egy hosszú beszélgetés mentése sem
            // akasztja meg a gépelést.
            Task.detached(priority: .utility) {
                do {
                    try data.write(to: primary, options: .atomic)
                    if alsoBackup { try? data.write(to: backup, options: .atomic) }
                } catch {
                    print("Cortex AI: save failed — \(error)")
                }
            }
            Spotlight.schedule(conversations)
        } catch {
            // Persistence must never take the UI down.
            print("Cortex AI: save failed — \(error)")
        }
    }

    /// Folyó válasz közben ez megy: legfeljebb két másodpercenként ír, hogy a gépelés
    /// alatt ne lemezeljünk minden delta után. A válasz végén a `save()` már azonnal ír.
    func saveSoon() {
        guard Date().timeIntervalSince(lastDeltaSave) > 2.0 else { return }
        lastDeltaSave = Date()
        save()
    }

    private func load() {
        for url in [storeURL, backupURL] {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                apply(snapshot)
                return
            }
            // Unreadable store: keep it for a later rescue instead of overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let kept = storeDir.appendingPathComponent("cortex-ai-store.damaged-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: kept)
        }
    }

    private func apply(_ snapshot: Snapshot) {
        conversations = snapshot.conversations
        profiles = snapshot.profiles.isEmpty ? PersonaProfile.builtIns : snapshot.profiles
        settings = snapshot.settings
        activeConversationID = snapshot.activeConversationID
        memories = snapshot.memories
        projects = snapshot.projects
        activeProjectID = snapshot.activeProjectID
        tasks = snapshot.tasks
        // Older versions could store a half-streamed bubble; never let it spin forever.
        resetStuckStreaming()
    }

    /// A reply that was streaming when the app died comes back as ordinary text.
    private func resetStuckStreaming() {
        for c in conversations.indices {
            for m in conversations[c].messages.indices where conversations[c].messages[m].isStreaming {
                conversations[c].messages[m].isStreaming = false
            }
        }
        isStreaming = false
    }

    func eraseEverything() {
        conversations = [Conversation(profileID: defaultProfile.id)]
        activeConversationID = conversations.first?.id
        memories.removeAll()
        settings = .default
        save()
    }
}


// MARK: - Lapok

/// A nyitható lapok. `String` nyersérték, mert a SwiftUI `sheet(item:)` az `id`-t várja.
enum AppSheet: String, Identifiable {
    case library, settings, profiles, studio, features, projects, tasks, knowledge
    case subscription, prompts, export, commands

    var id: String { rawValue }
}
