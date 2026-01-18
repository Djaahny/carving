//
//  ContentView.swift
//  Carving extreem
//
//  Created by Morten Kirkelund on 18/01/2026.
//

import Charts
import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var client = StreamClient()
    @StateObject private var session = RideSessionViewModel()
    @StateObject private var locationManager = RideLocationManager()
    @StateObject private var runStore = RunDataStore()
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

                    openSavedRunsCard
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
        .onChange(of: session.isRunning) { _, isRunning in
            if isRunning {
                locationManager.startUpdates()
            } else {
                locationManager.stopUpdates()
            }
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationFlowView(client: client)
        }
        .fullScreenCover(isPresented: $showRunSession) {
            RunSessionView(
                session: session,
                client: client,
                locationManager: locationManager,
                runStore: runStore
            )
        }
        .alert("Calibration required", isPresented: $showCalibrationRequired) {
            Button("Start calibration") {
                showCalibration = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Complete the level and edge alignment calibration before starting a run.")
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
                Toggle("Edge angle above \(Int(session.edgeCalloutThreshold))°", isOn: $session.edgeCalloutsEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Edge callout threshold")
                        Spacer()
                        Text("\(Int(session.edgeCalloutThreshold))°")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $session.edgeCalloutThreshold, in: 30...80, step: 1)
                }
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
                    Text("Level boot + edge alignment")
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
                    Text("Yaw ref")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(client.calibrationState.yawReference, specifier: "%.1f")°")
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

    private var openSavedRunsCard: some View {
        NavigationLink(destination: SavedRunsView(runStore: runStore)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open saved runs")
                        .font(.headline)
                    Text("Review past sessions and turns.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

private struct CalibrationFlowView: View {
    enum Step: Int, CaseIterable {
        case level
        case side
        case complete

        var title: String {
            switch self {
            case .level: return "Level the boot"
            case .side: return "Edge the skis"
            case .complete: return "Calibration saved"
            }
        }

        var message: String {
            switch self {
            case .level:
                return "Place the boot flat on the ground and keep it steady. This flat calibration is reused for the next steps, so keep the sensor mounted in its ride position."
            case .side:
                return "Edge the skis 10–20° to each side. This aligns the Y axis (edge rotation) with the boot length. Hold each side steady twice, returning to flat between holds."
            case .complete:
                return "You're ready to ride with calibrated references."
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .level
    @State private var positiveRollPeaks: [Double] = []
    @State private var negativeRollPeaks: [Double] = []
    @State private var positiveYawAngles: [Double] = []
    @State private var negativeYawAngles: [Double] = []
    @State private var currentPositivePeak: Double = 0
    @State private var currentNegativePeak: Double = 0
    @State private var currentPositiveYaw: Double = 0
    @State private var currentNegativeYaw: Double = 0
    @State private var sidePositiveCapturedInHold = false
    @State private var sideNegativeCapturedInHold = false
    @State private var latestEdgeCalibrationAngle: Double = 0
    @State private var sidePositiveProgress: Double = 0
    @State private var sideNegativeProgress: Double = 0
    @State private var isLevelCalibrating = false
    @State private var levelProgress: Double = 0
    @State private var levelStart: Date?
    @State private var levelSamples: [SensorSample] = []
    @State private var sidePositiveHoldStart: Date?
    @State private var sideNegativeHoldStart: Date?
    let client: StreamClient
    private let sideThreshold = 10.0
    private let levelDuration: TimeInterval = 5
    private let sideHoldDuration: TimeInterval = 1.0
    private let sideCaptureTarget = 2

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
            case .side:
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
            case .side:
                VStack(alignment: .leading, spacing: 16) {
                    BootTiltView(angle: displaySideAngle)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Edge alignment")
                            .font(.subheadline.weight(.semibold))
                        Text("Current: \(formattedAngle(displaySideAngle))° • Target: 10–20° each side")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Outside edge")
                                    .font(.footnote.weight(.medium))
                                Spacer()
                                Text(sideCaptureStatusText(for: positiveRollPeaks.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: sawPositiveRoll ? 1 : sidePositiveProgress)

                            HStack {
                                Text("Inside edge")
                                    .font(.footnote.weight(.medium))
                                Spacer()
                                Text(sideCaptureStatusText(for: negativeRollPeaks.count))
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
        case .side:
            break
        case .complete:
            dismiss()
        }
    }

    private func handleSample(_ sample: SensorSample) {
        latestEdgeCalibrationAngle = client.calibrationEdgeAngle(from: sample)
        switch step {
        case .level:
            handleLevelSample(sample)
        case .side:
            detectSideReference(sample: sample, pitch: latestEdgeCalibrationAngle)
        default:
            break
        }
    }
    private func detectSideReference(sample: SensorSample, pitch: Double) {
        let sideAngle = pitch
        let yawAngle = client.edgeYawAngle(from: sample)

        if sideAngle > sideThreshold {
            currentPositivePeak = max(currentPositivePeak, sideAngle)
            if sideAngle == currentPositivePeak {
                currentPositiveYaw = yawAngle
            }
            if sidePositiveHoldStart == nil {
                sidePositiveHoldStart = Date()
            }
            if let holdStart = sidePositiveHoldStart {
                let elapsed = Date().timeIntervalSince(holdStart)
                sidePositiveProgress = min(max(elapsed / sideHoldDuration, 0), 1)
                if elapsed >= sideHoldDuration,
                   !sidePositiveCapturedInHold,
                   positiveRollPeaks.count < sideCaptureTarget {
                    sidePositiveCapturedInHold = true
                    positiveRollPeaks.append(currentPositivePeak)
                    positiveYawAngles.append(currentPositiveYaw)
                }
            }
        } else if sideAngle < -sideThreshold {
            currentNegativePeak = min(currentNegativePeak == 0 ? sideAngle : currentNegativePeak, sideAngle)
            if sideAngle == currentNegativePeak {
                currentNegativeYaw = yawAngle
            }
            if sideNegativeHoldStart == nil {
                sideNegativeHoldStart = Date()
            }
            if let holdStart = sideNegativeHoldStart {
                let elapsed = Date().timeIntervalSince(holdStart)
                sideNegativeProgress = min(max(elapsed / sideHoldDuration, 0), 1)
                if elapsed >= sideHoldDuration,
                   !sideNegativeCapturedInHold,
                   negativeRollPeaks.count < sideCaptureTarget {
                    sideNegativeCapturedInHold = true
                    negativeRollPeaks.append(currentNegativePeak)
                    negativeYawAngles.append(currentNegativeYaw)
                }
            }
        } else {
            resetSideHold()
        }

        guard sawPositiveRoll, sawNegativeRoll else { return }
        let positiveAverage = positiveRollPeaks.reduce(0, +) / Double(positiveRollPeaks.count)
        let negativeAverage = negativeRollPeaks.reduce(0, +) / Double(negativeRollPeaks.count)
        let midpoint = (positiveAverage + negativeAverage) / 2
        let yawSamples = positiveYawAngles + negativeYawAngles
        let yawAverage = yawSamples.reduce(0, +) / Double(max(yawSamples.count, 1))
        client.captureSideReference(angle: midpoint, yaw: yawAverage)
        step = .complete
    }

    private func resetSideTracking() {
        positiveRollPeaks = []
        negativeRollPeaks = []
        positiveYawAngles = []
        negativeYawAngles = []
        currentPositivePeak = 0
        currentNegativePeak = 0
        currentPositiveYaw = 0
        currentNegativeYaw = 0
        sidePositiveCapturedInHold = false
        sideNegativeCapturedInHold = false
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

    private var displaySideAngle: Double {
        latestEdgeCalibrationAngle
    }

    private func resetSideHold() {
        sidePositiveHoldStart = nil
        sideNegativeHoldStart = nil
        currentPositivePeak = 0
        currentNegativePeak = 0
        currentPositiveYaw = 0
        currentNegativeYaw = 0
        sidePositiveCapturedInHold = false
        sideNegativeCapturedInHold = false
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
        step = .side
    }

    private var sawPositiveRoll: Bool {
        positiveRollPeaks.count >= sideCaptureTarget
    }

    private var sawNegativeRoll: Bool {
        negativeRollPeaks.count >= sideCaptureTarget
    }

    private func sideCaptureStatusText(for count: Int) -> String {
        if count >= sideCaptureTarget {
            return "Captured \(sideCaptureTarget)/\(sideCaptureTarget)"
        }
        return String(
            format: "Hold %.1fs (%d/%d)",
            sideHoldDuration,
            count,
            sideCaptureTarget
        )
    }
}

private struct RunSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: RideSessionViewModel
    @ObservedObject var client: StreamClient
    @ObservedObject var locationManager: RideLocationManager
    @ObservedObject var runStore: RunDataStore
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
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
                            LineMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                                .interpolationMethod(.catmullRom)
                            AreaMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                                .foregroundStyle(.linearGradient(
                                    colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        }
                        .chartYScale(domain: 0...90)
                        .frame(height: 220)

                        runStats

                        HStack {
                            Label("Turn count", systemImage: "repeat")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(session.turnCount)")
                                .font(.headline.weight(.semibold))
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    if session.isStopped {
                        RunAnalysisView(run: session.buildRunRecord(runNumber: runStore.runNumber(for: Date())))
                    }
                }
                .padding()
            }
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if session.isRunning {
                        Button("Stop") {
                            session.stopRun()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                if session.isStopped {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Save") {
                            saveRun()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .interactiveDismissDisabled(session.isRunning)
            .onReceive(client.$latestEdgeAngle) { angle in
                guard session.isRunning, let sample = client.latestSample else { return }
                let speed = max(locationManager.speedMetersPerSecond, 0)
                let location = locationManager.latestLocation.map { location in
                    LocationSample(
                    timestamp: location.timestamp,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude,
                    speed: location.speed,
                    horizontalAccuracy: location.horizontalAccuracy
                )
            }
                session.ingest(
                    sample: sample,
                    edgeAngle: angle,
                    speedMetersPerSecond: speed,
                    location: location
                )
            }
            .onReceive(locationManager.$latestLocation) { location in
                guard session.isRunning, let location else { return }
                let locationSample = LocationSample(
                    timestamp: location.timestamp,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude,
                    speed: location.speed,
                    horizontalAccuracy: location.horizontalAccuracy
                )
                session.ingestLocation(locationSample)
            }
        .alert("Save failed", isPresented: Binding(get: { saveError != nil }, set: { _ in saveError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    private var runStats: some View {
        let speed = max(locationManager.speedMetersPerSecond, 0)
        let speedKmh = speed * 3.6
        let peakAngle = session.edgeSamples.map(\.angle).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Live stats")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                statTile(title: "Current edge", value: "\(Int(session.latestEdgeAngle))°")
                statTile(title: "Peak (10s)", value: "\(Int(peakAngle))°")
            }
            HStack(spacing: 16) {
                statTile(title: "Speed", value: String(format: "%.1f km/h", speedKmh))
                statTile(title: "Edge alert", value: "\(Int(session.edgeCalloutThreshold))°")
            }
            if !locationManager.status.isEmpty {
                Text(locationManager.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func saveRun() {
        do {
            let runNumber = runStore.runNumber(for: Date())
            let run = session.buildRunRecord(runNumber: runNumber)
            try runStore.save(run: run)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct BootAngleCard: View {
    let angle: Double
    let tiltAngle: Double
    let forwardAngle: Double
    @State private var show3DView = false

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
                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("3D view", isOn: $show3DView)
                        .font(.footnote.weight(.semibold))
                        .toggleStyle(.switch)
                    Text("\(Int(angle))°")
                        .font(.headline.weight(.semibold))
                }
            }

            Group {
                if show3DView {
                    Boot3DView(pitchAngle: forwardAngle, rollAngle: tiltAngle)
                } else {
                    BootTiltView(angle: tiltAngle)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )

            if show3DView {
                HStack {
                    Text("Forward/Aft: \(Int(forwardAngle))°")
                    Spacer()
                    Text("Side: \(Int(tiltAngle))°")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct BootTiltView: View {
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

            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 2, height: 110)

            Capsule()
                .fill(Color.blue.opacity(0.6))
                .frame(width: 150, height: 18)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

            Text("\(Int(angle))°")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .offset(y: 60)
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

private struct Boot3DView: View {
    let pitchAngle: Double
    let rollAngle: Double

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
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 150, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .offset(y: 6)

                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .offset(y: -18)
            }
            .rotation3DEffect(.degrees(-pitchAngle), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(rollAngle), axis: (x: 0, y: 0, z: 1))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pitchAngle)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: rollAngle)
        }
        .padding(.vertical, 8)
    }
}

private extension ContentView {
    var bootAngleCard: some View {
        let pitchAngle = client.latestSample.map { client.pitchRoll(from: $0).pitch } ?? 0
        return BootAngleCard(
            angle: client.latestEdgeAngle,
            tiltAngle: client.latestSignedEdgeAngle,
            forwardAngle: pitchAngle
        )
    }
}
