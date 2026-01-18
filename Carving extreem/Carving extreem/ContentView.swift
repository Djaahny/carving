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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    welcomeCard

                    bootAngleCard

                    connectionCard

                    runControlCard

                    if session.isRunning {
                        edgeChartCard
                    }

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
            guard client.latestSample != nil else { return }
            session.ingest(edgeAngle: angle)
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationFlowView(client: client)
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

            Button(session.isRunning ? "Stop Run" : "Start Run") {
                if session.isRunning {
                    session.stopRun()
                } else {
                    if client.calibrationState.isCalibrated {
                        session.startRun(isCalibrated: true)
                    } else {
                        showCalibrationRequired = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isRunning ? .red : .blue)
            .disabled(!session.isRunning && !client.calibrationState.isCalibrated)

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

    private var edgeChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edge angle")
                        .font(.headline)
                    Text("Rolling 10-second view")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(client.latestEdgeAngle))°")
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
            .frame(height: 200)
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
                return "Tip the boot forward onto the toe to capture the forward reference."
            case .side:
                return "Tilt the boot toward the outside edge to capture the side reference."
            case .complete:
                return "You're ready to ride with calibrated references."
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .level
    let client: StreamClient

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(step.title)
                    .font(.title2.bold())
                Text(step.message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(primaryButtonTitle) {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
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
    }

    private var primaryButtonTitle: String {
        switch step {
        case .level: return "Capture Level"
        case .forward: return "Capture Forward"
        case .side: return "Capture Side"
        case .complete: return "Done"
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .level:
            client.captureZeroCalibration()
            step = .forward
        case .forward:
            client.captureForwardReference()
            step = .side
        case .side:
            client.captureSideReference()
            step = .complete
        case .complete:
            dismiss()
        }
    }
}

private struct BootAngleCard: View {
    let angle: Double

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

            Boot3DView(angle: angle)
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

private extension ContentView {
    var bootAngleCard: some View {
        BootAngleCard(angle: client.latestEdgeAngle)
    }
}
