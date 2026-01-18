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

struct EdgeSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let angle: Double
}

struct AccelSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
}

struct CalibratedAccel: Equatable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = CalibratedAccel(x: 0, y: 0, z: 0)
}

struct CalibrationState: Codable, Equatable {
    var accelOffset: [Double]
    var gyroOffset: [Double]
    var forwardReference: Double
    var sideReference: Double
    var isCalibrated: Bool

    static let empty = CalibrationState(
        accelOffset: [0, 0, 0],
        gyroOffset: [0, 0, 0],
        forwardReference: 0,
        sideReference: 0,
        isCalibrated: false
    )
}

private struct Vector3 {
    var x: Double
    var y: Double
    var z: Double

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
    @Published private(set) var calibrationState: CalibrationState = .empty
    @Published private(set) var accelSamples: [AccelSample] = []
    @Published private(set) var latestCalibratedAccel: CalibratedAccel = .zero

    private let deviceName = "Carving-Extreem"
    private let serviceUUID = CBUUID(string: "7a3f0001-3c12-4b50-8d32-9f8c8a3d8f31")
    private let dataCharacteristicUUID = CBUUID(string: "7a3f0002-3c12-4b50-8d32-9f8c8a3d8f31")
    private let savedPeripheralKey = "lastPeripheralIdentifier"
    private let savedPeripheralNameKey = "lastPeripheralName"
    private let calibrationKey = "calibrationState"
    private let gravity = 9.80665
    private let radiansToDegrees = 180.0 / Double.pi
    private let edgeAngleSmoothingAlpha = 0.18
    private let accelWindowSeconds: TimeInterval = 5
    private let rotationEpsilon = 1e-6

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var smoothedEdgeAngle: Double?

    override init() {
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
        updateCalibratedAccel(from: sample)
        let rawEdgeAngle = computeEdgeAngle(from: sample)
        if let smoothedEdgeAngle {
            self.smoothedEdgeAngle = smoothedEdgeAngle + edgeAngleSmoothingAlpha * (rawEdgeAngle - smoothedEdgeAngle)
        } else {
            smoothedEdgeAngle = rawEdgeAngle
        }
        latestEdgeAngle = smoothedEdgeAngle ?? rawEdgeAngle
    }

    private func computeEdgeAngle(from sample: SensorSample) -> Double {
        guard calibrationState.isCalibrated else { return 0 }
        let pitchRoll = pitchRoll(from: sample)
        let alignedRoll = pitchRoll.roll - calibrationState.sideReference
        let adjusted = abs(alignedRoll)
        return min(max(adjusted, 0), 90)
    }

    private func updateCalibratedAccel(from sample: SensorSample) {
        let leveled = leveledAccel(from: sample)
        let calibrated = CalibratedAccel(x: leveled.x, y: leveled.y, z: leveled.z)
        latestCalibratedAccel = calibrated
        let timestamp = Date()
        accelSamples.append(AccelSample(timestamp: timestamp, x: calibrated.x, y: calibrated.y, z: calibrated.z))
        let cutoff = timestamp.addingTimeInterval(-accelWindowSeconds)
        accelSamples.removeAll { $0.timestamp < cutoff }
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

    func captureZeroCalibration() {
        guard let sample = latestSample else { return }
        var state = calibrationState
        state.accelOffset = [sample.ax, sample.ay, sample.az]
        state.gyroOffset = [sample.gx, sample.gy, sample.gz]
        state.forwardReference = 0
        state.sideReference = 0
        state.isCalibrated = false
        saveCalibration(state)
    }

    func captureZeroCalibration(samples: [SensorSample]) {
        guard !samples.isEmpty else { return }
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
        var state = calibrationState
        state.accelOffset = [totalAccel.x / count, totalAccel.y / count, totalAccel.z / count]
        state.gyroOffset = [totalGyro.x / count, totalGyro.y / count, totalGyro.z / count]
        state.forwardReference = 0
        state.sideReference = 0
        state.isCalibrated = false
        saveCalibration(state)
    }

    func captureForwardReference() {
        guard let sample = latestSample else { return }
        let pitch = pitchRoll(from: sample).pitch
        var state = calibrationState
        state.forwardReference = pitch
        state.isCalibrated = false
        saveCalibration(state)
    }

    func captureSideReference() {
        guard let sample = latestSample else { return }
        let roll = pitchRoll(from: sample).roll
        var state = calibrationState
        state.sideReference = roll
        state.isCalibrated = true
        saveCalibration(state)
    }

    func captureSideReference(roll: Double) {
        var state = calibrationState
        state.sideReference = roll
        state.isCalibrated = true
        saveCalibration(state)
    }

    func pitchRoll(from sample: SensorSample) -> (pitch: Double, roll: Double) {
        let leveled = leveledAccel(from: sample)
        let roll = atan2(leveled.y, leveled.z) * 180 / .pi
        let pitch = atan2(-leveled.x, sqrt(leveled.y * leveled.y + leveled.z * leveled.z)) * 180 / .pi
        return (pitch, roll)
    }

    private func leveledAccel(from sample: SensorSample) -> Vector3 {
        let raw = Vector3(x: sample.ax, y: sample.ay, z: sample.az)
        let flat = Vector3(
            x: calibrationState.accelOffset[0],
            y: calibrationState.accelOffset[1],
            z: calibrationState.accelOffset[2]
        )
        return rotateVector(raw, aligning: flat)
    }

    private func rotateVector(_ vector: Vector3, aligning flatReference: Vector3) -> Vector3 {
        let flatLength = flatReference.length
        guard flatLength > rotationEpsilon else {
            return vector
        }
        let from = flatReference.normalized
        let to = Vector3(x: 0, y: 0, z: 1)
        let dotValue = max(min(Vector3.dot(from, to), 1), -1)
        let angle = acos(dotValue)
        if angle < rotationEpsilon {
            return vector
        }
        let axis = Vector3.cross(from, to)
        let axisLength = axis.length
        guard axisLength > rotationEpsilon else {
            return Vector3(x: -vector.x, y: -vector.y, z: -vector.z)
        }
        let normalizedAxis = axis.normalized
        return rotate(vector, axis: normalizedAxis, angle: angle)
    }

    private func rotate(_ vector: Vector3, axis: Vector3, angle: Double) -> Vector3 {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let term1 = Vector3(
            x: vector.x * cosAngle,
            y: vector.y * cosAngle,
            z: vector.z * cosAngle
        )
        let cross = Vector3.cross(axis, vector)
        let term2 = Vector3(
            x: cross.x * sinAngle,
            y: cross.y * sinAngle,
            z: cross.z * sinAngle
        )
        let dot = Vector3.dot(axis, vector)
        let term3 = Vector3(
            x: axis.x * dot * (1 - cosAngle),
            y: axis.y * dot * (1 - cosAngle),
            z: axis.z * dot * (1 - cosAngle)
        )
        return Vector3(
            x: term1.x + term2.x + term3.x,
            y: term1.y + term2.y + term3.y,
            z: term1.z + term2.z + term3.z
        )
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
