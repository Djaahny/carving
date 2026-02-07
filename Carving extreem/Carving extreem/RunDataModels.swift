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
    let leftEdgeAngle: Double?
    let rightEdgeAngle: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case leftEdgeAngle
        case rightEdgeAngle
        case edgeAngle
        case side
    }

    init(timestamp: Date, leftEdgeAngle: Double?, rightEdgeAngle: Double?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.leftEdgeAngle = leftEdgeAngle
        self.rightEdgeAngle = rightEdgeAngle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let leftEdgeAngle = try container.decodeIfPresent(Double.self, forKey: .leftEdgeAngle)
        let rightEdgeAngle = try container.decodeIfPresent(Double.self, forKey: .rightEdgeAngle)
        if leftEdgeAngle != nil || rightEdgeAngle != nil {
            self.leftEdgeAngle = leftEdgeAngle
            self.rightEdgeAngle = rightEdgeAngle
            return
        }
        let legacyAngle = try container.decodeIfPresent(Double.self, forKey: .edgeAngle)
        let legacySide = try container.decodeIfPresent(SensorSide.self, forKey: .side)
        switch legacySide {
        case .right:
            self.leftEdgeAngle = nil
            self.rightEdgeAngle = legacyAngle
        case .left, .single, .none:
            self.leftEdgeAngle = legacyAngle
            self.rightEdgeAngle = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(leftEdgeAngle, forKey: .leftEdgeAngle)
        try container.encodeIfPresent(rightEdgeAngle, forKey: .rightEdgeAngle)
    }
}

struct TurnSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let leftEdgeAngle: Double?
    let rightEdgeAngle: Double?
    let turnSignal: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case leftEdgeAngle
        case rightEdgeAngle
        case edgeAngle
        case turnSignal
    }

    init(timestamp: Date, leftEdgeAngle: Double?, rightEdgeAngle: Double?, turnSignal: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.leftEdgeAngle = leftEdgeAngle
        self.rightEdgeAngle = rightEdgeAngle
        self.turnSignal = turnSignal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let leftEdgeAngle = try container.decodeIfPresent(Double.self, forKey: .leftEdgeAngle)
        let rightEdgeAngle = try container.decodeIfPresent(Double.self, forKey: .rightEdgeAngle)
        if leftEdgeAngle != nil || rightEdgeAngle != nil {
            self.leftEdgeAngle = leftEdgeAngle
            self.rightEdgeAngle = rightEdgeAngle
        } else {
            let legacyEdge = try container.decodeIfPresent(Double.self, forKey: .edgeAngle)
            self.leftEdgeAngle = legacyEdge
            self.rightEdgeAngle = nil
        }
        turnSignal = try container.decode(Double.self, forKey: .turnSignal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(leftEdgeAngle, forKey: .leftEdgeAngle)
        try container.encodeIfPresent(rightEdgeAngle, forKey: .rightEdgeAngle)
        try container.encode(turnSignal, forKey: .turnSignal)
    }

    var combinedEdgeAngle: Double? {
        let values = [leftEdgeAngle, rightEdgeAngle].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var peakEdgeAngle: Double? {
        [leftEdgeAngle, rightEdgeAngle].compactMap { $0 }.max()
    }
}

struct RawSensorSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let leftAx: Double?
    let leftAy: Double?
    let leftAz: Double?
    let leftGx: Double?
    let leftGy: Double?
    let leftGz: Double?
    let rightAx: Double?
    let rightAy: Double?
    let rightAz: Double?
    let rightGx: Double?
    let rightGy: Double?
    let rightGz: Double?
    let speedMetersPerSecond: Double?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let horizontalAccuracy: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case leftAx
        case leftAy
        case leftAz
        case leftGx
        case leftGy
        case leftGz
        case rightAx
        case rightAy
        case rightAz
        case rightGx
        case rightGy
        case rightGz
        case ax
        case ay
        case az
        case gx
        case gy
        case gz
        case side
        case speedMetersPerSecond
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy
    }

    init(
        timestamp: Date,
        leftSample: SensorSample?,
        rightSample: SensorSample?,
        speedMetersPerSecond: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.leftAx = leftSample?.ax
        self.leftAy = leftSample?.ay
        self.leftAz = leftSample?.az
        self.leftGx = leftSample?.gx
        self.leftGy = leftSample?.gy
        self.leftGz = leftSample?.gz
        self.rightAx = rightSample?.ax
        self.rightAy = rightSample?.ay
        self.rightAz = rightSample?.az
        self.rightGx = rightSample?.gx
        self.rightGy = rightSample?.gy
        self.rightGz = rightSample?.gz
        self.speedMetersPerSecond = speedMetersPerSecond
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let leftAx = try container.decodeIfPresent(Double.self, forKey: .leftAx)
        let leftAy = try container.decodeIfPresent(Double.self, forKey: .leftAy)
        let leftAz = try container.decodeIfPresent(Double.self, forKey: .leftAz)
        let leftGx = try container.decodeIfPresent(Double.self, forKey: .leftGx)
        let leftGy = try container.decodeIfPresent(Double.self, forKey: .leftGy)
        let leftGz = try container.decodeIfPresent(Double.self, forKey: .leftGz)
        let rightAx = try container.decodeIfPresent(Double.self, forKey: .rightAx)
        let rightAy = try container.decodeIfPresent(Double.self, forKey: .rightAy)
        let rightAz = try container.decodeIfPresent(Double.self, forKey: .rightAz)
        let rightGx = try container.decodeIfPresent(Double.self, forKey: .rightGx)
        let rightGy = try container.decodeIfPresent(Double.self, forKey: .rightGy)
        let rightGz = try container.decodeIfPresent(Double.self, forKey: .rightGz)
        if leftAx != nil || rightAx != nil {
            self.leftAx = leftAx
            self.leftAy = leftAy
            self.leftAz = leftAz
            self.leftGx = leftGx
            self.leftGy = leftGy
            self.leftGz = leftGz
            self.rightAx = rightAx
            self.rightAy = rightAy
            self.rightAz = rightAz
            self.rightGx = rightGx
            self.rightGy = rightGy
            self.rightGz = rightGz
        } else {
            let legacyAx = try container.decodeIfPresent(Double.self, forKey: .ax)
            let legacyAy = try container.decodeIfPresent(Double.self, forKey: .ay)
            let legacyAz = try container.decodeIfPresent(Double.self, forKey: .az)
            let legacyGx = try container.decodeIfPresent(Double.self, forKey: .gx)
            let legacyGy = try container.decodeIfPresent(Double.self, forKey: .gy)
            let legacyGz = try container.decodeIfPresent(Double.self, forKey: .gz)
            let legacySide = try container.decodeIfPresent(SensorSide.self, forKey: .side)
            switch legacySide {
            case .right:
                self.leftAx = nil
                self.leftAy = nil
                self.leftAz = nil
                self.leftGx = nil
                self.leftGy = nil
                self.leftGz = nil
                self.rightAx = legacyAx
                self.rightAy = legacyAy
                self.rightAz = legacyAz
                self.rightGx = legacyGx
                self.rightGy = legacyGy
                self.rightGz = legacyGz
            case .left, .single, .none:
                self.leftAx = legacyAx
                self.leftAy = legacyAy
                self.leftAz = legacyAz
                self.leftGx = legacyGx
                self.leftGy = legacyGy
                self.leftGz = legacyGz
                self.rightAx = nil
                self.rightAy = nil
                self.rightAz = nil
                self.rightGx = nil
                self.rightGy = nil
                self.rightGz = nil
            }
        }
        speedMetersPerSecond = try container.decodeIfPresent(Double.self, forKey: .speedMetersPerSecond)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        horizontalAccuracy = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(leftAx, forKey: .leftAx)
        try container.encodeIfPresent(leftAy, forKey: .leftAy)
        try container.encodeIfPresent(leftAz, forKey: .leftAz)
        try container.encodeIfPresent(leftGx, forKey: .leftGx)
        try container.encodeIfPresent(leftGy, forKey: .leftGy)
        try container.encodeIfPresent(leftGz, forKey: .leftGz)
        try container.encodeIfPresent(rightAx, forKey: .rightAx)
        try container.encodeIfPresent(rightAy, forKey: .rightAy)
        try container.encodeIfPresent(rightAz, forKey: .rightAz)
        try container.encodeIfPresent(rightGx, forKey: .rightGx)
        try container.encodeIfPresent(rightGy, forKey: .rightGy)
        try container.encodeIfPresent(rightGz, forKey: .rightGz)
        try container.encodeIfPresent(speedMetersPerSecond, forKey: .speedMetersPerSecond)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(horizontalAccuracy, forKey: .horizontalAccuracy)
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
    let calibration: RunCalibration?

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
        case calibration
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
        sensorMode: SensorMode,
        calibration: RunCalibration? = nil
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
        self.calibration = calibration
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
        calibration = try container.decodeIfPresent(RunCalibration.self, forKey: .calibration)
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
        try container.encode(calibration, forKey: .calibration)
    }
}

struct RunCalibration: Codable, Equatable {
    var single: BootCalibration?
    var left: BootCalibration?
    var right: BootCalibration?
}
