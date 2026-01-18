import Charts
import MapKit
import SwiftUI

struct RunAnalysisView: View {
    let run: RunRecord
    @State private var selectedTurnID: TurnWindow.ID?
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn analysis")
                .font(.headline)

            turnChart
                .frame(height: 220)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                Text("Turn track")
                    .font(.subheadline.weight(.semibold))
                Map(position: $mapPosition) {
                    if !trackCoordinates.isEmpty {
                        MapPolyline(coordinates: trackCoordinates)
                            .stroke(.blue, lineWidth: 3)
                    }
                    ForEach(run.turnWindows) { turn in
                        if let location = turn.location {
                            Annotation("Turn \(turn.index)", coordinate: CLLocationCoordinate2D(
                                latitude: location.latitude,
                                longitude: location.longitude
                            )) {
                                Text("\(turn.index)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(turn.id == selectedTurnID ? Color.orange : Color.blue))
                                    .onTapGesture {
                                        selectedTurnID = turn.id
                                    }
                            }
                        }
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var turnChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let turn = selectedTurn {
                Text("Turn \(turn.index) • \(turn.direction.rawValue.capitalized)")
                    .font(.subheadline.weight(.semibold))
                Chart(turnChartSamples(for: turn)) { sample in
                    LineMark(
                        x: .value("Turn %", sample.progress),
                        y: .value("Edge angle", sample.edgeAngle)
                    )
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Turn %", sample.progress),
                        y: .value("Edge angle", sample.edgeAngle)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [Color.purple.opacity(0.4), Color.purple.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
                .chartXScale(domain: 0...100)
                .chartYScale(domain: 0...90)
            } else {
                Text("Tap a turn marker to view edge angle over the turn.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Chart([] as [TurnChartSample]) { _ in }
                    .chartXScale(domain: 0...100)
                    .chartYScale(domain: 0...90)
            }
        }
        .padding()
    }

    private var trackCoordinates: [CLLocationCoordinate2D] {
        run.locationTrack.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var selectedTurn: TurnWindow? {
        if let selectedTurnID {
            return run.turnWindows.first { $0.id == selectedTurnID }
        }
        return run.turnWindows.first
    }

    private func turnChartSamples(for turn: TurnWindow) -> [TurnChartSample] {
        let duration = max(turn.endTime.timeIntervalSince(turn.startTime), 0.001)
        return turn.samples.map { sample in
            let progress = (sample.timestamp.timeIntervalSince(turn.startTime) / duration) * 100
            return TurnChartSample(progress: progress, edgeAngle: sample.edgeAngle)
        }
    }
}

private struct TurnChartSample: Identifiable {
    let id = UUID()
    let progress: Double
    let edgeAngle: Double
}
