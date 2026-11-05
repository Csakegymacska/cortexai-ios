import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Live voice input: the microphone becomes text in the composer while you speak, so
/// talking and typing are the same gesture. Everything runs on device when the phone
/// supports it (`requiresOnDeviceRecognition`), nothing is uploaded for transcription.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "hu-HU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        errorText = nil
        transcript = ""
        Task { await begin() }
    }

    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        teardown()
    }

    /// Called after the draft has been handed to the chat.
    func reset() {
        transcript = ""
        level = 0
    }

    // MARK: Session

    private func begin() async {
        guard await microphoneAllowed() else {
            errorText = "Microphone access is off. Turn it on in iOS Settings."
            return
        }
        guard await speechAllowed() else {
            errorText = "Speech recognition is off. Turn it on in iOS Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Voice input is unavailable right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Could not open the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorText = "No microphone is available."
            teardown()
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.rms(buffer)
            Task { @MainActor in self?.level = level }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.teardown() }
                }
                if error != nil, self.isRecording { self.teardown() }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorText = "Could not start recording."
            teardown()
            return
        }
        isRecording = true
        Haptics.tap()
    }

    private func teardown() {
        isRecording = false
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Permissions

    private func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    // MARK: Level

    /// Loudness of one buffer, 0…1, used by the waveform.
    nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let value = sqrt(sum / Float(count))
        return CGFloat(min(1, max(0, value * 6)))
    }
}

// MARK: - Waveform

/// Five bars that answer the microphone. Replaced by a static row when Reduce Motion
/// is on, so the state is still readable without movement.
struct VoiceWaveform: View {
    let level: CGFloat
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tick = false

    private let weights: [CGFloat] = [0.55, 0.85, 1.0, 0.72, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                Capsule()
                    .fill(LinearGradient(colors: [Theme.cyan, Theme.violet], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5, height: height(weight: weight, index: index))
            }
        }
        .frame(width: 26, height: 20)
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
            tick.toggle()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: level)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: tick)
        .accessibilityHidden(true)
    }

    private func height(weight: CGFloat, index: Int) -> CGFloat {
        guard active else { return 3 }
        let base = 4 + level * 14 * weight
        let wobble = tick ? CGFloat(index % 2 == 0 ? 1.1 : 0.85) : 1.0
        return max(3, min(20, base * wobble))
    }
}
