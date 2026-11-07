// ActivityView — az élő lépés-napló (step ledger) és a konzol-nézet.
// Mintaminták: Claude Code / Devin / Manus — minden művelet kártyán,
// a futó lépés mindig látszik, a kimenet kibontható.
import SwiftUI

/// Chat | Activity | Console fülek tartója — a műszerfal gerince.
struct AgentTabs: View {
    @Binding var tab: Int
    @Namespace private var ns

    private let titles = ["Chat", "Activity", "Console"]
    private let icons = ["bubble.left", "list.bullet.rectangle", "terminal"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Button {
                    Haptics.select()
                    withAnimation(Theme.spring) { tab = i }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icons[i]).font(.system(size: 11, weight: .bold))
                        Text(titles[i]).font(Theme.ui(13)).fontWeight(.semibold)
                    }
                    .foregroundStyle(tab == i ? .white : Theme.txt3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if tab == i {
                            RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous)
                                .fill(Theme.accent.opacity(0.85))
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                }
            }
        }
        .padding(4)
        .background(Theme.surf, in: RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// Misszió-sáv — a futó task fejléce: cím, állapot, eltelt idő.
struct MissionStrip: View {
    let log: AgentLog
    var body: some View {
        if log.task.state != "idle" && !log.task.title.isEmpty {
            HStack(spacing: 10) {
                Circle()
                    .fill(log.task.state == "working" ? Theme.pink : (log.task.state == "done" ? Theme.ok : Theme.err))
                    .frame(width: 8, height: 8)
                    .shadow(color: log.task.state == "working" ? Theme.pink.opacity(0.8) : .clear, radius: 4)
                Text(log.task.title)
                    .font(Theme.ui(13)).fontWeight(.semibold)
                    .foregroundStyle(Theme.txt)
                    .lineLimit(1)
                Spacer()
                Text(log.task.state.uppercased())
                    .font(Theme.ui(10)).fontWeight(.bold)
                    .kerning(1)
                    .foregroundStyle(log.task.state == "working" ? Theme.pink : Theme.txt3)
                Text("\(log.steps.filter { $0.state == "done" || $0.state == "failed" } .count)/\(log.steps.count)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt3)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surf, in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }
}

/// A lépés-napló — a hitelesség maga: mit csinál az agent, lépésről lépésre.
struct ActivityView: View {
    @ObservedObject var feed: AgentFeed

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if feed.log.steps.isEmpty {
                    emptyState
                }
                ForEach(feed.log.steps) { step in
                    StepCard(step: step)
                }
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            CoreMark(size: 64, working: false)
                .padding(.top, 40)
            Text("No agent runs yet")
                .font(Theme.display(18)).fontWeight(.bold)
                .foregroundStyle(Theme.txt)
            Text("Tasks executed by the Linux runner appear here\nas a live step ledger.")
                .font(Theme.ui(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.txt3)
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("phantom_runner.py")
                    .font(Theme.mono)
            }
            .foregroundStyle(Theme.txt3)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.surf, in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rSm).stroke(Theme.line, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Egy lépés kártya — állapot-jel, cím, mono részlet, kibontható kimenet.
struct StepCard: View {
    let step: AgentStep
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Theme.softSpring) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    glyph
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(step.n).")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt3)
                            Text(step.title)
                                .font(Theme.ui(14)).fontWeight(.semibold)
                                .foregroundStyle(Theme.txt)
                                .lineLimit(1)
                        }
                        if !step.detail.isEmpty && step.detail != step.title {
                            Text(step.detail)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt3)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if step.sec > 0 {
                        Text(String(format: "%.1fs", step.sec))
                            .font(Theme.mono)
                            .foregroundStyle(Theme.txt3)
                    }
                    if !step.out.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.txt3)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
            }

            if open && !step.out.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(step.out)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.txt2)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: 520, alignment: .leading)
                        .background(Theme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Theme.surf, in: RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous)
                .stroke(step.state == "working" ? Theme.vio.opacity(0.5) : Theme.line, lineWidth: 1)
        )
    }

    @ViewBuilder private var glyph: some View {
        switch step.state {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.ok)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.err)
        case "working":
            ProgressView().controlSize(.small).tint(Theme.pink)
        default:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.txt3)
        }
    }
}

/// Konzol — a nyers kimenet folyam, terminal-szerűen.
struct ConsoleView: View {
    @ObservedObject var feed: AgentFeed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                    Text("PHANTOM RUNNER OUTPUT")
                        .font(Theme.ui(10)).fontWeight(.bold)
                        .kerning(1.5)
                    Spacer()
                    Text(feed.online ? "LIVE" : "OFFLINE")
                        .font(Theme.ui(10)).fontWeight(.bold)
                        .kerning(1)
                        .foregroundStyle(feed.online ? Theme.ok : Theme.err)
                }
                .foregroundStyle(Theme.txt3)

                if feed.log.steps.isEmpty {
                    Text("waiting for runner output…")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.txt3)
                }
                ForEach(feed.log.steps) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$ \(s.title)")
                            .font(Theme.mono)
                            .foregroundStyle(s.state == "failed" ? Theme.err : Theme.pink)
                        if !s.out.isEmpty {
                            Text(s.out)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt2)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .background(Theme.bg.opacity(0.5))
    }
}
