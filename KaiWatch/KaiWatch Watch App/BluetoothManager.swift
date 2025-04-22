import Foundation
import CoreBluetooth
import Combine // Needed for ObservableObject and @Published

// Define the UUIDs (matching your web app)
let kaiTagServiceUUID = CBUUID(string: "b7063e97-8504-4fcb-b0f5-aef2d5903c4d")
let quaternionCharacteristicUUID = CBUUID(string: "71fa0f31-bcc7-42f2-bb57-a9810b436231")

// Simple struct to hold quaternion data
struct Quaternion {
    var w: Float = 0.0
    var x: Float = 0.0
    var y: Float = 0.0
    var z: Float = 0.0
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Published Properties for UI Updates
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Initializing..."
    @Published var lastQuaternion: Quaternion = Quaternion() // Store the latest received quaternion

    // MARK: - Core Bluetooth Properties
    private var centralManager: CBCentralManager!
    private var kaiTagPeripheral: CBPeripheral?

    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil) // Use main queue for simplicity
        print("BluetoothManager Initialized")
    }

    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not powered on"
            print("Cannot scan, Bluetooth is not powered on.")
            // TODO: Prompt user to turn on Bluetooth?
            return
        }

        guard !isConnected else {
            print("Already connected or connecting.")
            return
        }

        // Clear any previously stored peripheral before starting a new scan
        kaiTagPeripheral = nil

        statusMessage = "Scanning for KaiTag by name..."
        print("Starting scan for all peripherals...")
        // Start scanning for ALL peripherals
        centralManager.scanForPeripherals(withServices: nil, options: nil)

        // Optional: Timeout for scanning
        // DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
        //     if self?.kaiTagPeripheral == nil {
        //         self?.centralManager.stopScan()
        //         self?.statusMessage = "KaiTag not found."
        //         print("Scan timed out.")
        //     }
        // }
    }

    func disconnect() {
        guard let peripheral = kaiTagPeripheral else {
            print("No peripheral to disconnect.")
            return
        }
        guard isConnected else {
            print("Not currently connected.")
             // Reset state if needed, e.g., if stuck in a connecting state
            if centralManager.isScanning { centralManager.stopScan() }
            kaiTagPeripheral = nil
            isConnected = false
            statusMessage = "Disconnected"
            return
        }

        print("Disconnecting from \(peripheral.name ?? "device")...")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - CBCentralManagerDelegate Methods

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth Ready. Tap Connect."
            print("CBCentralManager state: poweredOn")
            // Optionally start scanning immediately if desired
            // startScanning()
        case .poweredOff:
            statusMessage = "Bluetooth is Off"
            print("CBCentralManager state: poweredOff")
            isConnected = false // Ensure state is correct
            kaiTagPeripheral = nil // Clear peripheral
        case .resetting:
            statusMessage = "Bluetooth Resetting"
            print("CBCentralManager state: resetting")
            isConnected = false
            kaiTagPeripheral = nil
        case .unauthorized:
            statusMessage = "Bluetooth Unauthorized"
            print("CBCentralManager state: unauthorized")
            // TODO: Guide user to settings
        case .unsupported:
            statusMessage = "Bluetooth Unsupported"
            print("CBCentralManager state: unsupported")
        case .unknown:
            statusMessage = "Bluetooth State Unknown"
            print("CBCentralManager state: unknown")
        @unknown default:
            statusMessage = "Bluetooth State Error"
            print("CBCentralManager state: unknown default")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // We found a peripheral, now check its advertised name
        let peripheralName = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        print("Discovered peripheral: \(peripheralName ?? "(No Name)") [\(peripheral.identifier)] at RSSI: \(RSSI)")

        // Check if the name matches "KaiTag"
        if let name = peripheralName, name == "KaiTag" {
            print("Found KaiTag by name! Connecting...")
            statusMessage = "KaiTag Found. Connecting..."

            // We found our target, store reference and connect
            kaiTagPeripheral = peripheral // Store reference
            kaiTagPeripheral?.delegate = self // Set delegate

            centralManager.stopScan() // Stop scanning once found
            centralManager.connect(peripheral, options: nil)
        } else {
             // It's not the KaiTag, keep scanning (or log if needed)
             // print("Ignoring peripheral \(peripheralName ?? "(No Name)")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == kaiTagPeripheral else { return }

        statusMessage = "Connected. Discovering services..."
        print("Successfully connected to \(peripheral.name ?? "device"). Discovering services...")
        isConnected = true // Update connection state

        // Discover the specific service we need
        peripheral.discoverServices([kaiTagServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
         guard peripheral == kaiTagPeripheral else { return }

        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        print("Failed to connect to \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "Unknown error")")
        isConnected = false
        kaiTagPeripheral = nil // Clear reference on failure
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == kaiTagPeripheral else { return }

        if let error = error {
            statusMessage = "Disconnected with error: \(error.localizedDescription)"
            print("Disconnected from \(peripheral.name ?? "device") with error: \(error.localizedDescription)")
        } else {
            statusMessage = "Disconnected"
            print("Disconnected from \(peripheral.name ?? "device")")
        }
        isConnected = false
        kaiTagPeripheral = nil // Clear reference

        // Optional: Implement automatic reconnection logic here if desired
        // print("Attempting to reconnect...")
        // startScanning() // Or a more robust timer-based reconnect
    }

    // MARK: - CBPeripheralDelegate Methods

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == kaiTagPeripheral else { return }

        if let error = error {
            statusMessage = "Error discovering services: \(error.localizedDescription)"
            print("Error discovering services: \(error.localizedDescription)")
            disconnect() // Disconnect on error
            return
        }

        guard let services = peripheral.services else {
             print("No services found.")
             disconnect()
             return
        }

        print("Discovered services: \(services)")
        statusMessage = "Services Discovered. Discovering characteristics..."

        for service in services {
            if service.uuid == kaiTagServiceUUID {
                print("Found KaiTag service. Discovering characteristics...")
                // Discover the specific characteristic we need
                peripheral.discoverCharacteristics([quaternionCharacteristicUUID], for: service)
                return // Found our service, no need to check others
            }
        }
        print("KaiTag service UUID not found.")
        statusMessage = "Required service not found."
        disconnect()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == kaiTagPeripheral, service.uuid == kaiTagServiceUUID else { return }

        if let error = error {
            statusMessage = "Error discovering characteristics: \(error.localizedDescription)"
            print("Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
            disconnect()
            return
        }

        guard let characteristics = service.characteristics else {
            print("No characteristics found for service \(service.uuid).")
            disconnect()
            return
        }

        print("Discovered characteristics: \(characteristics)")
        statusMessage = "Characteristics Discovered. Enabling notifications..."

        for characteristic in characteristics {
            if characteristic.uuid == quaternionCharacteristicUUID {
                print("Found Quaternion characteristic. Subscribing...")
                // Subscribe to notifications (characteristicvaluechanged)
                peripheral.setNotifyValue(true, for: characteristic)
                return // Found our characteristic
            }
        }
        print("Quaternion characteristic UUID not found.")
        statusMessage = "Required characteristic not found."
        disconnect()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
         guard peripheral == kaiTagPeripheral, characteristic.uuid == quaternionCharacteristicUUID else { return }

         if let error = error {
            statusMessage = "Error changing notification state: \(error.localizedDescription)"
            print("Error changing notification state for \(characteristic.uuid): \(error.localizedDescription)")
            disconnect()
            return
        }

        if characteristic.isNotifying {
            statusMessage = "Subscribed to Quaternion Data"
            print("Successfully subscribed to notifications for Quaternion characteristic.")
            // Optional: Read initial value if needed? Usually notifications are enough.
            // peripheral.readValue(for: characteristic)
        } else {
            statusMessage = "Notifications stopped."
            print("Notifications stopped for \(characteristic.uuid). Disconnecting.")
            // This might happen during disconnect, handle appropriately
            // disconnect() // Consider if disconnect is always right here
        }
    }


    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == kaiTagPeripheral, characteristic.uuid == quaternionCharacteristicUUID else { return }

        if let error = error {
            print("Error receiving notification for \(characteristic.uuid): \(error.localizedDescription)")
            // Decide if you want to disconnect on characteristic read errors
            // statusMessage = "Data read error."
            return
        }

        guard let data = characteristic.value else {
            print("Characteristic value is nil.")
            return
        }

        // Parse the quaternion data (4 x Float32, little-endian)
        guard data.count >= 16 else {
             print("Received data length \(data.count) is less than expected 16 bytes for quaternion.")
             return
        }

        // Use subscripting with range for safety
        let w = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Float.self) }
        let x = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Float.self) }
        let y = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: Float.self) }
        let z = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: Float.self) }

        // Update the published property
        // Run on main thread as it triggers UI updates
        DispatchQueue.main.async {
            self.lastQuaternion = Quaternion(w: w, x: x, y: y, z: z)
            // Optionally normalize here if needed, though usually done on sensor
            // print("Quaternion Updated: w:\(w) x:\(x) y:\(y) z:\(z)") // DEBUG: Reduce frequency if needed
        }
    }
}

// Helper extension for parsing Float from Data (assuming little-endian)
extension Data {
    func readFloat(at offset: Int) -> Float? {
        guard self.count >= offset + MemoryLayout<Float>.size else { return nil }
        // Assuming little-endian based on web code (true parameter in getFloat32)
        let value = self.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        // For big-endian use: Float(bitPattern: UInt32(bigEndian: ...))
        return value
    }
} 