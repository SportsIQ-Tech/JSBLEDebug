import Foundation
import CoreBluetooth
import Combine // For ObservableObject and @Published

// Define the UUIDs (matching the JavaScript)
let kServiceUUID = CBUUID(string: "b7063e97-8504-4fcb-b0f5-aef2d5903c4d")
let kQuaternionCharacteristicUUID = CBUUID(string: "71fa0f31-bcc7-42f2-bb57-a9810b436231")

// Simple Quaternion struct to hold data
struct Quaternion {
    var w: Float = 0.0
    var x: Float = 0.0
    var y: Float = 0.0
    var z: Float = 0.0
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var centralManager: CBCentralManager!
    private var kaiTagPeripheral: CBPeripheral?

    @Published var connectionStatus: String = "Disconnected"
    @Published var isConnected: Bool = false
    @Published var quaternion: Quaternion = Quaternion() // Holds the latest quaternion data

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        print("BluetoothManager initialized.")
    }

    // MARK: - CBCentralManagerDelegate Methods

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is Powered On.")
            connectionStatus = "Ready to Scan"
            // Start scanning immediately or provide a button to trigger it
            // startScan()
        case .poweredOff:
            print("Bluetooth is Powered Off.")
            connectionStatus = "Bluetooth Off"
            isConnected = false
            // Handle disconnection if needed
        case .resetting:
            print("Bluetooth is Resetting.")
            connectionStatus = "Resetting..."
            isConnected = false
        case .unauthorized:
            print("Bluetooth is Unauthorized.")
            connectionStatus = "Bluetooth Unauthorized"
            isConnected = false
        case .unknown:
            print("Bluetooth state is Unknown.")
            connectionStatus = "Bluetooth Unknown State"
            isConnected = false
        case .unsupported:
            print("Bluetooth is Unsupported.")
            connectionStatus = "Bluetooth Not Supported"
            isConnected = false
        @unknown default:
            print("A new Bluetooth state was added.")
            connectionStatus = "Bluetooth Unknown State"
            isConnected = false
        }
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            print("Cannot scan, Bluetooth is not powered on.")
            connectionStatus = "Bluetooth not ready"
            return
        }
        // print("Starting scan for KaiTag peripheral with service UUID: \(kServiceUUID)") // Keep this line commented or remove
        print("Starting scan for peripheral with name 'KaiTag'")
        connectionStatus = "Scanning..."
        // Scan for *any* peripherals, filtering will happen in didDiscover
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
         print("Stopping scan.")
         centralManager.stopScan()
         if connectionStatus == "Scanning..." {
             connectionStatus = "Scan stopped"
         }
     }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if the name matches (optional but good practice)
        if let name = peripheral.name, name == "KaiTag" {
            print("Discovered KaiTag: \(name) with RSSI: \(RSSI)")
            kaiTagPeripheral = peripheral
            kaiTagPeripheral?.delegate = self // Set the delegate
            connectionStatus = "KaiTag Found. Connecting..."
            centralManager.stopScan() // Stop scanning once found
            centralManager.connect(kaiTagPeripheral!, options: nil)
        } else if peripheral.name != nil {
            print("Discovered other peripheral: \(peripheral.name ?? "Unknown Name")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "device")")
        connectionStatus = "Connected. Discovering services..."
        isConnected = true
        // Discover the specific service we need
        peripheral.discoverServices([kServiceUUID])
    }

     func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
         print("Failed to connect to \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "Unknown error")")
         connectionStatus = "Connection Failed"
         isConnected = false
         kaiTagPeripheral = nil
         // Optionally restart scanning or implement retry logic
     }

     func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
         print("Disconnected from \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "No error info")")
         connectionStatus = "Disconnected"
         isConnected = false
         kaiTagPeripheral = nil
         quaternion = Quaternion() // Reset quaternion data
         // Implement reconnection logic here if desired, e.g., start scanning again
         // startScan()
     }

    // MARK: - CBPeripheralDelegate Methods

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            connectionStatus = "Error discovering services"
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            print("Discovered service: \(service.uuid)")
            if service.uuid == kServiceUUID {
                connectionStatus = "Service Found. Discovering characteristics..."
                // Discover the specific characteristic we need
                peripheral.discoverCharacteristics([kQuaternionCharacteristicUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            connectionStatus = "Error discovering characteristics"
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == kQuaternionCharacteristicUUID {
                print("Found Quaternion characteristic. Subscribing...")
                connectionStatus = "Subscribing to Quaternion..."
                // Subscribe to notifications
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

     func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
         if let error = error {
             print("Error changing notification state for \(characteristic.uuid): \(error.localizedDescription)")
             connectionStatus = "Subscription Error"
             return
         }

         if characteristic.isNotifying {
             print("Successfully subscribed to notifications for \(characteristic.uuid)")
             connectionStatus = "Connected and Listening"
         } else {
             print("Stopped notifications for \(characteristic.uuid)")
             // This might happen on disconnect
         }
     }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == kQuaternionCharacteristicUUID, let data = characteristic.value else {
            return
        }

        // Parse the quaternion data (4 Float32 values, little-endian)
        // Ensure data is long enough
        guard data.count >= 16 else {
            print("Received data length \(data.count) is less than expected 16 bytes for quaternion.")
            return
        }

        // Extract float values (assuming little-endian like the JS code)
        let w = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Float.self) }
        let x = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Float.self) }
        let y = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: Float.self) }
        let z = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: Float.self) }

        // Update the published property - do this on the main thread for UI updates
        DispatchQueue.main.async {
            self.quaternion = Quaternion(w: w, x: x, y: y, z: z)
           // print("Quaternion Updated: w:\(w), x:\(x), y:\(y), z:\(z)") // Optional: Log updates
        }
    }

    // MARK: - Public Control Methods

    func connect() {
         if kaiTagPeripheral != nil && kaiTagPeripheral?.state == .connected {
             print("Already connected.")
             return
         } else if kaiTagPeripheral != nil && kaiTagPeripheral?.state == .connecting {
             print("Already connecting.")
             return
         } else if kaiTagPeripheral != nil {
             print("Found peripheral, attempting connection...")
             connectionStatus = "Connecting..."
             centralManager.connect(kaiTagPeripheral!, options: nil)
         }
         else {
             print("No peripheral found yet, starting scan.")
             startScan()
         }
     }

    func disconnect() {
        if let peripheral = kaiTagPeripheral {
            if peripheral.state == .connected || peripheral.state == .connecting {
                print("Disconnecting from \(peripheral.name ?? "device")...")
                // Unsubscribe if necessary (CoreBluetooth often handles this on disconnect)
                // Find the characteristic and call setNotifyValue(false, for: char) if needed
                centralManager.cancelPeripheralConnection(peripheral)
            } else {
                 print("Cannot disconnect, peripheral not connected or connecting.")
             }
        } else {
            print("Cannot disconnect, no peripheral reference.")
        }
        // Also stop scanning if it was running
        stopScan()
    }
}

// Helper to access Float from Data easily
extension Data {
    func readFloat(at offset: Int) -> Float {
        // Assumes little-endian based on JS `true` argument
        return self.subdata(in: offset..<(offset+4)).withUnsafeBytes { $0.load(as: Float.self) }
    }
} 