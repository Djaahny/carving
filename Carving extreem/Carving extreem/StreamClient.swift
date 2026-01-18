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

struct CalibrationState: Codable, Equatable {
    var accelOffset: [Double]
    var gyroOffset: [Double]
    var forwardReference: Double
    var sideReference: Double

    static let empty = CalibrationState(
        accelOffset: [0, 0, 0],
        gyroOffset: [0, 0, 0],
        forwardReference: 0,
        sideReference: 0
    )
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

    private let deviceName = "Carving-Extreem"
    private let serviceUUID = CBUUID(string: "7a3f0001-3c12-4b50-8d32-9f8c8a3d8f31")
    private let dataCharacteristicUUID = CBUUID(string: "7a3f0002-3c12-4b50-8d32-9f8c8a3d8f31")
    private let savedPeripheralKey = "lastPeripheralIdentifier"
    private let savedPeripheralNameKey = "lastPeripheralName"
    private let calibrationKey = "calibrationState"

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?

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
        guard parts.count == 6 else {
            return trimmed
        }

        return "a:\(parts[0]),\(parts[1]),\(parts[2]) g:\(parts[3]),\(parts[4]),\(parts[5])"
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

        let sample = SensorSample(ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz)
        latestSample = sample
        latestEdgeAngle = computeEdgeAngle(from: sample)
    }

    private func computeEdgeAngle(from sample: SensorSample) -> Double {
        let ax = sample.ax - calibrationState.accelOffset[0]
        let ay = sample.ay - calibrationState.accelOffset[1]
        let az = sample.az - calibrationState.accelOffset[2]
        let roll = atan2(ay, az) * 180 / .pi
        let adjusted = abs(roll - calibrationState.sideReference)
        return min(max(adjusted, 0), 90)
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
        saveCalibration(state)
    }

    func captureForwardReference() {
        guard let sample = latestSample else { return }
        let ax = sample.ax - calibrationState.accelOffset[0]
        let ay = sample.ay - calibrationState.accelOffset[1]
        let az = sample.az - calibrationState.accelOffset[2]
        let pitch = atan2(-ax, sqrt(ay * ay + az * az)) * 180 / .pi
        var state = calibrationState
        state.forwardReference = pitch
        saveCalibration(state)
    }

    func captureSideReference() {
        guard let sample = latestSample else { return }
        let ay = sample.ay - calibrationState.accelOffset[1]
        let az = sample.az - calibrationState.accelOffset[2]
        let roll = atan2(ay, az) * 180 / .pi
        var state = calibrationState
        state.sideReference = roll
        saveCalibration(state)
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
