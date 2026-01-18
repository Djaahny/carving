import AVFoundation
import Combine
import Foundation

@MainActor
final class RideSessionViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var elapsed: TimeInterval = 0
    @Published var timeCalloutsEnabled = true
    @Published var edgeCalloutsEnabled = true
    @Published var edgeSamples: [EdgeSample] = []

    private var startDate: Date?
    private var timerCancellable: AnyCancellable?
    private var lastTimeCalloutCount = 0
    private var lastEdgeCalloutTime: Date?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let edgeThreshold = 60.0

    func startRun() {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()
        elapsed = 0
        edgeSamples = []
        lastTimeCalloutCount = 0
        lastEdgeCalloutTime = nil

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(startDate)
                self.handleTimeCallout()
            }
    }

    func stopRun() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func ingest(edgeAngle: Double, at date: Date = Date()) {
        guard isRunning else { return }
        edgeSamples.append(EdgeSample(timestamp: date, angle: edgeAngle))
        pruneSamples()
        handleEdgeCallout(angle: edgeAngle)
    }

    private func pruneSamples() {
        let cutoff = Date().addingTimeInterval(-10)
        edgeSamples.removeAll { $0.timestamp < cutoff }
    }

    private func handleTimeCallout() {
        guard timeCalloutsEnabled else { return }
        let calloutCount = Int(elapsed / 30)
        guard calloutCount > lastTimeCalloutCount else { return }
        lastTimeCalloutCount = calloutCount
        let seconds = calloutCount * 30
        speak("\(seconds) seconds")
    }

    private func handleEdgeCallout(angle: Double) {
        guard edgeCalloutsEnabled, angle >= edgeThreshold else { return }
        let now = Date()
        if let lastCallout = lastEdgeCalloutTime, now.timeIntervalSince(lastCallout) < 5 {
            return
        }
        lastEdgeCalloutTime = now
        speak("Edge angle \(Int(angle)) degrees")
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let siriVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name.contains("Siri") }) {
            utterance.voice = siriVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }
}
