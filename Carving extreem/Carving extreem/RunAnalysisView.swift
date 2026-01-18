import Charts
import MapKit
import SwiftUI

struct RunAnalysisView: View {
    let run: RunRecord
    @State private var selectedTurnID: TurnWindow.ID?
    @State private var selectedTurnProgress: Double?
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn analysis")
                .font(.headline)

            turnChart
                .frame(height: 220)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if let selectedSample {
                turnDetails(for: selectedSample)
                    .transition(.opacity)
            }

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
                                        updateSelectedProgress(for: turn)
                                    }
                            }
                        }
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onAppear {
                    updateMapPosition()
                    if selectedTurnID == nil {
                        selectedTurnID = run.turnWindows.first?.id
                    }
                    updateSelectedProgress(for: selectedTurn)
                }
                .onChange(of: run.locationTrack.count) { _, _ in
                    updateMapPosition()
                }
                .onChange(of: selectedTurnID) { _, _ in
                    updateSelectedProgress(for: selectedTurn)
                }
            }
        }
    }

    private var turnChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let turn = selectedTurn {
                Text("Turn \(turn.index) • \(turn.direction.rawValue.capitalized)")
                    .font(.subheadline.weight(.semibold))
                let samples = turnChartSamples(for: turn)
                Chart(samples) { sample in
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
                    if let selectedTurnProgress {
                        RuleMark(x: .value("Selected turn progress", selectedTurnProgress))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: 0...100)
                .chartYScale(domain: 0...90)
                .chartXSelection(value: $selectedTurnProgress)
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
            return TurnChartSample(
                progress: progress,
                edgeAngle: sample.edgeAngle,
                turnSignal: sample.turnSignal,
                timestamp: sample.timestamp
            )
        }
    }

    private var selectedSample: TurnChartSample? {
        guard let turn = selectedTurn else { return nil }
        let samples = turnChartSamples(for: turn)
        guard let selectedTurnProgress else { return samples.max(by: { $0.edgeAngle < $1.edgeAngle }) }
        return samples.min(by: { abs($0.progress - selectedTurnProgress) < abs($1.progress - selectedTurnProgress) })
    }

    private func updateSelectedProgress(for turn: TurnWindow?) {
        guard let turn else {
            selectedTurnProgress = nil
            return
        }
        let samples = turnChartSamples(for: turn)
        guard let peakSample = samples.max(by: { $0.edgeAngle < $1.edgeAngle }) else {
            selectedTurnProgress = nil
            return
        }
        selectedTurnProgress = peakSample.progress
    }

    private func updateMapPosition() {
        guard !trackCoordinates.isEmpty else { return }
        if trackCoordinates.count == 1, let coordinate = trackCoordinates.first {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            )
            return
        }
        let latitudes = trackCoordinates.map(\.latitude)
        let longitudes = trackCoordinates.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max()
        else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func turnDetails(for sample: TurnChartSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor details")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                detailTile(title: "Progress", value: "\(Int(sample.progress))%")
                detailTile(title: "Edge angle", value: "\(Int(sample.edgeAngle))°")
                detailTile(title: "Turn signal", value: String(format: "%.2f", sample.turnSignal))
            }
            Text("Timestamp: \(sample.timestamp.formatted(date: .omitted, time: .standard))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detailTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TurnChartSample: Identifiable {
    let id = UUID()
    let progress: Double
    let edgeAngle: Double
    let turnSignal: Double
    let timestamp: Date
}
