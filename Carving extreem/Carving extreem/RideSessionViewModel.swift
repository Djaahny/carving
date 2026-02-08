import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class RideSessionViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isStopped = false
    @Published var elapsed: TimeInterval = 0
    @Published var timeCalloutsEnabled = true
    @Published var edgeCalloutsEnabled = true
    @Published var rawDataRecordingEnabled = false
    @Published var sensorMode: SensorMode = .single
    @Published var primarySide: SensorSide = .single
    @Published var edgeCalloutThreshold: Double {
        didSet {
            UserDefaults.standard.set(edgeCalloutThreshold, forKey: edgeThresholdKey)
        }
    }
    @Published var edgeSamples: [EdgeSample] = []
    @Published var latestEdgeAngle: Double = 0
    @Published var latestEdgeAnglesBySide: [SensorSide: Double] = [:]
    @Published var latestSpeedMetersPerSecond: Double = 0
    @Published var turnWindows: [TurnWindow] = []
    @Published var backgroundSamples: [BackgroundSample] = []
    @Published var locationTrack: [LocationSample] = []
    @Published var turnCount = 0
    @Published var rawSensorSamples: [RawSensorSample] = []
    @Published var canStartFromRemote = false {
        didSet {
            updateRemoteCommandAvailability()
        }
    }

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
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var remoteCommandTargets: [Any] = []

    private let turnSettings = TurnDetectorSettings()
    private var recordedEdgeSamples: [EdgeSample] = []
    private var isInTurn = false
    private var turnStartCandidate: Date?
    private var turnEndCandidate: Date?
    private var currentTurnStart: Date?
    private var currentTurnSamples: [TurnSample] = []
    private var lastTurnStart: Date?
    private var currentTurnPeakSignal: Double = 0
    private var turnSignalHistory: [Double] = []
    private var latestLocationSample: LocationSample?
    private var latestPrimarySample: SensorSample?
    private var latestPrimarySide: SensorSide?
    private var latestRawSamplesBySide: [SensorSide: SensorSample] = [:]
    private var turnSignalProcessor = TurnSignalProcessor()

    init() {
        let storedThreshold = UserDefaults.standard.object(forKey: edgeThresholdKey) as? Double
        edgeCalloutThreshold = storedThreshold ?? defaultEdgeThreshold
        configureRemoteCommands()
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
        latestEdgeAnglesBySide = [:]
        rawSensorSamples = []
        lastTimeCalloutCount = 0
        lastEdgeCalloutTime = nil
        lastSampleTime = nil
        lastBackgroundSampleTime = nil
        lastLocationSampleTime = nil
        isInTurn = false
        turnStartCandidate = nil
        turnEndCandidate = nil
        currentTurnStart = nil
        currentTurnSamples = []
        lastTurnStart = nil
        currentTurnPeakSignal = 0
        turnSignalHistory = []
        latestLocationSample = nil
        latestPrimarySample = nil
        latestPrimarySide = nil
        latestRawSamplesBySide = [:]

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(startDate)
                self.handleTimeCallout()
                self.updateNowPlayingInfo()
            }
        updateNowPlayingInfo()
        updateRemoteCommandAvailability()
    }

    func stopRun() {
        isRunning = false
        isStopped = true
        timerCancellable?.cancel()
        timerCancellable = nil
        deactivateAudioSession()
        updateNowPlayingInfo()
        updateRemoteCommandAvailability()
    }

    func ingest(
        sample: SensorSample,
        edgeAngle: Double,
        speedMetersPerSecond: Double,
        location: LocationSample?,
        side: SensorSide,
        at date: Date = Date(),
        rawSample: SensorSample? = nil
    ) {
        guard isRunning else { return }
        if let lastSampleTime, date.timeIntervalSince(lastSampleTime) < minSampleInterval {
            return
        }
        lastSampleTime = date
        latestEdgeAnglesBySide[side] = edgeAngle
        latestEdgeAngle = combinedEdgeAngle()
        latestSpeedMetersPerSecond = speedMetersPerSecond
        let edgeAngles = edgeAnglesForRecording()
        let edgeSample = EdgeSample(timestamp: date, leftAngle: edgeAngles.left, rightAngle: edgeAngles.right)
        edgeSamples.append(edgeSample)
        recordedEdgeSamples.append(edgeSample)
        pruneSamples()
        handleEdgeCallout(angle: edgeAngle, speedMetersPerSecond: speedMetersPerSecond)

        if let location {
            trackLocation(location, at: date)
        }

        if side == primarySide || (primarySide == .single && side != .right) {
            latestPrimarySample = sample
            latestPrimarySide = side
        }

        if let primarySample = latestPrimarySample, let primarySide = latestPrimarySide {
            if let result = turnSignalProcessor.process(sample: primarySample, side: primarySide, at: date), result.isValid {
                updateTurnDetection(turnSignal: result.signal, edgeAngle: latestEdgeAngle, location: location, at: date)
            }
        }

        if !isInTurn {
            maybeStoreBackgroundSample(edgeAngles: edgeAngles, at: date)
        }

        if let rawSample {
            latestRawSamplesBySide[side] = rawSample
        } else {
            latestRawSamplesBySide[side] = sample
        }

        if rawDataRecordingEnabled {
            let leftSample = latestRawSamplesBySide[.left] ?? latestRawSamplesBySide[.single]
            let rightSample = latestRawSamplesBySide[.right]
            rawSensorSamples.append(
                RawSensorSample(
                    timestamp: date,
                    leftSample: leftSample,
                    rightSample: rightSample,
                    speedMetersPerSecond: speedMetersPerSecond,
                    latitude: location?.latitude,
                    longitude: location?.longitude,
                    altitude: location?.altitude,
                    horizontalAccuracy: location?.horizontalAccuracy
                )
            )
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

    private func maybeStoreBackgroundSample(edgeAngles: (left: Double?, right: Double?), at date: Date) {
        if let lastBackgroundSampleTime, date.timeIntervalSince(lastBackgroundSampleTime) < backgroundSampleInterval {
            return
        }
        lastBackgroundSampleTime = date
        backgroundSamples.append(
            BackgroundSample(timestamp: date, leftEdgeAngle: edgeAngles.left, rightEdgeAngle: edgeAngles.right)
        )
    }

    private func updateTurnDetection(turnSignal: Double, edgeAngle: Double, location: LocationSample?, at date: Date) {
        let turnOnThreshold = max(turnSettings.turnOnThreshold, adaptiveTurnOnThreshold(for: abs(turnSignal)))
        if isInTurn {
            let edgeAngles = edgeAnglesForRecording()
            currentTurnSamples.append(
                TurnSample(
                    timestamp: date,
                    leftEdgeAngle: edgeAngles.left,
                    rightEdgeAngle: edgeAngles.right,
                    turnSignal: turnSignal
                )
            )
            currentTurnPeakSignal = max(currentTurnPeakSignal, abs(turnSignal))
            let dynamicTurnOffThreshold = max(
                turnSettings.turnOffThreshold,
                currentTurnPeakSignal * turnSettings.turnOffPeakRatio
            )
            let edgeExitThreshold = turnSettings.edgeAngleExitThreshold + turnSettings.edgeAngleExitMargin
            if abs(turnSignal) < dynamicTurnOffThreshold, edgeAngle <= edgeExitThreshold {
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

        if abs(turnSignal) > turnOnThreshold {
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
        currentTurnPeakSignal = abs(turnSignal)
        let edgeAngles = edgeAnglesForRecording()
        currentTurnSamples = [
            TurnSample(
                timestamp: date,
                leftEdgeAngle: edgeAngles.left,
                rightEdgeAngle: edgeAngles.right,
                turnSignal: turnSignal
            )
        ]
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
        let peakEdgeAngle = currentTurnSamples.compactMap(\.peakEdgeAngle).max() ?? 0
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
        currentTurnPeakSignal = 0
    }

    private func adaptiveTurnOnThreshold(for value: Double) -> Double {
        turnSignalHistory.append(value)
        if turnSignalHistory.count > turnSettings.adaptiveWindowSize {
            turnSignalHistory.removeFirst(turnSignalHistory.count - turnSettings.adaptiveWindowSize)
        }
        guard turnSignalHistory.count >= turnSettings.adaptiveMinSamples else { return 0 }
        let median = medianValue(from: turnSignalHistory)
        let deviations = turnSignalHistory.map { abs($0 - median) }
        let mad = medianValue(from: deviations)
        return median + (turnSettings.adaptiveMadMultiplier * mad)
    }

    private func medianValue(from values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    func buildRunRecord(runNumber: Int, date: Date = Date(), calibration: RunCalibration? = nil) -> RunRecord {
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
            edgeSamples: recordedEdgeSamples,
            rawSensorSamples: rawSensorSamples,
            sensorMode: sensorMode,
            calibration: calibration
        )
    }

    private func combinedEdgeAngle() -> Double {
        let available = latestEdgeAnglesBySide
        if available.isEmpty {
            return 0
        }
        let values = available.values
        return values.reduce(0, +) / Double(values.count)
    }

    private func edgeAnglesForRecording() -> (left: Double?, right: Double?) {
        let left = latestEdgeAnglesBySide[.left] ?? latestEdgeAnglesBySide[.single]
        let right = latestEdgeAnglesBySide[.right]
        return (left, right)
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

    private func configureRemoteCommands() {
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.stopCommand.isEnabled = true

        remoteCommandTargets.append(
            remoteCommandCenter.playCommand.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                guard !self.isRunning else { return .success }
                self.startRun(isCalibrated: self.canStartFromRemote)
                return self.isRunning ? .success : .commandFailed
            }
        )

        remoteCommandTargets.append(
            remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                guard self.isRunning else { return .success }
                self.stopRun()
                return .success
            }
        )

        remoteCommandTargets.append(
            remoteCommandCenter.stopCommand.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                guard self.isRunning else { return .success }
                self.stopRun()
                return .success
            }
        )

        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        remoteCommandCenter.playCommand.isEnabled = canStartFromRemote && !isRunning
        remoteCommandCenter.pauseCommand.isEnabled = isRunning
        remoteCommandCenter.stopCommand.isEnabled = isRunning
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Carving Run",
            MPMediaItemPropertyArtist: "Carving Extreem",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isRunning ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed
        ]
        if startDate != nil {
            info[MPMediaItemPropertyPlaybackDuration] = 0
        }
        nowPlayingCenter.nowPlayingInfo = info
        nowPlayingCenter.playbackState = isRunning ? .playing : .paused
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

    private func configureAudioSession() {
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true, options: [])
    }

    private func deactivateAudioSession() {
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private struct TurnSignalResult {
    let signal: Double
    let magnitude: Double
    let isValid: Bool
}

private struct TurnSignalSideState {
    var lastTimestamp: Date?
    var filteredMagnitude: Double?
    var magnitudeHistory: [Double] = []
    var imbalanceCount: Int = 0
    var lastValidMagnitude: Double?
}

private struct TurnSignalProcessor {
    private let settings = TurnSignalFilterSettings()
    private var states: [SensorSide: TurnSignalSideState] = [:]

    mutating func process(sample: SensorSample, side: SensorSide, at timestamp: Date) -> TurnSignalResult? {
        var state = states[side] ?? TurnSignalSideState()
        let previousTimestamp = state.lastTimestamp
        if let previousTimestamp, timestamp == previousTimestamp {
            return nil
        }

        state.lastTimestamp = timestamp
        let accelMagnitude = sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
        let gyroMagnitude = sqrt(sample.gx * sample.gx + sample.gy * sample.gy + sample.gz * sample.gz)
        let otherSide: SensorSide?
        switch side {
        case .left:
            otherSide = .right
        case .right:
            otherSide = .left
        case .single:
            otherSide = nil
        }
        let counterpartMagnitude = otherSide.flatMap { states[$0]?.lastValidMagnitude }

        let isAccelValid = accelMagnitude <= settings.maxAccelG
        let isGyroValid = gyroMagnitude <= settings.maxGyroRad
        let isConsistent = !isImbalanced(gyroMagnitude: gyroMagnitude, counterpartMagnitude: counterpartMagnitude, state: &state)
        let isValid = isAccelValid && isGyroValid && isConsistent

        guard isValid else {
            states[side] = state
            return TurnSignalResult(signal: 0, magnitude: gyroMagnitude, isValid: false)
        }

        let despikedMagnitude = applyHampelFilter(to: gyroMagnitude, history: state.magnitudeHistory)
        state.magnitudeHistory.append(despikedMagnitude)
        if state.magnitudeHistory.count > settings.hampelWindowSize {
            state.magnitudeHistory.removeFirst(state.magnitudeHistory.count - settings.hampelWindowSize)
        }

        let filteredMagnitude = applyLowPassFilter(
            current: despikedMagnitude,
            previous: state.filteredMagnitude,
            previousTimestamp: previousTimestamp,
            currentTimestamp: timestamp,
            cutoffHz: settings.turnLowPassHz
        )
        state.filteredMagnitude = filteredMagnitude
        state.lastValidMagnitude = gyroMagnitude
        states[side] = state

        let sign = sample.gz == 0 ? 0 : (sample.gz > 0 ? 1.0 : -1.0)
        let signal = filteredMagnitude * sign
        return TurnSignalResult(signal: signal, magnitude: filteredMagnitude, isValid: true)
    }

    private func isImbalanced(
        gyroMagnitude: Double,
        counterpartMagnitude: Double?,
        state: inout TurnSignalSideState
    ) -> Bool {
        guard let counterpartMagnitude, counterpartMagnitude > 0 else {
            state.imbalanceCount = 0
            return false
        }
        if gyroMagnitude > counterpartMagnitude * settings.imbalanceRatio {
            state.imbalanceCount += 1
        } else {
            state.imbalanceCount = 0
        }
        return state.imbalanceCount >= settings.imbalanceHoldSamples
    }

    private func applyHampelFilter(to value: Double, history: [Double]) -> Double {
        guard history.count >= settings.hampelMinSamples else {
            return value
        }
        let median = medianValue(from: history)
        let deviations = history.map { abs($0 - median) }
        let mad = medianValue(from: deviations)
        guard mad > 0 else {
            return value
        }
        if abs(value - median) > settings.hampelThreshold * mad {
            return median
        }
        return value
    }

    private func applyLowPassFilter(
        current: Double,
        previous: Double?,
        previousTimestamp: Date?,
        currentTimestamp: Date,
        cutoffHz: Double
    ) -> Double {
        guard let previous else {
            return current
        }
        let dt = max(currentTimestamp.timeIntervalSince(previousTimestamp ?? currentTimestamp), settings.minDeltaTime)
        let rc = 1.0 / (2.0 * Double.pi * cutoffHz)
        let alpha = dt / (rc + dt)
        return previous + alpha * (current - previous)
    }

    private func medianValue(from values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private struct TurnSignalFilterSettings {
    let maxAccelG: Double = 8.0
    let maxGyroRad: Double = 35.0
    let imbalanceRatio: Double = 10.0
    let imbalanceHoldSamples: Int = 3
    let hampelWindowSize: Int = 31
    let hampelMinSamples: Int = 7
    let hampelThreshold: Double = 5.0
    let turnLowPassHz: Double = 6.0
    let minDeltaTime: TimeInterval = 1.0 / 100.0
}

private struct TurnDetectorSettings {
    let turnOnThreshold: Double = 25
    let turnOffThreshold: Double = 15
    let edgeAngleExitThreshold: Double = 5
    let edgeAngleExitMargin: Double = 3
    let turnOffPeakRatio: Double = 0.35
    let turnStartHold: TimeInterval = 0.15
    let turnStopHold: TimeInterval = 0.2
    let minTurnDuration: TimeInterval = 0.4
    let minTurnGap: TimeInterval = 0.3
    let adaptiveWindowSize: Int = 200
    let adaptiveMinSamples: Int = 30
    let adaptiveMadMultiplier: Double = 2.5
}

private extension TurnDirection {
    static func from(signal: Double) -> TurnDirection {
        if signal > 0 { return .right }
        if signal < 0 { return .left }
        return .unknown
    }
}
