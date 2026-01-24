import AVFoundation
import Combine
import Foundation

@MainActor
final class RideSessionViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isStopped = false
    @Published var elapsed: TimeInterval = 0
    @Published var timeCalloutsEnabled = true
    @Published var edgeCalloutsEnabled = true
    @Published var edgeCalloutThreshold: Double {
        didSet {
            UserDefaults.standard.set(edgeCalloutThreshold, forKey: edgeThresholdKey)
        }
    }
    @Published var edgeSamples: [EdgeSample] = []
    @Published var latestEdgeAngle: Double = 0
    @Published var latestSpeedMetersPerSecond: Double = 0
    @Published var turnWindows: [TurnWindow] = []
    @Published var backgroundSamples: [BackgroundSample] = []
    @Published var locationTrack: [LocationSample] = []
    @Published var turnCount = 0

    private var startDate: Date?
    private var timerCancellable: AnyCancellable?
    private var lastTimeCalloutCount = 0
    private var lastEdgeCalloutTime: Date?
    private var lastSampleTime: Date?
    private var lastBackgroundSampleTime: Date?
    private var lastLocationSampleTime: Date?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let minSampleInterval: TimeInterval = 0
    private let edgeThresholdKey = "edgeCalloutThreshold"
    private let defaultEdgeThreshold = 60.0
    private let backgroundSampleInterval: TimeInterval = 0
    private let locationSampleInterval: TimeInterval = 0

    private let turnSettings = TurnDetectorSettings()
    private var gravityEstimate: Vector3?
    private var recordedEdgeSamples: [EdgeSample] = []
    private var isInTurn = false
    private var turnStartCandidate: Date?
    private var turnEndCandidate: Date?
    private var currentTurnStart: Date?
    private var currentTurnSamples: [TurnSample] = []
    private var lastTurnStart: Date?
    private var latestLocationSample: LocationSample?

    init() {
        let storedThreshold = UserDefaults.standard.object(forKey: edgeThresholdKey) as? Double
        edgeCalloutThreshold = storedThreshold ?? defaultEdgeThreshold
        configureAudioSession()
    }

    func startRun(isCalibrated: Bool) {
        guard isCalibrated else { return }
        guard !isRunning else { return }
        configureAudioSession()
        isRunning = true
        isStopped = false
        startDate = Date()
        elapsed = 0
        edgeSamples = []
        recordedEdgeSamples = []
        turnWindows = []
        backgroundSamples = []
        locationTrack = []
        turnCount = 0
        lastTimeCalloutCount = 0
        lastEdgeCalloutTime = nil
        lastSampleTime = nil
        lastBackgroundSampleTime = nil
        lastLocationSampleTime = nil
        gravityEstimate = nil
        isInTurn = false
        turnStartCandidate = nil
        turnEndCandidate = nil
        currentTurnStart = nil
        currentTurnSamples = []
        lastTurnStart = nil
        latestLocationSample = nil

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
        isStopped = true
        timerCancellable?.cancel()
        timerCancellable = nil
        deactivateAudioSession()
    }

    func ingest(
        sample: SensorSample,
        edgeAngle: Double,
        speedMetersPerSecond: Double,
        location: LocationSample?,
        at date: Date = Date()
    ) {
        guard isRunning else { return }
        if let lastSampleTime, date.timeIntervalSince(lastSampleTime) < minSampleInterval {
            return
        }
        lastSampleTime = date
        latestEdgeAngle = edgeAngle
        latestSpeedMetersPerSecond = speedMetersPerSecond
        let edgeSample = EdgeSample(timestamp: date, angle: edgeAngle)
        edgeSamples.append(edgeSample)
        recordedEdgeSamples.append(edgeSample)
        pruneSamples()
        handleEdgeCallout(angle: edgeAngle, speedMetersPerSecond: speedMetersPerSecond)

        if let location {
            trackLocation(location, at: date)
        }

        let turnSignal = computeTurnSignal(from: sample)
        updateTurnDetection(turnSignal: turnSignal, edgeAngle: edgeAngle, location: location, at: date)

        if !isInTurn {
            maybeStoreBackgroundSample(edgeAngle: edgeAngle, at: date)
        }
    }

    func ingestLocation(_ location: LocationSample, at date: Date? = nil) {
        guard isRunning else { return }
        let sampleDate = date ?? location.timestamp
        trackLocation(location, at: sampleDate)
    }

    private func pruneSamples() {
        let cutoff = Date().addingTimeInterval(-10)
        edgeSamples.removeAll { $0.timestamp < cutoff }
    }

    private func trackLocation(_ location: LocationSample, at date: Date) {
        if let lastLocationSampleTime, date.timeIntervalSince(lastLocationSampleTime) < locationSampleInterval {
            return
        }
        lastLocationSampleTime = date
        latestLocationSample = location
        locationTrack.append(location)
    }

    private func maybeStoreBackgroundSample(edgeAngle: Double, at date: Date) {
        if let lastBackgroundSampleTime, date.timeIntervalSince(lastBackgroundSampleTime) < backgroundSampleInterval {
            return
        }
        lastBackgroundSampleTime = date
        backgroundSamples.append(BackgroundSample(timestamp: date, edgeAngle: edgeAngle))
    }

    private func computeTurnSignal(from sample: SensorSample) -> Double {
        let accel = Vector3(x: sample.ax, y: sample.ay, z: sample.az)
        if let estimate = gravityEstimate {
            gravityEstimate = estimate.lerp(to: accel, alpha: turnSettings.gravityAlpha)
        } else {
            gravityEstimate = accel
        }
        guard let gravityEstimate else { return 0 }
        let gravityAxis = gravityEstimate.normalized
        let gyro = Vector3(x: sample.gx, y: sample.gy, z: sample.gz)
        return Vector3.dot(gyro, gravityAxis)
    }

    private func updateTurnDetection(turnSignal: Double, edgeAngle: Double, location: LocationSample?, at date: Date) {
        if isInTurn {
            currentTurnSamples.append(TurnSample(timestamp: date, edgeAngle: edgeAngle, turnSignal: turnSignal))
            if abs(turnSignal) < turnSettings.turnOffThreshold, edgeAngle <= turnSettings.edgeAngleExitThreshold {
                if turnEndCandidate == nil {
                    turnEndCandidate = date
                }
                if let turnEndCandidate, date.timeIntervalSince(turnEndCandidate) >= turnSettings.turnStopHold {
                    finalizeTurn(at: date)
                }
            } else {
                turnEndCandidate = nil
            }
            return
        }

        if abs(turnSignal) > turnSettings.turnOnThreshold {
            if turnStartCandidate == nil {
                turnStartCandidate = date
            }
            if let turnStartCandidate,
               date.timeIntervalSince(turnStartCandidate) >= turnSettings.turnStartHold,
               canStartTurn(at: date)
            {
                beginTurn(at: date, edgeAngle: edgeAngle, turnSignal: turnSignal)
            }
        } else {
            turnStartCandidate = nil
        }
    }

    private func canStartTurn(at date: Date) -> Bool {
        guard let lastTurnStart else { return true }
        return date.timeIntervalSince(lastTurnStart) >= turnSettings.minTurnGap
    }

    private func beginTurn(at date: Date, edgeAngle: Double, turnSignal: Double) {
        isInTurn = true
        turnStartCandidate = nil
        turnEndCandidate = nil
        currentTurnStart = date
        lastTurnStart = date
        currentTurnSamples = [TurnSample(timestamp: date, edgeAngle: edgeAngle, turnSignal: turnSignal)]
        turnCount += 1
    }

    private func finalizeTurn(at date: Date) {
        guard let start = currentTurnStart else {
            resetTurnTracking()
            return
        }
        let duration = date.timeIntervalSince(start)
        guard duration >= turnSettings.minTurnDuration else {
            resetTurnTracking()
            return
        }
        let meanSignal = currentTurnSamples.map(\.turnSignal).reduce(0, +) / Double(currentTurnSamples.count)
        let direction = TurnDirection.from(signal: meanSignal)
        let peakEdgeAngle = currentTurnSamples.map(\.edgeAngle).max() ?? 0
        let window = TurnWindow(
            index: turnWindows.count + 1,
            startTime: start,
            endTime: date,
            direction: direction,
            meanTurnSignal: meanSignal,
            peakEdgeAngle: peakEdgeAngle,
            samples: currentTurnSamples,
            location: latestLocationSample
        )
        turnWindows.append(window)
        resetTurnTracking()
    }

    private func resetTurnTracking() {
        isInTurn = false
        turnEndCandidate = nil
        currentTurnStart = nil
        currentTurnSamples = []
    }

    func buildRunRecord(runNumber: Int, date: Date = Date()) -> RunRecord {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        let name = "\(dateString) Run \(runNumber)"
        return RunRecord(
            date: date,
            runNumber: runNumber,
            name: name,
            turnWindows: turnWindows,
            backgroundSamples: backgroundSamples,
            locationTrack: locationTrack,
            edgeSamples: recordedEdgeSamples
        )
    }

    private func handleTimeCallout() {
        guard timeCalloutsEnabled else { return }
        let calloutCount = Int(elapsed / 30)
        guard calloutCount > lastTimeCalloutCount else { return }
        guard !speechSynthesizer.isSpeaking else { return }
        lastTimeCalloutCount = calloutCount
        let seconds = calloutCount * 30
        speak("\(seconds) seconds")
    }

    private func handleEdgeCallout(angle: Double, speedMetersPerSecond: Double) {
        guard edgeCalloutsEnabled, angle >= edgeCalloutThreshold else { return }
        guard !speechSynthesizer.isSpeaking else { return }
        let now = Date()
        if let lastCallout = lastEdgeCalloutTime, now.timeIntervalSince(lastCallout) < 5 {
            return
        }
        lastEdgeCalloutTime = now
        let speedKmh = max(speedMetersPerSecond, 0) * 3.6
        speak("Edge angle \(Int(angle)) degrees at \(Int(speedKmh)) kilometers per hour")
    }

    private func speak(_ text: String) {
        configureAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        if let siriVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name.contains("Siri") }) {
            utterance.voice = siriVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true, options: [])
    }

    private func deactivateAudioSession() {
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private struct TurnDetectorSettings {
    let turnOnThreshold: Double = 25
    let turnOffThreshold: Double = 15
    let edgeAngleExitThreshold: Double = 5
    let turnStartHold: TimeInterval = 0.15
    let turnStopHold: TimeInterval = 0.2
    let minTurnDuration: TimeInterval = 0.4
    let minTurnGap: TimeInterval = 0.3
    let gravityAlpha: Double = 0.08
}

private struct Vector3 {
    let x: Double
    let y: Double
    let z: Double

    var length: Double {
        sqrt(x * x + y * y + z * z)
    }

    var normalized: Vector3 {
        let len = length
        guard len > 0 else { return self }
        return Vector3(x: x / len, y: y / len, z: z / len)
    }

    func lerp(to target: Vector3, alpha: Double) -> Vector3 {
        Vector3(
            x: x + alpha * (target.x - x),
            y: y + alpha * (target.y - y),
            z: z + alpha * (target.z - z)
        )
    }

    static func dot(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }
}

private extension TurnDirection {
    static func from(signal: Double) -> TurnDirection {
        if signal > 0 { return .right }
        if signal < 0 { return .left }
        return .unknown
    }
}
