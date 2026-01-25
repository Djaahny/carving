import Combine
import CoreBluetooth
import Foundation

struct SensorSample: Equatable {
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double
}

struct EdgeSample: Identifiable, Codable {
    var id: UUID
    let timestamp: Date
    let angle: Double
    let side: SensorSide

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case angle
        case side
    }

    init(id: UUID = UUID(), timestamp: Date, angle: Double, side: SensorSide) {
        self.id = id
        self.timestamp = timestamp
        self.angle = angle
        self.side = side
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        angle = try container.decode(Double.self, forKey: .angle)
        side = try container.decode(SensorSide.self, forKey: .side)
    }
}

struct CalibratedAccel: Equatable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = CalibratedAccel(x: 0, y: 0, z: 0)
}

struct CalibrationState: Codable, Equatable {
    var rotationMatrix: [[Double]]
    var gyroBias: [Double]
    var accelScale: Double
    var zAxis: [Double]
    var isCalibrated: Bool

    static let empty = CalibrationState(
        rotationMatrix: [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
        ],
        gyroBias: [0, 0, 0],
        accelScale: 1,
        zAxis: [0, 0, 1],
        isCalibrated: false
    )

    private enum CodingKeys: String, CodingKey {
        case rotationMatrix
        case gyroBias
        case accelScale
        case zAxis
        case isCalibrated
    }

    init(
        rotationMatrix: [[Double]],
        gyroBias: [Double],
        accelScale: Double,
        zAxis: [Double],
        isCalibrated: Bool
    ) {
        self.rotationMatrix = rotationMatrix
        self.gyroBias = gyroBias
        self.accelScale = accelScale
        self.zAxis = zAxis
        self.isCalibrated = isCalibrated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rotationMatrix = try container.decodeIfPresent([[Double]].self, forKey: .rotationMatrix) ?? [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
        ]
        gyroBias = try container.decodeIfPresent([Double].self, forKey: .gyroBias) ?? [0, 0, 0]
        accelScale = try container.decodeIfPresent(Double.self, forKey: .accelScale) ?? 1
        zAxis = try container.decodeIfPresent([Double].self, forKey: .zAxis) ?? [0, 0, 1]
        isCalibrated = try container.decodeIfPresent(Bool.self, forKey: .isCalibrated) ?? false
    }
}

private struct Vector3 {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var length: Double {
        sqrt(x * x + y * y + z * z)
    }

    var normalized: Vector3 {
        let len = length
        guard len > 0 else { return self }
        return Vector3(x: x / len, y: y / len, z: z / len)
    }

    static func dot(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    static func cross(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}

struct BootCalibration: Codable, Equatable {
    let rotationMatrix: [[Double]]
    let gyroBias: [Double]
    let accelScale: Double
}

private struct PendingCalibration {
    let zAxis: Vector3
    let gyroBias: Vector3
    let accelScale: Double
    let meanAccel: Vector3
    let meanGyro: Vector3
}

enum CalibrationResult {
    case success
    case failure(String)
}

@MainActor
final class StreamClient: NSObject, ObservableObject {
    @Published private(set) var messages: [String] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var status = "Bluetooth not ready"
    @Published private(set) var lastKnownSensorName: String?
    @Published private(set) var latestSample: SensorSample?
    @Published private(set) var latestEdgeAngle: Double = 0
    @Published private(set) var latestSignedEdgeAngle: Double = 0
    @Published private(set) var calibrationState: CalibrationState = .empty
    @Published private(set) var latestCalibratedAccel: CalibratedAccel = .zero
    @Published private(set) var latestAccelMagnitude: Double = 0
    @Published private(set) var lastShockTimestamp: Date?
    @Published private(set) var lastShockMagnitude: Double = 0
    @Published private(set) var connectedIdentifier: String?

    private let deviceName: String
    private let serviceUUID = CBUUID(string: "7a3f0001-3c12-4b50-8d32-9f8c8a3d8f31")
    private let dataCharacteristicUUID = CBUUID(string: "7a3f0002-3c12-4b50-8d32-9f8c8a3d8f31")
    private let savedPeripheralKey: String
    private let savedPeripheralNameKey: String
    private let calibrationKey: String
    private let gravity = 9.80665
    private let radiansToDegrees = 180.0 / Double.pi
    private let edgeAngleSmoothingAlpha = 0.18
    private let shockThreshold = 2.5
    private let shockCooldown: TimeInterval = 0.8
    private let rotationEpsilon = 1e-6
    private let stillnessAccelStdDevThreshold = 0.05
    private let stillnessGyroStdDevThreshold = 2.0
    private let alignmentReferenceThreshold = 0.75
    private let edgeHoldMinSampleCount = 10
    private let edgeHoldMinSeparationDegrees = 25.0

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var smoothedEdgeAngle: Double?
    private var smoothedSignedEdgeAngle: Double?
    private var pendingStationaryCalibration: PendingCalibration?

    init(deviceName: String = "Carving-Extreem", storageSuffix: String) {
        self.deviceName = deviceName
        savedPeripheralKey = "lastPeripheralIdentifier.\(storageSuffix)"
        savedPeripheralNameKey = "lastPeripheralName.\(storageSuffix)"
        calibrationKey = "calibrationState.\(storageSuffix)"
        super.init()
        calibrationState = loadCalibration()
        lastKnownSensorName = UserDefaults.standard.string(forKey: savedPeripheralNameKey)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connect() {
        guard centralManager.state == .poweredOn else {
            status = "Bluetooth is unavailable"
            return
        }

        if isScanning {
            return
        }

        if let cachedPeripheral = retrieveCachedPeripheral() {
            status = "Connecting to \(cachedPeripheral.name ?? deviceName)…"
            peripheral = cachedPeripheral
            cachedPeripheral.delegate = self
            centralManager.connect(cachedPeripheral, options: nil)
            return
        }

        status = "Scanning for \(deviceName)…"
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func disconnect() {
        stopScan()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState(statusText: "Disconnected")
    }

    private func stopScan() {
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }
    }

    private func resetConnectionState(statusText: String) {
        isConnected = false
        status = statusText
        peripheral = nil
        dataCharacteristic = nil
        connectedIdentifier = nil
    }

    private func retrieveCachedPeripheral() -> CBPeripheral? {
        guard let uuidString = UserDefaults.standard.string(forKey: savedPeripheralKey),
              let uuid = UUID(uuidString: uuidString)
        else {
            return nil
        }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        return peripherals.first
    }

    private func saveLastPeripheral(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedPeripheralKey)
        if let name = peripheral.name {
            UserDefaults.standard.set(name, forKey: savedPeripheralNameKey)
            lastKnownSensorName = name
        }
    }

    private func appendMessage(_ message: String) {
        messages.append(message)
        let maxMessages = 200
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    private func formattedMessage(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: true)
        guard parts.count == 6,
              let ax = Double(parts[0]),
              let ay = Double(parts[1]),
              let az = Double(parts[2]),
              let gx = Double(parts[3]),
              let gy = Double(parts[4]),
              let gz = Double(parts[5])
        else {
            return trimmed
        }

        let accelInG = [ax, ay, az].map { $0 / gravity }
        let gyroInDeg = [gx, gy, gz].map { $0 * radiansToDegrees }
        return String(
            format: "a:%.3f,%.3f,%.3f g:%.2f,%.2f,%.2f",
            accelInG[0],
            accelInG[1],
            accelInG[2],
            gyroInDeg[0],
            gyroInDeg[1],
            gyroInDeg[2]
        )
    }

    private func updateSample(from raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: true)
        guard parts.count == 6,
              let ax = Double(parts[0]),
              let ay = Double(parts[1]),
              let az = Double(parts[2]),
              let gx = Double(parts[3]),
              let gy = Double(parts[4]),
              let gz = Double(parts[5])
        else {
            return
        }

        let sample = SensorSample(
            ax: ax / gravity,
            ay: ay / gravity,
            az: az / gravity,
            gx: gx * radiansToDegrees,
            gy: gy * radiansToDegrees,
            gz: gz * radiansToDegrees
        )
        latestSample = sample
        updateShockState(for: sample)
        updateCalibratedAccel(from: sample)
        let edgeAngles = computeEdgeAngles(from: sample)
        let rawEdgeAngle = edgeAngles.magnitude
        if let smoothedEdgeAngle {
            self.smoothedEdgeAngle = smoothedEdgeAngle + edgeAngleSmoothingAlpha * (rawEdgeAngle - smoothedEdgeAngle)
        } else {
            smoothedEdgeAngle = rawEdgeAngle
        }
        latestEdgeAngle = smoothedEdgeAngle ?? rawEdgeAngle
        let rawSignedEdgeAngle = edgeAngles.signed
        if let smoothedSignedEdgeAngle {
            self.smoothedSignedEdgeAngle = smoothedSignedEdgeAngle + edgeAngleSmoothingAlpha * (rawSignedEdgeAngle - smoothedSignedEdgeAngle)
        } else {
            smoothedSignedEdgeAngle = rawSignedEdgeAngle
        }
        latestSignedEdgeAngle = smoothedSignedEdgeAngle ?? rawSignedEdgeAngle
    }

    private func updateShockState(for sample: SensorSample) {
        let magnitude = sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
        latestAccelMagnitude = magnitude
        let now = Date()
        if magnitude >= shockThreshold {
            if let lastShockTimestamp, now.timeIntervalSince(lastShockTimestamp) < shockCooldown {
                return
            }
            lastShockTimestamp = now
            lastShockMagnitude = magnitude
        }
    }

    private func computeEdgeAngles(from sample: SensorSample) -> (signed: Double, magnitude: Double) {
        guard let accel = bootFrame(from: sample)?.accel else { return (0, 0) }
        let roll = normalizedRollDegrees(from: accel)
        let signed = min(max(roll, -90), 90)
        let magnitude = min(max(abs(roll), 0), 90)
        return (signed, magnitude)
    }

    private func updateCalibratedAccel(from sample: SensorSample) {
        let accel = bootFrame(from: sample)?.accel
            ?? Vector3(x: sample.ax, y: sample.ay, z: sample.az)
        let calibrated = CalibratedAccel(x: accel.x, y: accel.y, z: accel.z)
        latestCalibratedAccel = calibrated
    }

    private func saveCalibration(_ state: CalibrationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: calibrationKey)
        calibrationState = state
    }

    private func loadCalibration() -> CalibrationState {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey),
              let state = try? JSONDecoder().decode(CalibrationState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    func captureStationaryCalibration(samples: [SensorSample]) -> CalibrationResult {
        guard !samples.isEmpty else {
            return .failure("No samples captured yet. Make sure the sensor is streaming and try again.")
        }

        let count = Double(samples.count)
        let totalAccel = samples.reduce(into: (x: 0.0, y: 0.0, z: 0.0)) { result, sample in
            result.x += sample.ax
            result.y += sample.ay
            result.z += sample.az
        }
        let totalGyro = samples.reduce(into: (x: 0.0, y: 0.0, z: 0.0)) { result, sample in
            result.x += sample.gx
            result.y += sample.gy
            result.z += sample.gz
        }
        let meanAccel = Vector3(
            x: totalAccel.x / count,
            y: totalAccel.y / count,
            z: totalAccel.z / count
        )
        let meanGyro = Vector3(
            x: totalGyro.x / count,
            y: totalGyro.y / count,
            z: totalGyro.z / count
        )
        let accelMagnitude = samples.map { sample in
            sqrt(sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az)
        }
        let gyroMagnitude = samples.map { sample in
            sqrt(sample.gx * sample.gx + sample.gy * sample.gy + sample.gz * sample.gz)
        }
        let accelStdDev = standardDeviation(values: accelMagnitude)
        let gyroStdDev = standardDeviation(values: gyroMagnitude)
        guard accelStdDev <= stillnessAccelStdDevThreshold, gyroStdDev <= stillnessGyroStdDevThreshold else {
            return .failure(
                "Too much movement detected. Keep the boot still for 2 seconds (no stamping or sliding). " +
                "Accel σ \(Self.formatDecimal(accelStdDev)) (max \(Self.formatDecimal(stillnessAccelStdDevThreshold))), " +
                "gyro σ \(Self.formatDecimal(gyroStdDev)) (max \(Self.formatDecimal(stillnessGyroStdDevThreshold)))."
            )
        }

        let accelNorm = meanAccel.length
        guard accelNorm > rotationEpsilon else {
            return .failure(
                "Gravity signal was too small. Set the boot flat on the snow and try again. " +
                "Magnitude \(Self.formatDecimal(accelNorm)) (min \(Self.formatDecimal(rotationEpsilon)))."
            )
        }
        let accelScale = 1.0 / accelNorm
        let gHat = meanAccel.normalized
        let zAxis = Vector3(x: -gHat.x, y: -gHat.y, z: -gHat.z)
        let levelRotation = levelRotationMatrix(for: zAxis)

        pendingStationaryCalibration = PendingCalibration(
            zAxis: zAxis,
            gyroBias: meanGyro,
            accelScale: accelScale,
            meanAccel: meanAccel,
            meanGyro: meanGyro
        )

        var state = calibrationState
        state.gyroBias = [meanGyro.x, meanGyro.y, meanGyro.z]
        state.accelScale = accelScale
        state.zAxis = [zAxis.x, zAxis.y, zAxis.z]
        state.rotationMatrix = levelRotation
        state.isCalibrated = false
        saveCalibration(state)
        return .success
    }

    func captureForwardCalibration(edgeOneSamples: [SensorSample], edgeTwoSamples: [SensorSample]) -> CalibrationResult {
        guard let pending = pendingStationaryCalibration else {
            return .failure("Finish the stillness step first, then start the edge holds.")
        }
        guard edgeOneSamples.count >= edgeHoldMinSampleCount else {
            return .failure("Not enough samples for the first edge hold. Keep the boot steady on the edge for 2 seconds.")
        }
        guard edgeTwoSamples.count >= edgeHoldMinSampleCount else {
            return .failure("Not enough samples for the second edge hold. Hold the opposite edge for 2 seconds.")
        }
        let edgeOneMean = meanAccel(from: edgeOneSamples) * pending.accelScale
        let edgeTwoMean = meanAccel(from: edgeTwoSamples) * pending.accelScale
        let edgeOneGravity = edgeOneMean.normalized
        let edgeTwoGravity = edgeTwoMean.normalized
        let dot = max(min(Vector3.dot(edgeOneGravity, edgeTwoGravity), 1.0), -1.0)
        let separationAngle = acos(dot) * radiansToDegrees
        guard separationAngle >= edgeHoldMinSeparationDegrees else {
            return .failure(
                "Edge holds were too similar. Tilt further edge-to-edge before holding. " +
                "Separation \(Self.formatDecimal(separationAngle))° (min \(Self.formatDecimal(edgeHoldMinSeparationDegrees))°)."
            )
        }
        let forwardAxis = Vector3.cross(edgeOneGravity, edgeTwoGravity)

        let zAxis = pending.zAxis.normalized
        let xTemp = forwardAxis - zAxis * Vector3.dot(forwardAxis, zAxis)
        guard xTemp.length > rotationEpsilon else {
            return .failure(
                "Edge axis looked vertical. Keep the boot flat and tilt side to side. " +
                "Projection \(Self.formatDecimal(xTemp.length)) (min \(Self.formatDecimal(rotationEpsilon)))."
            )
        }
        let xAxis = xTemp.normalized
        let crossMagnitude = Vector3.cross(zAxis, xAxis).length
        guard crossMagnitude > 0.1 else {
            return .failure(
                "Roll axis was too close to gravity. Keep the boot flat and avoid twisting. " +
                "Cross magnitude \(Self.formatDecimal(crossMagnitude)) (min 0.100)."
            )
        }
        let yAxis = Vector3.cross(zAxis, xAxis).normalized
        let correctedXAxis = Vector3.cross(yAxis, zAxis)

        let rotationMatrix = [
            [correctedXAxis.x, correctedXAxis.y, correctedXAxis.z],
            [yAxis.x, yAxis.y, yAxis.z],
            [zAxis.x, zAxis.y, zAxis.z]
        ]

        if let validationFailure = validateCalibration(
            rotationMatrix: rotationMatrix,
            accelScale: pending.accelScale,
            meanAccel: pending.meanAccel,
            gyroBias: pending.gyroBias
        ) {
            return .failure(validationFailure)
        }

        var state = calibrationState
        state.rotationMatrix = rotationMatrix
        state.gyroBias = [pending.gyroBias.x, pending.gyroBias.y, pending.gyroBias.z]
        state.accelScale = pending.accelScale
        state.zAxis = [zAxis.x, zAxis.y, zAxis.z]
        state.isCalibrated = true
        saveCalibration(state)
        pendingStationaryCalibration = nil
        return .success
    }

    func pitchRoll(from sample: SensorSample) -> (pitch: Double, roll: Double) {
        let accel = bootFrame(from: sample)?.accel
            ?? Vector3(x: sample.ax, y: sample.ay, z: sample.az)
        let roll = normalizedRollDegrees(from: accel)
        let pitch = atan2(accel.x, sqrt(accel.y * accel.y + accel.z * accel.z)) * radiansToDegrees
        return (pitch, roll)
    }

    private func normalizedRollDegrees(from accel: Vector3) -> Double {
        let rawRoll = atan2(accel.y, accel.z) * radiansToDegrees
        if rawRoll > 90 {
            return rawRoll - 180
        }
        if rawRoll < -90 {
            return rawRoll + 180
        }
        return rawRoll
    }

    func calibratedSample(from sample: SensorSample) -> SensorSample {
        if let bootFrame = bootFrame(from: sample) {
            return SensorSample(
                ax: bootFrame.accel.x,
                ay: bootFrame.accel.y,
                az: bootFrame.accel.z,
                gx: bootFrame.gyro.x,
                gy: bootFrame.gyro.y,
                gz: bootFrame.gyro.z
            )
        }
        return sample
    }

    func currentBootCalibration() -> BootCalibration? {
        guard calibrationState.isCalibrated else { return nil }
        return BootCalibration(
            rotationMatrix: calibrationState.rotationMatrix,
            gyroBias: calibrationState.gyroBias,
            accelScale: calibrationState.accelScale
        )
    }

    private func bootFrame(from sample: SensorSample) -> (accel: Vector3, gyro: Vector3)? {
        guard shouldApplyCalibration else { return nil }
        let matrix = normalizedRotationMatrix(calibrationState.rotationMatrix)
        let accelScaled = Vector3(
            x: sample.ax * calibrationState.accelScale,
            y: sample.ay * calibrationState.accelScale,
            z: sample.az * calibrationState.accelScale
        )
        let gyroUnbiased = Vector3(
            x: sample.gx - calibrationState.gyroBias[0],
            y: sample.gy - calibrationState.gyroBias[1],
            z: sample.gz - calibrationState.gyroBias[2]
        )
        let accelBoot = applyRotation(matrix, to: accelScaled)
        let gyroBoot = applyRotation(matrix, to: gyroUnbiased)
        return (accelBoot, gyroBoot)
    }

    private var shouldApplyCalibration: Bool {
        if calibrationState.isCalibrated {
            return true
        }
        let hasBias = calibrationState.gyroBias.contains { abs($0) > rotationEpsilon }
        let hasScale = abs(calibrationState.accelScale - 1.0) > rotationEpsilon
        let hasLevelAlignment = calibrationState.zAxis.contains { abs($0) > rotationEpsilon } &&
            !(abs(calibrationState.zAxis[0]) < rotationEpsilon &&
              abs(calibrationState.zAxis[1]) < rotationEpsilon &&
              abs(calibrationState.zAxis[2] - 1.0) < rotationEpsilon)
        return hasBias || hasScale || hasLevelAlignment
    }

    private func levelRotationMatrix(for zAxis: Vector3) -> [[Double]] {
        let z = zAxis.normalized
        let reference: Vector3
        if abs(z.x) < alignmentReferenceThreshold {
            reference = Vector3(x: 1, y: 0, z: 0)
        } else {
            reference = Vector3(x: 0, y: 1, z: 0)
        }
        let xTemp = reference - z * Vector3.dot(reference, z)
        let xAxis = xTemp.length > rotationEpsilon ? xTemp.normalized : Vector3(x: 0, y: 1, z: 0)
        let yAxis = Vector3.cross(z, xAxis).normalized
        let correctedXAxis = Vector3.cross(yAxis, z)
        return [
            [correctedXAxis.x, correctedXAxis.y, correctedXAxis.z],
            [yAxis.x, yAxis.y, yAxis.z],
            [z.x, z.y, z.z]
        ]
    }

    private func normalizedRotationMatrix(_ matrix: [[Double]]) -> [[Double]] {
        guard matrix.count == 3,
              matrix.allSatisfy({ $0.count == 3 }) else {
            return [
                [1, 0, 0],
                [0, 1, 0],
                [0, 0, 1]
            ]
        }
        return matrix
    }

    private func applyRotation(_ matrix: [[Double]], to vector: Vector3) -> Vector3 {
        Vector3(
            x: matrix[0][0] * vector.x + matrix[0][1] * vector.y + matrix[0][2] * vector.z,
            y: matrix[1][0] * vector.x + matrix[1][1] * vector.y + matrix[1][2] * vector.z,
            z: matrix[2][0] * vector.x + matrix[2][1] * vector.y + matrix[2][2] * vector.z
        )
    }

    private func meanAccel(from samples: [SensorSample]) -> Vector3 {
        guard !samples.isEmpty else { return .zero }
        let total = samples.reduce(Vector3.zero) { total, sample in
            total + Vector3(x: sample.ax, y: sample.ay, z: sample.az)
        }
        return total * (1.0 / Double(samples.count))
    }

    private func standardDeviation(values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private func validateCalibration(
        rotationMatrix: [[Double]],
        accelScale: Double,
        meanAccel: Vector3,
        gyroBias: Vector3
    ) -> String? {
        let scaledAccel = Vector3(
            x: meanAccel.x * accelScale,
            y: meanAccel.y * accelScale,
            z: meanAccel.z * accelScale
        )
        let accelBoot = applyRotation(rotationMatrix, to: scaledAccel)
        let stationaryAccelTolerance = 0.25
        let accelBootAbsZ = abs(accelBoot.z)
        if abs(accelBootAbsZ - 1.0) > stationaryAccelTolerance
            || abs(accelBoot.x) > stationaryAccelTolerance
            || abs(accelBoot.y) > stationaryAccelTolerance {
            return """
            Calibration check failed. Try holding the boot still during step 1. \
            Ax \(Self.formatDecimal(accelBoot.x)), Ay \(Self.formatDecimal(accelBoot.y)), Az \(Self.formatDecimal(accelBoot.z)) (target 0, 0, ±1 ±\(Self.formatDecimal(stationaryAccelTolerance))).
            """
        }
        let gyroBoot = applyRotation(rotationMatrix, to: gyroBias)
        let gyroMagnitude = gyroBoot.length
        if gyroMagnitude > 3.0 {
            return "Gyro bias looks too high. Re-run the stationary step. Magnitude \(Self.formatDecimal(gyroMagnitude)) (max 3.000)."
        }
        return nil
    }

    nonisolated private static func formatDecimal(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

extension StreamClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Ready to scan"
        case .poweredOff:
            resetConnectionState(statusText: "Bluetooth is off")
        case .unauthorized:
            resetConnectionState(statusText: "Bluetooth unauthorized")
        case .unsupported:
            resetConnectionState(statusText: "Bluetooth unsupported")
        case .resetting:
            resetConnectionState(statusText: "Bluetooth resetting")
        case .unknown:
            resetConnectionState(statusText: "Bluetooth state unknown")
        @unknown default:
            resetConnectionState(statusText: "Bluetooth error")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard peripheral.name == deviceName || advertisedName == deviceName else {
            return
        }

        stopScan()
        status = "Connecting to \(deviceName)…"
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Discovering services…"
        isConnected = true
        connectedIdentifier = peripheral.identifier.uuidString
        saveLastPeripheral(peripheral)
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resetConnectionState(statusText: "Failed to connect")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let statusText = error == nil ? "Disconnected" : "Disconnected: \(error?.localizedDescription ?? "Error")"
        resetConnectionState(statusText: statusText)
    }
}

extension StreamClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            resetConnectionState(statusText: "Service error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            resetConnectionState(statusText: "Service missing")
            return
        }

        for service in services where service.uuid == serviceUUID {
            status = "Discovering characteristics…"
            peripheral.discoverCharacteristics([dataCharacteristicUUID], for: service)
            return
        }

        resetConnectionState(statusText: "Service not found")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            resetConnectionState(statusText: "Characteristic error: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            resetConnectionState(statusText: "Characteristic missing")
            return
        }

        for characteristic in characteristics where characteristic.uuid == dataCharacteristicUUID {
            dataCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            status = "Subscribing to data…"
            return
        }

        resetConnectionState(statusText: "Data characteristic not found")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            resetConnectionState(statusText: "Notify error: \(error.localizedDescription)")
            return
        }

        guard characteristic.isNotifying else {
            resetConnectionState(statusText: "Notifications stopped")
            return
        }

        status = "Streaming \(deviceName)"
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            status = "Data error: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else { return }
        let raw = String(decoding: data, as: UTF8.self)
        let formatted = formattedMessage(from: raw)
        appendMessage(formatted)
        updateSample(from: raw)
    }
}
