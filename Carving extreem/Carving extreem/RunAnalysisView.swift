import Charts
import CoreLocation
import MapKit
import SwiftUI

struct RunAnalysisView: View {
    let run: RunRecord
    @State private var selectedTurnID: TurnWindow.ID?
    @State private var selectedTurnProgress: Double?
    @State private var lastSelectedTurnProgress: Double?
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            runSummaryCard

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
                    if let activeTurnProgress {
                        RuleMark(x: .value("Selected turn progress", activeTurnProgress))
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
        .onChange(of: selectedTurnProgress) { _, newValue in
            if let newValue {
                lastSelectedTurnProgress = newValue
            }
        }
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
        guard let activeTurnProgress else { return samples.max(by: { $0.edgeAngle < $1.edgeAngle }) }
        return samples.min(by: { abs($0.progress - activeTurnProgress) < abs($1.progress - activeTurnProgress) })
    }

    private func updateSelectedProgress(for turn: TurnWindow?) {
        guard let turn else {
            selectedTurnProgress = nil
            lastSelectedTurnProgress = nil
            return
        }
        let samples = turnChartSamples(for: turn)
        guard let peakSample = samples.max(by: { $0.edgeAngle < $1.edgeAngle }) else {
            selectedTurnProgress = nil
            lastSelectedTurnProgress = nil
            return
        }
        selectedTurnProgress = peakSample.progress
        lastSelectedTurnProgress = peakSample.progress
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

    private var activeTurnProgress: Double? {
        selectedTurnProgress ?? lastSelectedTurnProgress
    }

    private var runSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run summary")
                .font(.headline)
            HStack(spacing: 12) {
                summaryTile(title: "Max speed", value: formattedSpeed(maxSpeedKmh))
                summaryTile(title: "Avg speed", value: formattedSpeed(averageSpeedKmh))
            }
            HStack(spacing: 12) {
                summaryTile(title: "Turns", value: "\(run.turnWindows.count)")
                summaryTile(title: "Run time", value: formattedDuration(runDuration))
            }
            HStack(spacing: 12) {
                summaryTile(title: "Length", value: formattedDistance(runDistanceMeters))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var maxSpeedKmh: Double? {
        let speeds = run.locationTrack.map { max($0.speed, 0) }
        guard let maxSpeed = speeds.max() else { return nil }
        return maxSpeed * 3.6
    }

    private var averageSpeedKmh: Double? {
        let speeds = run.locationTrack.map { max($0.speed, 0) }
        guard !speeds.isEmpty else { return nil }
        let average = speeds.reduce(0, +) / Double(speeds.count)
        return average * 3.6
    }

    private var runDuration: TimeInterval? {
        let timestamps = run.locationTrack.map(\.timestamp)
            + run.backgroundSamples.map(\.timestamp)
            + run.turnWindows.flatMap { [$0.startTime, $0.endTime] }
        guard let start = timestamps.min(), let end = timestamps.max() else { return nil }
        return max(end.timeIntervalSince(start), 0)
    }

    private var runDistanceMeters: Double? {
        guard run.locationTrack.count > 1 else { return nil }
        var total: Double = 0
        for index in 1..<run.locationTrack.count {
            let previous = run.locationTrack[index - 1]
            let current = run.locationTrack[index]
            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            total += currentLocation.distance(from: previousLocation)
        }
        return total
    }

    private func formattedSpeed(_ speed: Double?) -> String {
        guard let speed else { return "—" }
        return String(format: "%.1f km/h", speed)
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formattedDistance(_ distance: Double?) -> String {
        guard let distance else { return "—" }
        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }
}

private struct TurnChartSample: Identifiable {
    let id = UUID()
    let progress: Double
    let edgeAngle: Double
    let turnSignal: Double
    let timestamp: Date
}
