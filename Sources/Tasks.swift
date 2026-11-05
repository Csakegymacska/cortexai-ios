import SwiftUI
import UserNotifications

/// Ütemezett feladat: egy kérés, egy időpont, és a telefon szól, amikor eljön.
///
/// A lista a workerben is megvan (eszköz-azonosítóval), így eszközváltásnál sem vész el;
/// magát az ébresztést viszont a telefon végzi helyben, hálózat és fiók nélkül.
struct ScheduledTask: Identifiable, Codable, Hashable {
    enum Repeats: String, Codable { case once, daily }

    var id: UUID = UUID()
    var title: String
    var prompt: String
    var at: Date
    var repeats: Repeats = .once
    var isOn: Bool = true
    /// A workerben kapott azonosító, ha sikerült feltölteni.
    var remoteID: String? = nil

    var isPast: Bool { at < Date() && repeats == .once }

    var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d. HH:mm"
        return f.string(from: at)
    }
}

// MARK: - Értesítések

enum TaskNotifications {
    /// A rendszer kérését csak egyszer kérjük; ha nem engedték, a feladat akkor is látszik.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func schedule(_ task: ScheduledTask) {
        guard task.isOn else { cancel(task); return }
        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "Cortex AI" : task.title
        content.body = task.prompt
        content.sound = .default
        content.userInfo = ["prompt": task.prompt, "task": task.id.uuidString]
        // A szöveg ne legyen semleges: a válasz is ott vár, ha rákattint.
        content.subtitle = "A válasz már készül"

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.at)
        if task.repeats == .daily {
            components = Calendar.current.dateComponents([.hour, .minute], from: task.at)
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: task.repeats == .daily)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel(_ task: ScheduledTask) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }

    /// A meglévő feladatok újraütemezése (pl. új telepítés után).
    static func resync(_ tasks: [ScheduledTask]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let alive = Set(tasks.filter(\.isOn).map(\.id.uuidString))
            let stale = pending.map(\.identifier).filter { !alive.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        }
        for task in tasks where task.isOn && !task.isPast { schedule(task) }
    }
}

/// A feladatra koppintva az értesítésből: a kérés bekerül a szövegmezőbe.
final class TaskNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Az UNUserNotificationCenter csak a fő szálon hívja; az osztály maga nem tart állapotot.
    nonisolated(unsafe) static let shared = TaskNotificationDelegate()

    @MainActor
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let prompt = info["prompt"] as? String, !prompt.isEmpty {
            await MainActor.run {
                UserDefaults.standard.set(prompt, forKey: "cortex.pendingPrompt")
            }
        }
    }

    /// Előtérben is látszódjon, hogy a feladat lefutott.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Felület

struct TasksView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var adding = false
    @State private var title = ""
    @State private var prompt = ""
    @State private var at = Date().addingTimeInterval(3600)
    @State private var repeatsDaily = false
    @State private var denied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if state.tasks.isEmpty {
                        emptyCard
                    } else {
                        ForEach(state.tasks) { task in
                            row(task)
                        }
                    }
                    if denied {
                        Text("Az értesítés nincs engedélyezve — a feladat mentve van, de a telefon nem fog szólni. Bekapcsolás: Beállítások → Cortex AI → Értesítések.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.danger.opacity(0.9))
                    }
                    Button {
                        adding = true
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Új feladat")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ink)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kész") { dismiss() } } }
            .sheet(isPresented: $adding) { editor.presentationBackground(Theme.ink) }
            .task {
                if !state.tasks.isEmpty {
                    let ok = await TaskNotifications.requestPermission()
                    denied = !ok
                    if ok { TaskNotifications.resync(state.tasks) }
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Még nincs feladat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Írj be egy kérdést, válassz időpontot — a Cortex akkor válaszol, amikor kell. Például: „Ma mi jön ki?” reggel 7:30-kor, minden nap.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func row(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(task.title.isEmpty ? task.prompt : task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { task.isOn },
                    set: { _ in state.toggleTask(task); Haptics.tap() }
                ))
                .labelsHidden()
                .tint(Theme.violet)
                .scaleEffect(0.82)
            }
            Text(task.prompt)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
            HStack(spacing: 7) {
                chip(task.timeLabel, symbol: "clock")
                if task.repeats == .daily { chip("naponta", symbol: "repeat") }
                if task.isPast { chip("lejárt", symbol: "exclamationmark.circle") }
                Spacer(minLength: 0)
                Button("Futtatás") {
                    dismiss()
                    state.runTask(task)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.violetSoft)
                Button {
                    state.deleteTask(task)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceRaised, in: Capsule())
    }

    private var editor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Megnevezés", text: $title, hint: "Reggeli adás")
                    field("Kérdés", text: $prompt, hint: "Melyik anime jön ki ma?", axis: .vertical)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MIKOR").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.textFaint)
                        DatePicker("", selection: $at, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Theme.violetSoft)
                    }
                    Toggle(isOn: $repeatsDaily) {
                        Text("Minden nap ebben az időben")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.text)
                    }
                    .tint(Theme.violet)

                    Button {
                        Task { await save() }
                    } label: {
                        Text("Mentés")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ink)
            .navigationTitle("Új feladat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Mégse") { adding = false } }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, hint: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.textFaint)
            TextField(hint, text: text, axis: axis)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
        }
    }

    private func save() async {
        let ok = await TaskNotifications.requestPermission()
        denied = !ok
        state.addTask(ScheduledTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            at: at,
            repeats: repeatsDaily ? .daily : .once
        ))
        title = ""
        prompt = ""
        repeatsDaily = false
        at = Date().addingTimeInterval(3600)
        adding = false
        Haptics.success()
    }
}
