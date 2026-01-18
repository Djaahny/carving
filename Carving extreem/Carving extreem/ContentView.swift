//
//  ContentView.swift
//  Carving extreem
//
//  Created by Morten Kirkelund on 18/01/2026.
//

import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var client = StreamClient()
    @StateObject private var session = RideSessionViewModel()
    @State private var showCalibration = false
    @State private var didAutoConnect = false
    @State private var showCalibrationRequired = false
    @State private var showRunSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    welcomeCard

                    bootAngleCard

                    connectionCard

                    runControlCard

                    calibrationCard
                }
                .padding()
            }
            .navigationTitle("Carving Extreem")
        }
        .onDisappear {
            client.disconnect()
        }
        .onAppear {
            if !didAutoConnect, client.lastKnownSensorName != nil {
                didAutoConnect = true
                client.connect()
            }
        }
        .onReceive(client.$latestEdgeAngle) { angle in
            guard session.isRunning, client.latestSample != nil else { return }
            session.ingest(edgeAngle: angle)
        }
        .onChange(of: session.isRunning) { _, isRunning in
            showRunSession = isRunning
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationFlowView(client: client)
        }
        .fullScreenCover(isPresented: $showRunSession) {
            RunSessionView(session: session)
        }
        .alert("Calibration required", isPresented: $showCalibrationRequired) {
            Button("Start calibration") {
                showCalibration = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Complete the level, forward, and side calibration before starting a run.")
        }
    }

    private var welcomeCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)
                .overlay(
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Welcome back")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("AI-generated alpine concept art")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 12) {
                            Label("Last sensor", systemImage: "sensor.tag.radiowaves.forward")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(client.lastKnownSensorName ?? "None saved yet")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20),
                    alignment: .bottomLeading
                )
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sensor connection")
                    .font(.headline)
                Spacer()
                Text(client.isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(client.isConnected ? .green : .secondary)
            }

            Text(client.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(client.isConnected ? "Disconnect" : "Connect") {
                    if client.isConnected {
                        client.disconnect()
                    } else {
                        client.connect()
                    }
                }
                .buttonStyle(.borderedProminent)

                if let lastSensor = client.lastKnownSensorName {
                    Text("Auto: \(lastSensor)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Auto reconnect ready")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var runControlCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride control")
                        .font(.headline)
                    Text("Start when you unload and stop at the lift line.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.isRunning ? timeString(from: session.elapsed) : "Ready")
                    .font(.headline.weight(.semibold))
            }

            Button(session.isRunning ? "Running" : "Start Run") {
                guard !session.isRunning else { return }
                if client.calibrationState.isCalibrated {
                    session.startRun(isCalibrated: true)
                    showRunSession = true
                } else {
                    showCalibrationRequired = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isRunning ? .gray : .blue)
            .disabled(session.isRunning || !client.calibrationState.isCalibrated)

            VStack(alignment: .leading, spacing: 8) {
                Text("Audio callouts")
                    .font(.subheadline.weight(.semibold))
                Toggle("Time every 30 seconds", isOn: $session.timeCalloutsEnabled)
                Toggle("Edge angle above 60°", isOn: $session.edgeCalloutsEnabled)
            }
            .font(.subheadline)

            if !client.calibrationState.isCalibrated {
                Label("Calibration required before starting a run.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibration")
                        .font(.headline)
                    Text("Level boot + forward/side reference")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start") {
                    showCalibration = true
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Forward ref")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(client.calibrationState.forwardReference, specifier: "%.1f")°")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Side ref")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(client.calibrationState.sideReference, specifier: "%.1f")°")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zeroed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(client.calibrationState.isCalibrated ? "Complete" : "Needed")
                        .font(.headline)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Flat axis (X / Y / Z)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        format: "%.2f g / %.2f g / %.2f g",
                        client.calibrationState.accelOffset[0],
                        client.calibrationState.accelOffset[1],
                        client.calibrationState.accelOffset[2]
                    )
                )
                .font(.subheadline.weight(.medium))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}

private struct CalibrationFlowView: View {
    enum Step: Int, CaseIterable {
        case level
        case forward
        case side
        case complete

        var title: String {
            switch self {
            case .level: return "Level the boot"
            case .forward: return "Tilt forward"
            case .side: return "Tilt to outside edge"
            case .complete: return "Calibration saved"
            }
        }

        var message: String {
            switch self {
            case .level:
                return "Place the boot flat on the ground and keep it steady."
            case .forward:
                return "Tip the boot forward onto the toe (up to 45°). Hold steady for 1.5s, return to flat, then repeat to confirm."
            case .side:
                return "Rock the boot side to side up to 45° each way. Keep the forward/back tilt within ~10° while holding each edge."
            case .complete:
                return "You're ready to ride with calibrated references."
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .level
    @State private var forwardStabilityCount = 0
    @State private var forwardCaptureCount = 0
    @State private var forwardNeedsReset = false
    @State private var forwardAxisCandidate: Axis?
    @State private var maxPositiveRoll: Double = 0
    @State private var maxNegativeRoll: Double = 0
    @State private var sawPositiveRoll = false
    @State private var sawNegativeRoll = false
    @State private var latestPitch: Double = 0
    @State private var latestRoll: Double = 0
    @State private var forwardHoldProgress: Double = 0
    @State private var sidePositiveProgress: Double = 0
    @State private var sideNegativeProgress: Double = 0
    @State private var isLevelCalibrating = false
    @State private var levelProgress: Double = 0
    @State private var levelStart: Date?
    @State private var levelSamples: [SensorSample] = []
    @State private var forwardHoldStart: Date?
    @State private var sidePositiveHoldStart: Date?
    @State private var sideNegativeHoldStart: Date?
    let client: StreamClient
    private let forwardThreshold = 18.0
    private let sideThreshold = 12.0
    private let stabilityTarget = 6
    private let levelDuration: TimeInterval = 5
    private let forwardHoldDuration: TimeInterval = 1.5
    private let sideHoldDuration: TimeInterval = 1.0
    private let orthogonalTolerance = 10.0
    private let forwardFlatTolerance = 6.0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(step.title)
                    .font(.title2.bold())
                Text(step.message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                calibrationActionView
            }
            .padding()
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onReceive(client.$latestSample) { sample in
            guard let sample else { return }
            handleSample(sample)
        }
    }

    private var calibrationActionView: some View {
        Group {
            switch step {
            case .level:
                if isLevelCalibrating {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: levelProgress)
                        Text("Averaging level position… \(Int(levelProgress * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Start 5s level capture") {
                        handlePrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .forward, .side:
                calibrationLiveView
            case .complete:
                Button("Done") {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var calibrationLiveView: some View {
        Group {
            switch step {
            case .forward:
                VStack(alignment: .leading, spacing: 16) {
                    BootPitchView(angle: displayForwardAngle)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Toe-to-flat calibration")
                            .font(.subheadline.weight(.semibold))
                        Text("Current: \(formattedAngle(displayForwardAngle))° • Target: 20–45°")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ProgressView(value: forwardHoldProgress)
                        Text(forwardStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            case .side:
                VStack(alignment: .leading, spacing: 16) {
                    Boot3DView(angle: displaySideAngle)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Side-to-side calibration")
                            .font(.subheadline.weight(.semibold))
                        Text("Current: \(formattedAngle(displaySideAngle))° • Target: 20–45° each side")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Outside edge")
                                    .font(.footnote.weight(.medium))
                                Spacer()
                                Text(sawPositiveRoll ? "Captured" : "Hold \(sideHoldDuration, specifier: "%.1f")s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: sawPositiveRoll ? 1 : sidePositiveProgress)

                            HStack {
                                Text("Inside edge")
                                    .font(.footnote.weight(.medium))
                                Spacer()
                                Text(sawNegativeRoll ? "Captured" : "Hold \(sideHoldDuration, specifier: "%.1f")s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: sawNegativeRoll ? 1 : sideNegativeProgress)
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .level:
            startLevelCalibration()
        case .forward:
            break
        case .side:
            break
        case .complete:
            dismiss()
        }
    }

    private func handleSample(_ sample: SensorSample) {
        let pitchRoll = client.pitchRoll(from: sample)
        latestPitch = pitchRoll.pitch
        latestRoll = pitchRoll.roll
        switch step {
        case .level:
            handleLevelSample(sample)
        case .forward:
            detectForwardReference(pitch: latestPitch, roll: latestRoll)
        case .side:
            detectSideReference(pitch: latestPitch, roll: latestRoll)
        default:
            break
        }
    }

    private func detectForwardReference(pitch: Double, roll: Double) {
        if forwardNeedsReset {
            if abs(pitch) <= forwardFlatTolerance, abs(roll) <= forwardFlatTolerance {
                forwardNeedsReset = false
                forwardHoldStart = nil
                forwardHoldProgress = 0
            }
            return
        }

        guard let axis = selectedForwardAxis(pitch: pitch, roll: roll) else {
            resetForwardHold()
            return
        }

        if let candidate = forwardAxisCandidate, candidate != axis {
            resetForwardTracking()
            return
        }

        let axisAngle = axis == .pitch ? pitch : roll
        let orthogonalAngle = axis == .pitch ? roll : pitch
        guard abs(orthogonalAngle) <= orthogonalTolerance else {
            resetForwardHold()
            return
        }

        guard abs(axisAngle) > forwardThreshold else {
            resetForwardHold()
            return
        }

        forwardAxisCandidate = axis
        forwardStabilityCount += 1
        let now = Date()
        if forwardHoldStart == nil {
            forwardHoldStart = now
        }
        guard let holdStart = forwardHoldStart else { return }
        forwardHoldProgress = min(max(now.timeIntervalSince(holdStart) / forwardHoldDuration, 0), 1)
        if forwardStabilityCount >= stabilityTarget, now.timeIntervalSince(holdStart) >= forwardHoldDuration {
            forwardCaptureCount += 1
            if forwardCaptureCount < 2 {
                forwardNeedsReset = true
                resetForwardHold()
                return
            }
            client.captureForwardReference(axis: axis, angle: axisAngle, pitch: pitch, roll: roll)
            resetSideTracking()
            step = .side
        }
    }

    private func detectSideReference(pitch: Double, roll: Double) {
        let sideAxis = client.calibrationState.sideAxis
        let sideAngle = sideAxis == .pitch ? pitch : roll
        let orthogonalAngle = sideAxis == .pitch ? roll : pitch
        guard abs(orthogonalAngle) <= orthogonalTolerance else {
            resetSideHold()
            return
        }

        if sideAngle > sideThreshold {
            maxPositiveRoll = max(maxPositiveRoll, sideAngle)
            if sidePositiveHoldStart == nil {
                sidePositiveHoldStart = Date()
            }
            if let holdStart = sidePositiveHoldStart,
               Date().timeIntervalSince(holdStart) >= sideHoldDuration {
                sawPositiveRoll = true
            }
            if let holdStart = sidePositiveHoldStart {
                sidePositiveProgress = min(max(Date().timeIntervalSince(holdStart) / sideHoldDuration, 0), 1)
            }
        } else if sideAngle < -sideThreshold {
            maxNegativeRoll = min(maxNegativeRoll, sideAngle)
            if sideNegativeHoldStart == nil {
                sideNegativeHoldStart = Date()
            }
            if let holdStart = sideNegativeHoldStart,
               Date().timeIntervalSince(holdStart) >= sideHoldDuration {
                sawNegativeRoll = true
            }
            if let holdStart = sideNegativeHoldStart {
                sideNegativeProgress = min(max(Date().timeIntervalSince(holdStart) / sideHoldDuration, 0), 1)
            }
        } else {
            resetSideHold()
        }

        guard sawPositiveRoll, sawNegativeRoll else { return }
        let midpoint = (maxPositiveRoll + maxNegativeRoll) / 2
        client.captureSideReference(angle: midpoint)
        step = .complete
    }

    private func resetSideTracking() {
        forwardStabilityCount = 0
        forwardCaptureCount = 0
        forwardNeedsReset = false
        forwardAxisCandidate = nil
        forwardHoldStart = nil
        forwardHoldProgress = 0
        maxPositiveRoll = 0
        maxNegativeRoll = 0
        sawPositiveRoll = false
        sawNegativeRoll = false
        sidePositiveHoldStart = nil
        sideNegativeHoldStart = nil
        sidePositiveProgress = 0
        sideNegativeProgress = 0
    }

    private func startLevelCalibration() {
        isLevelCalibrating = true
        levelProgress = 0
        levelSamples = []
        levelStart = Date()
    }

    private func formattedAngle(_ angle: Double) -> String {
        String(format: "%.1f", angle)
    }

    private var displayForwardAngle: Double {
        let axis = forwardAxisCandidate ?? (abs(latestPitch) >= abs(latestRoll) ? .pitch : .roll)
        return axis == .pitch ? latestPitch : latestRoll
    }

    private var displaySideAngle: Double {
        let axis = client.calibrationState.sideAxis
        return axis == .pitch ? latestPitch : latestRoll
    }

    private var forwardStatusText: String {
        if forwardNeedsReset {
            return "Return to flat to confirm."
        }
        if forwardCaptureCount == 1 {
            return forwardHoldProgress >= 1 ? "Forward reference confirmed." : "Hold steady again for \(forwardHoldDurationText)s"
        }
        return forwardHoldProgress >= 1 ? "Forward reference captured." : "Hold steady for \(forwardHoldDurationText)s"
    }

    private var forwardHoldDurationText: String {
        String(format: "%.1f", forwardHoldDuration)
    }

    private func selectedForwardAxis(pitch: Double, roll: Double) -> Axis? {
        let pitchCandidate = abs(pitch) >= forwardThreshold && abs(roll) <= orthogonalTolerance
        let rollCandidate = abs(roll) >= forwardThreshold && abs(pitch) <= orthogonalTolerance
        if pitchCandidate && !rollCandidate {
            return .pitch
        }
        if rollCandidate && !pitchCandidate {
            return .roll
        }
        return nil
    }

    private func resetForwardHold() {
        forwardStabilityCount = 0
        forwardHoldStart = nil
        forwardHoldProgress = 0
    }

    private func resetForwardTracking() {
        forwardStabilityCount = 0
        forwardCaptureCount = 0
        forwardNeedsReset = false
        forwardAxisCandidate = nil
        forwardHoldStart = nil
        forwardHoldProgress = 0
    }

    private func resetSideHold() {
        sidePositiveHoldStart = nil
        sideNegativeHoldStart = nil
        if !sawPositiveRoll {
            sidePositiveProgress = 0
        }
        if !sawNegativeRoll {
            sideNegativeProgress = 0
        }
    }

    private func handleLevelSample(_ sample: SensorSample) {
        guard isLevelCalibrating, let start = levelStart else { return }
        levelSamples.append(sample)
        let elapsed = Date().timeIntervalSince(start)
        levelProgress = min(max(elapsed / levelDuration, 0), 1)
        guard elapsed >= levelDuration else { return }
        client.captureZeroCalibration(samples: levelSamples)
        isLevelCalibrating = false
        resetSideTracking()
        step = .forward
    }
}

private struct RunSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = RideLocationManager()
    let session: RideSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Run mode")
                                .font(.title2.bold())
                            Text("Edge angle (accelerometer-based)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeString(from: session.elapsed))
                            .font(.headline.weight(.semibold))
                    }

                    Chart(session.edgeSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Angle", sample.angle)
                        )
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Angle", sample.angle)
                        )
                        .foregroundStyle(.linearGradient(
                            colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                    .chartYScale(domain: 0...90)
                    .frame(height: 220)

                    runStats
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Spacer()
            }
            .padding()
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Stop") {
                        session.stopRun()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .onAppear {
            locationManager.startUpdates()
        }
        .onDisappear {
            locationManager.stopUpdates()
        }
        .interactiveDismissDisabled()
    }

    private var runStats: some View {
        let speed = max(locationManager.speedMetersPerSecond, 0)
        let speedKmh = speed * 3.6
        return VStack(alignment: .leading, spacing: 8) {
            Text("Speed")
                .font(.subheadline.weight(.semibold))
            Text(String(format: "%.1f km/h", speedKmh))
                .font(.title3.weight(.semibold))
            if !locationManager.status.isEmpty {
                Text(locationManager.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct BootAngleCard: View {
    let angle: Double
    let tiltAngle: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Boot edge angle")
                        .font(.headline)
                    Text("Live side tilt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(angle))°")
                    .font(.headline.weight(.semibold))
            }

            Boot3DView(angle: tiltAngle)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct Boot3DView: View {
    let angle: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .padding(12)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 90, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .offset(y: -10)

                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 120, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .offset(y: 40)

                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.45))
                    .frame(width: 130, height: 24)
                    .offset(y: 70)
            }
            .rotation3DEffect(.degrees(-12), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 0, z: 1))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: angle)
        }
        .padding(.vertical, 8)
    }
}

private struct BootPitchView: View {
    let angle: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .padding(12)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .offset(y: -10)

                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 140, height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .offset(y: 30)

                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.45))
                    .frame(width: 150, height: 20)
                    .offset(y: 55)
            }
            .rotation3DEffect(.degrees(12), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(-angle), axis: (x: 1, y: 0, z: 0))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: angle)
        }
        .padding(.vertical, 8)
    }
}

private extension ContentView {
    var bootAngleCard: some View {
        BootAngleCard(angle: client.latestEdgeAngle, tiltAngle: client.latestSignedEdgeAngle)
    }
}
