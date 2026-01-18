import Combine
import CoreBluetooth
import Foundation

@MainActor
final class StreamClient: NSObject, ObservableObject {
    @Published private(set) var messages: [String] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var status = "Bluetooth not ready"

    private let deviceName = "Carving-Extreem"
    private let serviceUUID = CBUUID(string: "7a3f0001-3c12-4b50-8d32-9f8c8a3d8f31")
    private let dataCharacteristicUUID = CBUUID(string: "7a3f0002-3c12-4b50-8d32-9f8c8a3d8f31")

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?

    override init() {
        super.init()
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
    }
}
