import Charts
import CoreLocation
import MapKit
import SwiftUI

struct RunAnalysisView: View {
    @EnvironmentObject private var metricStore: MetricSelectionStore
    let run: RunRecord
    @State private var selectedTurnID: TurnWindow.ID?
    @State private var selectedTurnProgress: Double?
    @State private var lastSelectedTurnProgress: Double?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var rawExportURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runSummaryCard

                Text("Turn analysis")
                    .font(.headline)

                turnChart
                    .frame(height: 220)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let selectedSample, let selectedTurn {
                    turnDetails(for: selectedSample, turn: selectedTurn)
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

                rawDataCard
            }
        }
    }

    private var turnChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let turn = selectedTurn {
                Text("Turn \(turn.index) • \(turn.direction.rawValue.capitalized)")
                    .font(.subheadline.weight(.semibold))
                let samples = turnChartSamples(for: turn)
                let leftSamples = edgeSeries(from: samples, side: .left)
                let rightSamples = edgeSeries(from: samples, side: .right)
                Chart {
                    ForEach(leftSamples) { sample in
                        LineMark(
                            x: .value("Turn %", sample.progress),
                            y: .value("Left edge angle", sample.edgeAngle)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(rightSamples) { sample in
                        LineMark(
                            x: .value("Turn %", sample.progress),
                            y: .value("Right edge angle", sample.edgeAngle)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                    }
                    if leftSamples.isEmpty && rightSamples.isEmpty {
                        ForEach(samples) { sample in
                            if let edgeAngle = sample.combinedEdgeAngle {
                                LineMark(
                                    x: .value("Turn %", sample.progress),
                                    y: .value("Edge angle", edgeAngle)
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
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
                leftEdgeAngle: sample.leftEdgeAngle,
                rightEdgeAngle: sample.rightEdgeAngle,
                turnSignal: sample.turnSignal,
                timestamp: sample.timestamp
            )
        }
    }

    private func edgeSeries(from samples: [TurnChartSample], side: SensorSide) -> [TurnEdgePoint] {
        samples.compactMap { sample in
            let angle: Double?
            switch side {
            case .left:
                angle = sample.leftEdgeAngle
            case .right:
                angle = sample.rightEdgeAngle
            case .single:
                angle = sample.leftEdgeAngle ?? sample.rightEdgeAngle
            }
            guard let angle else { return nil }
            return TurnEdgePoint(id: sample.id, progress: sample.progress, edgeAngle: angle)
        }
    }

    private var selectedSample: TurnChartSample? {
        guard let turn = selectedTurn else { return nil }
        let samples = turnChartSamples(for: turn)
        guard let activeTurnProgress else { return samples.max(by: { $0.maxEdgeAngle < $1.maxEdgeAngle }) }
        return samples.min(by: { abs($0.progress - activeTurnProgress) < abs($1.progress - activeTurnProgress) })
    }

    private func updateSelectedProgress(for turn: TurnWindow?) {
        guard let turn else {
            selectedTurnProgress = nil
            lastSelectedTurnProgress = nil
            return
        }
        let samples = turnChartSamples(for: turn)
        guard let peakSample = samples.max(by: { $0.maxEdgeAngle < $1.maxEdgeAngle }) else {
            selectedTurnProgress = nil
            lastSelectedTurnProgress = nil
            return
        }
        selectedTurnProgress = peakSample.progress
        lastSelectedTurnProgress = peakSample.progress
    }

    private func edgeAngleDetail(for sample: TurnChartSample) -> String {
        let left = sample.leftEdgeAngle.map { "\(Int($0))°" }
        let right = sample.rightEdgeAngle.map { "\(Int($0))°" }
        if let left, let right {
            return "L \(left) / R \(right)"
        }
        if let left {
            return left
        }
        if let right {
            return right
        }
        return "—"
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

    private func turnDetails(for sample: TurnChartSample, turn: TurnWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor details")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                detailTile(title: "Progress", value: "\(Int(sample.progress))%")
                detailTile(title: "Edge angle", value: edgeAngleDetail(for: sample))
                detailTile(title: "Turn signal", value: String(format: "%.2f", sample.turnSignal))
                detailTile(title: "Turn time", value: formattedTurnDuration(turn))
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
            metricsGrid(metrics: metricStore.recordingMetrics.sorted { $0.rawValue < $1.rawValue })
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

    private func metricsGrid(metrics: [MetricKind]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                summaryTile(title: metric.title, value: recordingMetricValue(for: metric))
            }
        }
    }

    private func recordingMetricValue(for metric: MetricKind) -> String {
        switch metric {
        case .recordingMaxSpeed:
            return formattedSpeed(maxSpeedKmh)
        case .recordingAverageSpeed:
            return formattedSpeed(averageSpeedKmh)
        case .recordingRunDuration:
            return formattedDuration(runDuration)
        case .recordingDistance:
            return formattedDistance(runDistanceMeters)
        case .recordingTurnCount:
            return "\(run.turnWindows.count)"
        case .recordingAverageTurnDuration:
            return formattedDuration(averageTurnDuration)
        case .recordingMaxEdge:
            return formattedEdge(maxEdgeAngle)
        case .recordingAverageEdge:
            return formattedEdge(averageEdgeAngle)
        case .recordingPeakLeftEdge:
            return formattedEdge(peakEdgeAngle(for: .left))
        case .recordingPeakRightEdge:
            return formattedEdge(peakEdgeAngle(for: .right))
        case .recordingEdgeSampleCount:
            return formattedEdgeSampleCount
        case .recordingEdgeSampleRate:
            return formattedEdgeSampleResolution
        case .recordingEdgeRate:
            return formattedEdgeRate(samples: run.edgeSamples)
        case .recordingTurnSymmetry:
            return formattedTurnSymmetry
        case .recordingBalanceScore:
            return formattedBalanceScore
        default:
            return "—"
        }
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

    private var formattedEdgeSampleCount: String {
        let sampleCount = run.edgeSamples.reduce(0) { partial, sample in
            partial + (sample.leftAngle == nil ? 0 : 1) + (sample.rightAngle == nil ? 0 : 1)
        }
        guard sampleCount > 0 else { return "—" }
        return "\(sampleCount)"
    }

    private var formattedEdgeSampleResolution: String {
        let samples = run.edgeSamples
        guard samples.count > 1 else { return "—" }
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(samples.count - 1)
        for index in 1..<samples.count {
            let delta = samples[index].timestamp.timeIntervalSince(samples[index - 1].timestamp)
            if delta > 0 {
                intervals.append(delta)
            }
        }
        guard !intervals.isEmpty else { return "—" }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else { return "—" }
        let hz = 1 / averageInterval
        return String(format: "%.1f Hz", hz)
    }

    private var averageTurnDuration: TimeInterval? {
        guard !run.turnWindows.isEmpty else { return nil }
        let durations = run.turnWindows.map { max($0.endTime.timeIntervalSince($0.startTime), 0) }
        let total = durations.reduce(0, +)
        return total / Double(durations.count)
    }

    private var maxEdgeAngle: Double? {
        run.edgeSamples.compactMap { sample in
            [sample.leftAngle, sample.rightAngle].compactMap { $0 }.max()
        }.max()
    }

    private var averageEdgeAngle: Double? {
        let values = run.edgeSamples.flatMap { sample in
            [sample.leftAngle, sample.rightAngle].compactMap { $0 }
        }
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Double(values.count)
    }

    private func peakEdgeAngle(for side: SensorSide) -> Double? {
        let values = run.edgeSamples.compactMap { sample -> Double? in
            switch side {
            case .left:
                return sample.leftAngle
            case .right:
                return sample.rightAngle
            case .single:
                return sample.leftAngle ?? sample.rightAngle
            }
        }
        return values.max()
    }

    private var formattedTurnSymmetry: String {
        let leftTurns = run.turnWindows.filter { $0.direction == .left }.count
        let rightTurns = run.turnWindows.filter { $0.direction == .right }.count
        let total = max(leftTurns + rightTurns, 1)
        let leftPercent = Double(leftTurns) / Double(total) * 100
        let rightPercent = Double(rightTurns) / Double(total) * 100
        return String(format: "L %.0f%% / R %.0f%%", leftPercent, rightPercent)
    }

    private var formattedBalanceScore: String {
        let leftTurns = run.turnWindows.filter { $0.direction == .left }.count
        let rightTurns = run.turnWindows.filter { $0.direction == .right }.count
        let total = max(leftTurns + rightTurns, 1)
        let delta = abs(leftTurns - rightTurns)
        let score = max(0, 100 - (Double(delta) / Double(total) * 100))
        return String(format: "%.0f%%", score)
    }

    private func formattedSpeed(_ speed: Double?) -> String {
        guard let speed else { return "—" }
        return String(format: "%.1f km/h", speed)
    }

    private func formattedEdge(_ angle: Double?) -> String {
        guard let angle else { return "—" }
        return "\(Int(angle))°"
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

    private func formattedTurnDuration(_ turn: TurnWindow) -> String {
        let duration = max(turn.endTime.timeIntervalSince(turn.startTime), 0)
        return formattedDuration(duration)
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
        guard !rates.isEmpty else { return "—" }
        let average = rates.reduce(0, +) / Double(rates.count)
        return String(format: "%.1f°/s", average)
    }

    private var rawDataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw data export")
                .font(.subheadline.weight(.semibold))
            if run.rawSensorSamples.isEmpty {
                Text("Raw data recording was disabled for this run.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Download the full sensor stream for AI analysis and metric development.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let rawExportURL {
                    ShareLink(item: rawExportURL) {
                        Label("Share raw data", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Prepare raw data file") {
                        rawExportURL = buildRawExport()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func buildRawExport() -> URL? {
        guard !run.rawSensorSamples.isEmpty else { return nil }
        let export = RawDataExport(
            runName: run.name,
            date: run.date,
            sensorMode: run.sensorMode,
            samples: run.rawSensorSamples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        guard let data = try? encoder.encode(export) else { return nil }
        let filename = "\(run.name.replacingOccurrences(of: " ", with: "_"))_raw.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}

private struct TurnChartSample: Identifiable {
    let id = UUID()
    let progress: Double
    let leftEdgeAngle: Double?
    let rightEdgeAngle: Double?
    let turnSignal: Double
    let timestamp: Date

    var combinedEdgeAngle: Double? {
        let values = [leftEdgeAngle, rightEdgeAngle].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var maxEdgeAngle: Double {
        [leftEdgeAngle, rightEdgeAngle].compactMap { $0 }.max() ?? 0
    }
}

private struct TurnEdgePoint: Identifiable {
    let id: UUID
    let progress: Double
    let edgeAngle: Double
}

private struct RawDataExport: Codable {
    let runName: String
    let date: Date
    let sensorMode: SensorMode
    let samples: [RawSensorSample]
}
