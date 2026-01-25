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
        .onDisappear {
            sensorAClient.disconnect()
            sensorBClient.disconnect()
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
        }
        .onChange(of: session.isRunning) { _, isRunning in
            if isRunning {
                locationManager.startUpdates()
            } else {
                locationManager.stopUpdates()
            }
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
        case complete

        var title: String {
            switch self {
            case .stationary: return "Stand still"
            case .forward: return "Glide straight"
            case .complete: return "Calibration saved"
            }
        }

        var message: String {
            switch self {
            case .stationary:
                return "Stand still for about 2 seconds. Small sways are ok, but try to keep the boot steady so we can learn gravity and gyro bias."
            case .forward:
                return "Glide straight for 2–3 seconds with a gentle push. Keep your skis flat and avoid carving so we can spot the forward direction."
            case .complete:
                return "You're ready to ride with calibrated boot axes."
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .stationary
    @State private var isStationaryCapturing = false
    @State private var stationaryProgress: Double = 0
    @State private var stationaryStart: Date?
    @State private var stationarySamples: [SensorSample] = []
    @State private var isForwardCapturing = false
    @State private var forwardProgress: Double = 0
    @State private var forwardStart: Date?
    @State private var forwardSamples: [SensorSample] = []
    @State private var calibrationError: String?
    let client: StreamClient
    let sensorLabel: String
    private let stationaryDuration: TimeInterval = 2.0
    private let forwardDuration: TimeInterval = 2.5

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
            handleSample(sample)
        }
        .alert("Calibration failed", isPresented: Binding(get: { calibrationError != nil }, set: { _ in calibrationError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calibrationError ?? "Unknown error")
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
                        ProgressView(value: forwardProgress)
                        Text("Capturing forward glide… \(Int(forwardProgress * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Start 3s glide capture") {
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
        forwardSamples = []
        forwardStart = Date()
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
        guard isForwardCapturing, let start = forwardStart else { return }
        forwardSamples.append(sample)
        let elapsed = Date().timeIntervalSince(start)
        forwardProgress = min(max(elapsed / forwardDuration, 0), 1)
        guard elapsed >= forwardDuration else { return }
        let result = client.captureForwardCalibration(samples: forwardSamples)
        isForwardCapturing = false
        switch result {
        case .success:
            step = .complete
        case .failure(let message):
            calibrationError = message
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
                            ForEach(edgeSamples(for: .single)) { sample in
                                LineMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                                    .interpolationMethod(.catmullRom)
                            }
                            ForEach(edgeSamples(for: .left)) { sample in
                                LineMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                                    .foregroundStyle(.blue)
                                    .interpolationMethod(.catmullRom)
                            }
                            ForEach(edgeSamples(for: .right)) { sample in
                                LineMark(x: .value("Time", sample.timestamp), y: .value("Angle", sample.angle))
                                    .foregroundStyle(.purple)
                                    .interpolationMethod(.catmullRom)
                            }
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
        .onReceive(primaryClient.$latestEdgeAngle) { angle in
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
            let peak = session.edgeSamples.map(\.angle).max() ?? 0
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
            let deltaAngle = abs(sorted[index].angle - sorted[index - 1].angle)
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

    private func edgeSamples(for side: SensorSide) -> [EdgeSample] {
        switch side {
        case .single:
            return session.edgeSamples.filter { $0.side == .single }
        case .left:
            return session.edgeSamples.filter { $0.side == .left }
        case .right:
            return session.edgeSamples.filter { $0.side == .right }
        }
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
        secondaryClient?.$latestEdgeAngle.eraseToAnyPublisher() ?? Just(0).eraseToAnyPublisher()
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
        let pitchRoll = primaryClient.latestSample.map { primaryClient.pitchRoll(from: $0) }
        let forwardAngle = pitchRoll?.pitch ?? 0
        return BootAngleCard(
            angle: combinedEdgeAngle,
            tiltAngle: combinedSignedEdgeAngle,
            forwardAngle: forwardAngle
        )
    }

    var combinedEdgeAngle: Double {
        let values = [primaryClient.latestEdgeAngle, secondaryClient?.latestEdgeAngle].compactMap { $0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var combinedSignedEdgeAngle: Double {
        let values = [primaryClient.latestSignedEdgeAngle, secondaryClient?.latestSignedEdgeAngle].compactMap { $0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
