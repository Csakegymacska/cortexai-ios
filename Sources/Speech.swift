import AVFoundation
import Foundation
import Observation

/// Reading a reply out loud.
///
/// The synthesiser speaks Hungarian when the phone has a Hungarian voice, English
/// otherwise. Code blocks are dropped before speaking — nobody wants a brace read aloud —
/// and the audio session ducks other playback instead of stopping it.
@Observable
@MainActor
final class SpeechEngine {
    static let shared = SpeechEngine()

    /// Which message is being read right now, so the button can turn into a stop button.
    private(set) var speakingID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    private let proxy = SpeechDelegate()

    private init() {
        proxy.onFinish = { [weak self] in
            Task { @MainActor in self?.speakingID = nil }
        }
        synthesizer.delegate = proxy
    }

    func toggle(_ message: ChatMessage) {
        if speakingID == message.id { stop() } else { speak(message) }
    }

    func speak(_ message: ChatMessage) {
        let spoken = SpeechEngine.plain(message.text)
        guard !spoken.isEmpty else { return }
        stop()
        activateSession()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = AVSpeechSynthesisVoice(language: "hu-HU") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingID = message.id
        synthesizer.speak(utterance)
        Haptics.tap()
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }

    /// Markdown and code are written for the eye, not the ear, so they are flattened first.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        while let start = text.range(of: "```"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        let noise = ["**", "__", "`", "### ", "## ", "# ", "- ", "* ", "|", "> "]
        for needle in noise { text = text.replacingOccurrences(of: needle, with: "") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The synthesiser calls back from its own thread. This proxy hands the news back to the
/// main actor instead of dragging the whole engine out of isolation.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
