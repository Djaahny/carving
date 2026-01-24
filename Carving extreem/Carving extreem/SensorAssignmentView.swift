import SwiftUI

struct SensorAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var clientA: StreamClient
    @ObservedObject var clientB: StreamClient
    @ObservedObject var assignmentStore: SensorAssignmentStore
    @State private var step: Step = .left
    @State private var leftAssignment: String?
    @State private var rightAssignment: String?
    @State private var statusMessage: String?

    enum Step: Int {
        case left
        case right
        case done

        var title: String {
            switch self {
            case .left:
                return "Stamp left boot"
            case .right:
                return "Stamp right boot"
            case .done:
                return "Sensors assigned"
            }
        }

        var instructions: String {
            switch self {
            case .left:
                return "Stamp the left boot firmly once. We'll map the detected shock to the left sensor."
            case .right:
                return "Stamp the right boot firmly once to assign the remaining sensor."
            case .done:
                return "Left and right sensors are assigned. You're ready to calibrate."
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(step.title)
                    .font(.title2.bold())
                Text(step.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    sensorStatusRow(title: "Sensor A", client: clientA)
                    sensorStatusRow(title: "Sensor B", client: clientB)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if step == .done {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Assign sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onReceive(clientA.$lastShockTimestamp) { timestamp in
                guard let timestamp else { return }
                handleShock(from: clientA, at: timestamp)
            }
            .onReceive(clientB.$lastShockTimestamp) { timestamp in
                guard let timestamp else { return }
                handleShock(from: clientB, at: timestamp)
            }
        }
    }

    private func sensorStatusRow(title: String, client: StreamClient) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(client.isConnected ? "Connected" : "Disconnected")
                    .font(.footnote)
                    .foregroundStyle(client.isConnected ? .green : .secondary)
            }
            Spacer()
            Text(client.lastKnownSensorName ?? client.connectedIdentifier ?? "Unknown")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func handleShock(from client: StreamClient, at timestamp: Date) {
        guard client.isConnected else { return }
        guard let identifier = client.connectedIdentifier else { return }
        switch step {
        case .left:
            assignmentStore.assign(side: .left, identifier: identifier)
            leftAssignment = identifier
            statusMessage = "Left sensor assigned (\(timestamp.formatted(date: .omitted, time: .standard)))."
            step = .right
        case .right:
            guard identifier != leftAssignment else { return }
            assignmentStore.assign(side: .right, identifier: identifier)
            rightAssignment = identifier
            statusMessage = "Right sensor assigned (\(timestamp.formatted(date: .omitted, time: .standard)))."
            step = .done
        case .done:
            break
        }
    }
}
