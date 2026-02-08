//
//  ContentView.swift
//  Carving extreem
//
//  Created by Morten Kirkelund on 18/01/2026.
//

import Charts
import Combine
import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var sensorAClient = StreamClient(storageSuffix: "A")
    @StateObject private var sensorBClient = StreamClient(storageSuffix: "B")
    @StateObject private var session = RideSessionViewModel()
    @StateObject private var locationManager = RideLocationManager()
    @StateObject private var runStore = RunDataStore()
    @StateObject private var metricStore = MetricSelectionStore()
    @StateObject private var assignmentStore = SensorAssignmentStore()
    @AppStorage("sensorMode") private var sensorModeRaw = SensorMode.single.rawValue
    @State private var showCalibrationRequired = false
    @State private var showMetricSelection = false
    @State private var showSensorAssignment = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var calibrationTarget: CalibrationTarget?
    @State private var didAutoConnect = false
    @State private var showRunSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    welcomeCard

                    bootAngleCard

                    sensorSetupCard

                    connectionCard

                    runControlCard

                    calibrationCard

                    openSavedRunsCard

                    metricsCard
                }
                .padding()
            }
            .navigationTitle("Carving Extreem")
        }
        .onAppear {
            guard !didAutoConnect else { return }
            didAutoConnect = true
            if sensorAClient.lastKnownSensorName != nil {
                sensorAClient.connect()
            }
            if sensorMode == .dual, sensorBClient.lastKnownSensorName != nil {
                sensorBClient.connect()
            }
            session.canStartFromRemote = isCalibratedForRun
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if sensorAClient.lastKnownSensorName != nil {
                    sensorAClient.connect()
                }
                if sensorMode == .dual, sensorBClient.lastKnownSensorName != nil {
                    sensorBClient.connect()
                }
            case .background:
                guard !session.isRunning else { return }
                sensorAClient.disconnect()
                sensorBClient.disconnect()
            default:
                break
            }
        }
        .onChange(of: session.isRunning) { _, isRunning in
            if isRunning {
                locationManager.startUpdates()
            } else {
                locationManager.stopUpdates()
            }
        }
        .onChange(of: isCalibratedForRun) { _, newValue in
            session.canStartFromRemote = newValue
        }
        .onChange(of: sensorMode) { _, newValue in
            if newValue == .dual, sensorBClient.lastKnownSensorName != nil {
                sensorBClient.connect()
            }
            if newValue == .single {
                sensorBClient.disconnect()
            }
        }
        .sheet(item: $calibrationTarget) { target in
            CalibrationFlowView(client: target.client, sensorLabel: target.label)
        }
        .fullScreenCover(isPresented: $showRunSession) {
            RunSessionView(
                session: session,
                primaryClient: primaryClient,
                secondaryClient: secondaryClient,
                sensorMode: sensorMode,
                assignmentStore: assignmentStore,
                locationManager: locationManager,
                runStore: runStore
            )
        }
        .sheet(isPresented: $showMetricSelection) {
            MetricSelectionView(metricStore: metricStore)
        }
        .sheet(isPresented: $showSensorAssignment) {
            SensorAssignmentView(
                clientA: sensorAClient,
                clientB: sensorBClient,
                assignmentStore: assignmentStore
            )
        }
        .alert("Calibration required", isPresented: $showCalibrationRequired) {
            Button("Start calibration") {
                openCalibration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Complete the boot calibration before starting a run.")
        }
        .environmentObject(metricStore)
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sensorLabel(for: sensorAClient))
                                if sensorMode == .dual {
                                    Text(sensorLabel(for: sensorBClient))
                                }
                            }
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
            Text("Sensor connection")
                .font(.headline)

            if sensorMode == .dual {
                sensorConnectionRow(title: "Sensor A", client: sensorAClient)
                sensorConnectionRow(title: "Sensor B", client: sensorBClient)
            } else {
                sensorConnectionRow(title: "Sensor", client: primaryClient)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func sensorConnectionRow(title: String, client: StreamClient) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(client.isConnected ? "Connected" : "Disconnected")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(client.isConnected ? .green : .secondary)
            }

            Text(client.status)
                .font(.footnote)
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
                if isCalibratedForRun {
                    session.sensorMode = sensorMode
                    session.primarySide = sensorMode == .dual ? .left : .single
                    session.startRun(isCalibrated: true)
                    showRunSession = true
                } else {
                    showCalibrationRequired = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isRunning ? .gray : .blue)
            .disabled(session.isRunning || !isCalibratedForRun)

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Recording")
                    .font(.subheadline.weight(.semibold))
                Toggle("Record raw sensor data", isOn: $session.rawDataRecordingEnabled)
            }

            if !isCalibratedForRun {
                Label("Calibration required before starting a run.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var sensorSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sensor setup")
                .font(.headline)

            Picker("Mode", selection: sensorModeBinding) {
                ForEach(SensorMode.allCases) { mode in
                    Text(mode == .single ? "Single sensor" : "Dual sensors")
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if sensorMode == .dual {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assignments")
                        .font(.subheadline.weight(.semibold))
                    Text("Left: \(assignedSensorLabel(for: .left))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Right: \(assignedSensorLabel(for: .right))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Identify left/right by stamping") {
                        showSensorAssignment = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Use one sensor for live metrics and recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    Text("3D boot alignment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sensorMode == .dual {
                    Button("Assign sensors") {
                        showSensorAssignment = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Start") {
                        openCalibration()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if sensorMode == .dual {
                Text("Calibrate each boot separately for accurate left/right tracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                calibrationStatusRow(title: "Left sensor", client: leftClient ?? sensorAClient)
                calibrationStatusRow(title: "Right sensor", client: rightClient ?? sensorBClient)
                HStack {
                    Button("Calibrate left") {
                        openCalibration(for: .left)
                    }
                    .buttonStyle(.bordered)
                    Button("Calibrate right") {
                        openCalibration(for: .right)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                calibrationStatusRow(title: "Sensor", client: primaryClient)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func calibrationStatusRow(title: String, client: StreamClient) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accel scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(client.calibrationState.accelScale, specifier: "%.3f")")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gyro bias")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: "%.2f / %.2f / %.2f",
                            client.calibrationState.gyroBias[0],
                            client.calibrationState.gyroBias[1],
                            client.calibrationState.gyroBias[2]
                        )
                    )
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibrated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(client.calibrationState.isCalibrated ? "Complete" : "Needed")
                        .font(.headline)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Boot up axis (sensor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        format: "%.2f / %.2f / %.2f",
                        client.calibrationState.zAxis[0],
                        client.calibrationState.zAxis[1],
                        client.calibrationState.zAxis[2]
                    )
                )
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var sensorModeBinding: Binding<SensorMode> {
        Binding(
            get: { sensorMode },
            set: { newValue in
                sensorMode = newValue
                if newValue == .single {
                    assignmentStore.clear()
                }
            }
        )
    }

    private var sensorMode: SensorMode {
        get { SensorMode(rawValue: sensorModeRaw) ?? .single }
        nonmutating set { sensorModeRaw = newValue.rawValue }
    }

    private var primaryClient: StreamClient {
        if sensorMode == .dual {
            return leftClient ?? sensorAClient
        }
        return sensorAClient
    }

    private var secondaryClient: StreamClient? {
        guard sensorMode == .dual else { return nil }
        let fallback = primaryClient === sensorAClient ? sensorBClient : sensorAClient
        return rightClient ?? fallback
    }

    private var leftClient: StreamClient? {
        guard let identifier = assignmentStore.leftSensorIdentifier else { return nil }
        return client(for: identifier)
    }

    private var rightClient: StreamClient? {
        guard let identifier = assignmentStore.rightSensorIdentifier else { return nil }
        return client(for: identifier)
    }

    private func client(for identifier: String) -> StreamClient? {
        if sensorAClient.connectedIdentifier == identifier { return sensorAClient }
        if sensorBClient.connectedIdentifier == identifier { return sensorBClient }
        return nil
    }

    private var isCalibratedForRun: Bool {
        if sensorMode == .dual {
            let leftCalibrated = (leftClient ?? sensorAClient).calibrationState.isCalibrated
            let rightCalibrated = (rightClient ?? sensorBClient).calibrationState.isCalibrated
            return leftCalibrated && rightCalibrated
        }
        return primaryClient.calibrationState.isCalibrated
    }

    private func openCalibration() {
        calibrationTarget = CalibrationTarget(label: "Sensor", client: primaryClient)
    }

    private func openCalibration(for side: SensorSide) {
        switch side {
        case .left:
            calibrationTarget = CalibrationTarget(label: "Left sensor", client: leftClient ?? sensorAClient)
        case .right:
            calibrationTarget = CalibrationTarget(label: "Right sensor", client: rightClient ?? sensorBClient)
        case .single:
            calibrationTarget = CalibrationTarget(label: "Sensor", client: primaryClient)
        }
    }

    private func sensorLabel(for client: StreamClient) -> String {
        client.lastKnownSensorName ?? "None saved yet"
    }

    private func assignedSensorLabel(for side: SensorSide) -> String {
        let client = side == .left ? leftClient : rightClient
        if let client {
            return client.lastKnownSensorName ?? client.connectedIdentifier ?? "Unknown"
        }
        return "Unassigned"
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

    private var metricsCard: some View {
        Button {
            showMetricSelection = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Metric visibility")
                        .font(.headline)
                    Text("Customize live + recording stats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
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

private struct CalibrationTarget: Identifiable {
    let id = UUID()
    let label: String
    let client: StreamClient
}

private struct CalibrationFlowView: View {
    enum Step: Int, CaseIterable {
        case stationary
        case forward
        case forefoot
        case complete

        var title: String {
            switch self {
            case .stationary: return "Stand still"
            case .forward: return "Tilt to each edge"
            case .forefoot: return "Lift the forefoot"
            case .complete: return "Calibration saved"
            }
        }

        var message: String {
            switch self {
            case .stationary:
                return "Stand still for about 2 seconds with the boot flat. Small sways are ok, but try to keep the boot steady so we can learn gravity and gyro bias."
            case .forward:
                return """
                Apply the flat calibration from step 1, then start step 2. Tilt to one edge and hold for 2 seconds while keeping pitch within ±15°. Then tilt to the other edge and hold for another 2 seconds. We use the two edge holds to lock in the transverse axis.
                """
            case .forefoot:
                return """
                Step 3: lift the forefoot into the air while keeping the heel down. Hold the position for 2 seconds so we can determine front vs. back. The exact angle doesn't matter—just make sure the boot is clearly tipped forward.
                """
            case .complete:
                return "You're ready to ride with calibrated boot axes."
            }
        }
    }

    enum ForwardPhase {
        case firstEdge
        case secondEdge
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .stationary
    @State private var isStationaryCapturing = false
    @State private var stationaryProgress: Double = 0
    @State private var stationaryStart: Date?
    @State private var stationarySamples: [SensorSample] = []
    @State private var isForwardCapturing = false
    @State private var forwardProgress: Double = 0
    @State private var forwardPhase: ForwardPhase = .firstEdge
    @State private var forwardHoldStart: Date?
    @State private var forwardHoldDirection: Double?
    @State private var edgeOneSamples: [SensorSample] = []
    @State private var edgeTwoSamples: [SensorSample] = []
    @State private var isForefootCapturing = false
    @State private var forefootProgress: Double = 0
    @State private var forefootHoldStart: Date?
    @State private var forefootSamples: [SensorSample] = []
    @State private var calibrationError: String?
    @State private var livePitch: Double = 0
    @State private var liveRoll: Double = 0
    @State private var hasFilteredPitchRoll = false
    let client: StreamClient
    let sensorLabel: String
    private let stationaryDuration: TimeInterval = 2.0
    private let forwardHoldDuration: TimeInterval = 2.0
    private let pitchTolerance: Double = 15.0
    private let rollHoldThreshold: Double = 20.0
    private let forefootPitchThreshold: Double = 8.0
    private let calibrationFilterAlpha: Double = 0.1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(step.title)
                    .font(.title2.bold())
                Text(step.message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                calibrationVisual

                Spacer()

                calibrationActionView
            }
            .padding()
            .navigationTitle("\(sensorLabel) calibration")
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
            let pitchRoll = client.pitchRoll(from: sample)
            if !hasFilteredPitchRoll {
                livePitch = pitchRoll.pitch
                liveRoll = pitchRoll.roll
                hasFilteredPitchRoll = true
            } else {
                livePitch = livePitch * (1 - calibrationFilterAlpha) + pitchRoll.pitch * calibrationFilterAlpha
                liveRoll = liveRoll * (1 - calibrationFilterAlpha) + pitchRoll.roll * calibrationFilterAlpha
            }
            handleSample(sample)
        }
        .alert("Calibration failed", isPresented: Binding(get: { calibrationError != nil }, set: { _ in calibrationError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calibrationError ?? "Unknown error")
        }
    }

    private var calibrationVisual: some View {
        Group {
            if step == .complete {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Boot3DView(pitchAngle: livePitch, rollAngle: liveRoll)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        )

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Live")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Pitch \(Int(livePitch))°")
                            Text("Roll \(Int(liveRoll))°")
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            switch step {
                            case .forward:
                                Text("Pitch ±15°")
                                Text("Roll ±25°")
                            case .forefoot:
                                Text("Pitch: lift forefoot")
                                Text("Roll: any")
                            default:
                                Text("Pitch 0°")
                                Text("Roll 0°")
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text(calibrationVisualHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var calibrationActionView: some View {
        Group {
            switch step {
            case .stationary:
                if isStationaryCapturing {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: stationaryProgress)
                        Text("Capturing stillness… \(Int(stationaryProgress * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Start 2s still capture") {
                        handlePrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .forward:
                if isForwardCapturing {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(forwardPhase == .firstEdge ? "Edge 1 hold" : "Edge 2 hold")
                                .font(.subheadline.weight(.semibold))
                            ProgressView(value: forwardProgress)
                            Text(statusTextForForwardCapture())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if forwardPhase == .secondEdge {
                            Text("Edge 1 captured ✓")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("Start edge holds") {
                        handlePrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .forefoot:
                if isForefootCapturing {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: forefootProgress)
                        Text(statusTextForForefootCapture())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Start forefoot hold") {
                        handlePrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .complete:
                Button("Done") {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .stationary:
            startStationaryCalibration()
        case .forward:
            startForwardCalibration()
        case .forefoot:
            startForefootCalibration()
        case .complete:
            dismiss()
        }
    }

    private func handleSample(_ sample: SensorSample) {
        switch step {
        case .stationary:
            handleStationarySample(sample)
        case .forward:
            handleForwardSample(sample)
        case .forefoot:
            handleForefootSample(sample)
        default:
            break
        }
    }

    private func startStationaryCalibration() {
        isStationaryCapturing = true
        stationaryProgress = 0
        stationarySamples = []
        stationaryStart = Date()
    }

    private func startForwardCalibration() {
        isForwardCapturing = true
        forwardProgress = 0
        forwardPhase = .firstEdge
        forwardHoldStart = nil
        forwardHoldDirection = nil
        edgeOneSamples = []
        edgeTwoSamples = []
    }

    private func handleStationarySample(_ sample: SensorSample) {
        guard isStationaryCapturing, let start = stationaryStart else { return }
        stationarySamples.append(sample)
        let elapsed = Date().timeIntervalSince(start)
        stationaryProgress = min(max(elapsed / stationaryDuration, 0), 1)
        guard elapsed >= stationaryDuration else { return }
        let result = client.captureStationaryCalibration(samples: stationarySamples)
        isStationaryCapturing = false
        switch result {
        case .success:
            step = .forward
        case .failure(let message):
            calibrationError = message
        }
    }

    private func handleForwardSample(_ sample: SensorSample) {
        guard isForwardCapturing else { return }
        let pitchInRange = abs(livePitch) <= pitchTolerance
        let rollMagnitude = abs(liveRoll)
        let rollDirection = liveRoll >= 0 ? 1.0 : -1.0

        switch forwardPhase {
        case .firstEdge:
            guard pitchInRange, rollMagnitude >= rollHoldThreshold else {
                resetForwardHold()
                return
            }
            if forwardHoldDirection == nil || forwardHoldDirection != rollDirection || forwardHoldStart == nil {
                forwardHoldDirection = rollDirection
                forwardHoldStart = Date()
                edgeOneSamples = []
            }
            edgeOneSamples.append(sample)
            updateForwardProgress()
            if forwardProgress >= 1 {
                forwardPhase = .secondEdge
                forwardHoldStart = nil
                forwardProgress = 0
            }
        case .secondEdge:
            guard let firstDirection = forwardHoldDirection else { return }
            let requiredDirection = firstDirection * -1
            guard pitchInRange, rollMagnitude >= rollHoldThreshold, rollDirection == requiredDirection else {
                resetForwardHold()
                return
            }
            if forwardHoldStart == nil {
                forwardHoldStart = Date()
                edgeTwoSamples = []
            }
            edgeTwoSamples.append(sample)
            updateForwardProgress()
            if forwardProgress >= 1 {
                let result = client.captureForwardCalibration(
                    edgeOneSamples: edgeOneSamples,
                    edgeTwoSamples: edgeTwoSamples
                )
                isForwardCapturing = false
                switch result {
                case .success:
                    step = .forefoot
                case .failure(let message):
                    calibrationError = message
                }
            }
        }
    }

    private func startForefootCalibration() {
        isForefootCapturing = true
        forefootProgress = 0
        forefootHoldStart = nil
        forefootSamples = []
    }

    private func handleForefootSample(_ sample: SensorSample) {
        guard isForefootCapturing else { return }
        guard abs(livePitch) >= forefootPitchThreshold else {
            resetForefootHold()
            return
        }
        if forefootHoldStart == nil {
            forefootHoldStart = Date()
            forefootSamples = []
        }
        forefootSamples.append(sample)
        updateForefootProgress()
        if forefootProgress >= 1 {
            let result = client.captureForefootCalibration(forefootSamples: forefootSamples)
            isForefootCapturing = false
            switch result {
            case .success:
                step = .complete
            case .failure(let message):
                calibrationError = message
            }
        }
    }

    private func updateForwardProgress() {
        guard let start = forwardHoldStart else {
            forwardProgress = 0
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        forwardProgress = min(max(elapsed / forwardHoldDuration, 0), 1)
    }

    private func updateForefootProgress() {
        guard let start = forefootHoldStart else {
            forefootProgress = 0
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        forefootProgress = min(max(elapsed / forwardHoldDuration, 0), 1)
    }

    private func resetForwardHold() {
        forwardHoldStart = nil
        forwardProgress = 0
        switch forwardPhase {
        case .firstEdge:
            edgeOneSamples = []
        case .secondEdge:
            edgeTwoSamples = []
        }
    }

    private func resetForefootHold() {
        forefootHoldStart = nil
        forefootProgress = 0
        forefootSamples = []
    }

    private func statusTextForForwardCapture() -> String {
        let pitchStatus = abs(livePitch) <= pitchTolerance ? "Pitch ok" : "Keep pitch within ±\(Int(pitchTolerance))°"
        let rollStatus = abs(liveRoll) >= rollHoldThreshold ? "Hold the edge" : "Tilt more to the edge"
        return "\(pitchStatus) • \(rollStatus)"
    }

    private func statusTextForForefootCapture() -> String {
        let pitchStatus = abs(livePitch) >= forefootPitchThreshold
            ? "Forefoot lifted"
            : "Lift the forefoot"
        return "\(pitchStatus) • Hold steady"
    }

    private var calibrationVisualHint: String {
        switch step {
        case .forward:
            return "Tilt to one edge, hold steady, then repeat on the opposite edge while keeping pitch near 0°."
        case .forefoot:
            return "Lift the forefoot while keeping the heel down. Hold steady for 2 seconds."
        default:
            return "Hold the boot steady and keep pitch/roll near zero."
        }
    }
}

private struct RunSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metricStore: MetricSelectionStore
    @ObservedObject var session: RideSessionViewModel
    @ObservedObject var primaryClient: StreamClient
    let secondaryClient: StreamClient?
    let sensorMode: SensorMode
    @ObservedObject var assignmentStore: SensorAssignmentStore
    @ObservedObject var locationManager: RideLocationManager
    @ObservedObject var runStore: RunDataStore
    @State private var saveError: String?
    private let edgeUpdateInterval: TimeInterval = 0.05
    private let edgeGapThreshold: TimeInterval = 0.75

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

                        Chart {
                            edgeLineSeries(for: .single, color: nil)
                            edgeLineSeries(for: .left, color: .blue)
                            edgeLineSeries(for: .right, color: .purple)
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
                        RunAnalysisView(
                            run: session.buildRunRecord(
                                runNumber: runStore.runNumber(for: Date()),
                                calibration: runCalibration()
                            )
                        )
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
        .onReceive(primaryEdgePublisher) { angle in
            guard session.isRunning, let sample = primaryClient.latestSample else { return }
            ingestSample(from: primaryClient, sample: sample, edgeAngle: angle, fallbackSide: .left)
        }
        .onReceive(secondaryEdgePublisher) { angle in
            guard let secondaryClient else { return }
            guard session.isRunning, let sample = secondaryClient.latestSample else { return }
            ingestSample(from: secondaryClient, sample: sample, edgeAngle: angle, fallbackSide: .right)
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

    private var primaryEdgePublisher: AnyPublisher<Double, Never> {
        primaryClient.$latestEdgeAngle
            .throttle(for: .seconds(edgeUpdateInterval), scheduler: RunLoop.main, latest: true)
            .eraseToAnyPublisher()
    }

    private var runStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live stats")
                .font(.subheadline.weight(.semibold))
            metricsGrid(metrics: metricStore.liveMetrics.sorted { $0.rawValue < $1.rawValue })
            if !locationManager.status.isEmpty {
                Text(locationManager.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricsGrid(metrics: [MetricKind]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                statTile(title: metric.title, value: liveMetricValue(for: metric))
            }
        }
    }

    private func liveMetricValue(for metric: MetricKind) -> String {
        switch metric {
        case .liveCurrentEdge:
            return "\(Int(session.latestEdgeAngle))°"
        case .liveLeftEdge:
            return edgeValue(for: .left)
        case .liveRightEdge:
            return edgeValue(for: .right)
        case .livePeakEdge:
            let peak = session.edgeSamples.compactMap { sample in
                [sample.leftAngle, sample.rightAngle].compactMap { $0 }.max()
            }.max() ?? 0
            return "\(Int(peak))°"
        case .liveEdgeRate:
            return formattedEdgeRate(samples: session.edgeSamples)
        case .liveSpeed:
            return formattedSpeed(max(locationManager.speedMetersPerSecond, 0) * 3.6)
        case .liveTurnCount:
            return "\(session.turnCount)"
        case .liveTurnSignal:
            return formattedTurnSignal()
        case .livePitch:
            return formattedPitchRoll().pitch
        case .liveRoll:
            return formattedPitchRoll().roll
        case .liveAccelG:
            return formattedAccelMagnitude()
        case .liveLeftRightDelta:
            return formattedEdgeDelta()
        default:
            return "—"
        }
    }

    private func edgeValue(for side: SensorSide) -> String {
        if let value = session.latestEdgeAnglesBySide[side] {
            return "\(Int(value))°"
        }
        return "—"
    }

    private func formattedSpeed(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }

    private func formattedTurnSignal() -> String {
        guard let sample = primaryClient.latestSample else { return "—" }
        let calibrated = primaryClient.calibratedSample(from: sample)
        let signal = computeTurnSignal(from: calibrated)
        return String(format: "%.2f", signal)
    }

    private func formattedPitchRoll() -> (pitch: String, roll: String) {
        guard let sample = primaryClient.latestSample else { return ("—", "—") }
        let pitchRoll = primaryClient.pitchRoll(from: sample)
        return ("\(Int(pitchRoll.pitch))°", "\(Int(pitchRoll.roll))°")
    }

    private func formattedAccelMagnitude() -> String {
        let magnitude = max(primaryClient.latestAccelMagnitude, secondaryClient?.latestAccelMagnitude ?? 0)
        return String(format: "%.2f g", magnitude)
    }

    private func formattedEdgeDelta() -> String {
        guard sensorMode == .dual else { return "—" }
        let left = session.latestEdgeAnglesBySide[.left] ?? 0
        let right = session.latestEdgeAnglesBySide[.right] ?? 0
        return "\(Int(abs(left - right)))°"
    }

    private func formattedEdgeRate(samples: [EdgeSample]) -> String {
        guard samples.count > 1 else { return "—" }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var rates: [Double] = []
        rates.reserveCapacity(sorted.count - 1)
        for index in 1..<sorted.count {
            guard let currentAngle = sorted[index].combinedAngle,
                  let previousAngle = sorted[index - 1].combinedAngle
            else { continue }
            let deltaAngle = abs(currentAngle - previousAngle)
            let deltaTime = sorted[index].timestamp.timeIntervalSince(sorted[index - 1].timestamp)
            if deltaTime > 0 {
                rates.append(deltaAngle / deltaTime)
            }
        }
        guard let average = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count) else {
            return "—"
        }
        return String(format: "%.1f°/s", average)
    }

    private func edgeSamples(for side: SensorSide) -> [EdgeAngleSample] {
        session.edgeSamples.compactMap { sample in
            let angle: Double?
            switch side {
            case .single:
                guard sensorMode == .single else { return nil }
                angle = sample.leftAngle ?? sample.rightAngle
            case .left:
                angle = sample.leftAngle
            case .right:
                angle = sample.rightAngle
            }
            guard let angle else { return nil }
            return EdgeAngleSample(id: sample.id, timestamp: sample.timestamp, angle: angle)
        }
    }

    @ChartContentBuilder
    private func edgeLineSeries(for side: SensorSide, color: Color?) -> some ChartContent {
        let segments = edgeSampleSegments(for: side)
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            ForEach(segment) { sample in
                LineMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                    .foregroundStyle(color ?? .primary)
                    .interpolationMethod(.catmullRom)
            }
        }
    }

    private func edgeSampleSegments(for side: SensorSide) -> [[EdgeAngleSample]] {
        let samples = edgeSamples(for: side).sorted { $0.timestamp < $1.timestamp }
        guard !samples.isEmpty else { return [] }
        var segments: [[EdgeAngleSample]] = []
        var current: [EdgeAngleSample] = []
        for sample in samples {
            if let last = current.last,
               sample.timestamp.timeIntervalSince(last.timestamp) > edgeGapThreshold
            {
                if !current.isEmpty {
                    segments.append(current)
                }
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private func ingestSample(from client: StreamClient, sample: SensorSample, edgeAngle: Double, fallbackSide: SensorSide) {
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
        let side = resolvedSide(for: client, fallback: fallbackSide)
        let calibratedSample = client.calibratedSample(from: sample)
        session.ingest(
            sample: calibratedSample,
            edgeAngle: edgeAngle,
            speedMetersPerSecond: speed,
            location: location,
            side: side,
            rawSample: sample
        )
    }

    private func resolvedSide(for client: StreamClient, fallback: SensorSide) -> SensorSide {
        if sensorMode == .dual {
            if let identifier = client.connectedIdentifier, identifier == assignmentStore.leftSensorIdentifier {
                return .left
            }
            if let identifier = client.connectedIdentifier, identifier == assignmentStore.rightSensorIdentifier {
                return .right
            }
            return fallback
        }
        return .single
    }

    private var secondaryEdgePublisher: AnyPublisher<Double, Never> {
        secondaryClient?.$latestEdgeAngle
            .throttle(for: .seconds(edgeUpdateInterval), scheduler: RunLoop.main, latest: true)
            .eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    private func computeTurnSignal(from sample: SensorSample) -> Double {
        sample.gz
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
            let run = session.buildRunRecord(runNumber: runNumber, calibration: runCalibration())
            try runStore.save(run: run)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func runCalibration() -> RunCalibration? {
        switch sensorMode {
        case .single:
            let calibration = RunCalibration(single: primaryClient.currentBootCalibration())
            return calibration.single == nil ? nil : calibration
        case .dual:
            let leftCalibration = calibrationFor(identifier: assignmentStore.leftSensorIdentifier)
            let rightCalibration = calibrationFor(identifier: assignmentStore.rightSensorIdentifier)
            let calibration = RunCalibration(single: nil, left: leftCalibration, right: rightCalibration)
            if calibration.left == nil && calibration.right == nil {
                return nil
            }
            return calibration
        }
    }

    private func calibrationFor(identifier: String?) -> BootCalibration? {
        guard let identifier else { return nil }
        if primaryClient.connectedIdentifier == identifier {
            return primaryClient.currentBootCalibration()
        }
        if secondaryClient?.connectedIdentifier == identifier {
            return secondaryClient?.currentBootCalibration()
        }
        return nil
    }
}

private struct EdgeAngleSample: Identifiable {
    let id: UUID
    let timestamp: Date
    let angle: Double
}

private struct BootAngleSnapshot: Identifiable {
    let id = UUID()
    let label: String
    let edgeAngle: Double
    let signedEdgeAngle: Double
    let forwardAngle: Double
    let isCalibrated: Bool
}

private struct BootAngleCard: View {
    let boots: [BootAngleSnapshot]
    @State private var show3DView = false

    private var averageAngle: Int {
        let values = boots.map { $0.edgeAngle }
        guard !values.isEmpty else { return 0 }
        return Int(values.reduce(0, +) / Double(values.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Boot edge angle")
                        .font(.headline)
                    Text(boots.count > 1 ? "Left + right boots" : "Live side tilt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("3D view", isOn: $show3DView)
                        .font(.footnote.weight(.semibold))
                        .toggleStyle(.switch)
                    Text("\(averageAngle)°")
                        .font(.headline.weight(.semibold))
                }
            }

            Group {
                if boots.count == 1, let boot = boots.first {
                    singleBootView(boot)
                } else {
                    dualBootView
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
                    ForEach(boots) { boot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(boot.label)
                                .font(.caption.weight(.semibold))
                            Text("Forward \(Int(boot.forwardAngle))°")
                            Text("Side \(Int(boot.signedEdgeAngle))°")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func singleBootView(_ boot: BootAngleSnapshot) -> some View {
        Group {
            if show3DView {
                Boot3DView(pitchAngle: boot.forwardAngle, rollAngle: boot.signedEdgeAngle)
            } else {
                BootTiltView(angle: boot.signedEdgeAngle)
            }
        }
    }

    private var dualBootView: some View {
        HStack(spacing: 16) {
            ForEach(boots) { boot in
                VStack(spacing: 8) {
                    if show3DView {
                        Boot3DView(pitchAngle: boot.forwardAngle, rollAngle: boot.signedEdgeAngle)
                    } else {
                        BootTiltView(angle: boot.signedEdgeAngle)
                    }
                    VStack(spacing: 2) {
                        Text(boot.label)
                            .font(.footnote.weight(.semibold))
                        Text("Edge \(Int(boot.edgeAngle))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(boot.isCalibrated ? "Calibrated" : "Needs calibration")
                            .font(.caption)
                            .foregroundStyle(boot.isCalibrated ? .green : .orange)
                    }
                }
            }
        }
        .padding(.vertical, 8)
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
        if sensorMode == .dual {
            let leftClient = leftClient ?? sensorAClient
            let rightClient = rightClient ?? sensorBClient
            return BootAngleCard(
                boots: [
                    bootSnapshot(label: "Left boot", client: leftClient),
                    bootSnapshot(label: "Right boot", client: rightClient)
                ]
            )
        }
        return BootAngleCard(boots: [bootSnapshot(label: "Boot", client: primaryClient)])
    }

    private func bootSnapshot(label: String, client: StreamClient) -> BootAngleSnapshot {
        let pitchRoll = client.latestSample.map { client.pitchRoll(from: $0) }
        return BootAngleSnapshot(
            label: label,
            edgeAngle: client.latestEdgeAngle,
            signedEdgeAngle: client.latestSignedEdgeAngle,
            forwardAngle: pitchRoll?.pitch ?? 0,
            isCalibrated: client.calibrationState.isCalibrated
        )
    }
}
