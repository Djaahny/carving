import Foundation

enum SensorSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case single

    var id: String { rawValue }
}

enum SensorMode: String, Codable, CaseIterable, Identifiable {
    case single
    case dual

    var id: String { rawValue }
}

struct BackgroundSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let edgeAngle: Double
    let side: SensorSide

    init(timestamp: Date, edgeAngle: Double, side: SensorSide) {
        self.id = UUID()
        self.timestamp = timestamp
        self.edgeAngle = edgeAngle
        self.side = side
    }
}

struct TurnSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let edgeAngle: Double
    let turnSignal: Double

    init(timestamp: Date, edgeAngle: Double, turnSignal: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.edgeAngle = edgeAngle
        self.turnSignal = turnSignal
    }
}

struct RawSensorSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double
    let side: SensorSide

    init(timestamp: Date, ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double, side: SensorSide) {
        self.id = UUID()
        self.timestamp = timestamp
        self.ax = ax
        self.ay = ay
        self.az = az
        self.gx = gx
        self.gy = gy
        self.gz = gz
        self.side = side
    }
}

struct LocationSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let horizontalAccuracy: Double

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double, speed: Double, horizontalAccuracy: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }
}

enum TurnDirection: String, Codable {
    case left
    case right
    case unknown
}

struct TurnWindow: Codable, Identifiable {
    let id: UUID
    let index: Int
    let startTime: Date
    let endTime: Date
    let direction: TurnDirection
    let meanTurnSignal: Double
    let peakEdgeAngle: Double
    let samples: [TurnSample]
    let location: LocationSample?

    init(
        index: Int,
        startTime: Date,
        endTime: Date,
        direction: TurnDirection,
        meanTurnSignal: Double,
        peakEdgeAngle: Double,
        samples: [TurnSample],
        location: LocationSample?
    ) {
        self.id = UUID()
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.direction = direction
        self.meanTurnSignal = meanTurnSignal
        self.peakEdgeAngle = peakEdgeAngle
        self.samples = samples
        self.location = location
    }
}

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let runNumber: Int
    let name: String
    let turnWindows: [TurnWindow]
    let backgroundSamples: [BackgroundSample]
    let locationTrack: [LocationSample]
    let edgeSamples: [EdgeSample]
    let rawSensorSamples: [RawSensorSample]
    let sensorMode: SensorMode

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case runNumber
        case name
        case turnWindows
        case backgroundSamples
        case locationTrack
        case edgeSamples
        case rawSensorSamples
        case sensorMode
    }

    init(
        date: Date,
        runNumber: Int,
        name: String,
        turnWindows: [TurnWindow],
        backgroundSamples: [BackgroundSample],
        locationTrack: [LocationSample],
        edgeSamples: [EdgeSample],
        rawSensorSamples: [RawSensorSample],
        sensorMode: SensorMode
    ) {
        self.id = UUID()
        self.date = date
        self.runNumber = runNumber
        self.name = name
        self.turnWindows = turnWindows
        self.backgroundSamples = backgroundSamples
        self.locationTrack = locationTrack
        self.edgeSamples = edgeSamples
        self.rawSensorSamples = rawSensorSamples
        self.sensorMode = sensorMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        runNumber = try container.decode(Int.self, forKey: .runNumber)
        name = try container.decode(String.self, forKey: .name)
        turnWindows = try container.decodeIfPresent([TurnWindow].self, forKey: .turnWindows) ?? []
        backgroundSamples = try container.decodeIfPresent([BackgroundSample].self, forKey: .backgroundSamples) ?? []
        locationTrack = try container.decodeIfPresent([LocationSample].self, forKey: .locationTrack) ?? []
        edgeSamples = try container.decodeIfPresent([EdgeSample].self, forKey: .edgeSamples) ?? []
        rawSensorSamples = try container.decodeIfPresent([RawSensorSample].self, forKey: .rawSensorSamples) ?? []
        sensorMode = try container.decodeIfPresent(SensorMode.self, forKey: .sensorMode) ?? .single
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(runNumber, forKey: .runNumber)
        try container.encode(name, forKey: .name)
        try container.encode(turnWindows, forKey: .turnWindows)
        try container.encode(backgroundSamples, forKey: .backgroundSamples)
        try container.encode(locationTrack, forKey: .locationTrack)
        try container.encode(edgeSamples, forKey: .edgeSamples)
        try container.encode(rawSensorSamples, forKey: .rawSensorSamples)
        try container.encode(sensorMode, forKey: .sensorMode)
    }
}
