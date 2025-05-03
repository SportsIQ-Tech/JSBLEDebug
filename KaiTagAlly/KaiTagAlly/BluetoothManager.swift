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
    private var reconnectTimer: Timer? // Timer for reconnection attempts

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
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Ready to Scan"
            }
            // Consider starting scan automatically or waiting for user action
            // startScan()
        case .poweredOff:
            print("Bluetooth is Powered Off.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Bluetooth Off"
                self.isConnected = false
                self.invalidateReconnectTimer() // Stop trying to reconnect if BT is off
            }
        case .resetting:
            print("Bluetooth is Resetting.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Resetting..."
                self.isConnected = false
                self.invalidateReconnectTimer()
            }
        case .unauthorized:
            print("Bluetooth is Unauthorized.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Bluetooth Unauthorized"
                self.isConnected = false
                self.invalidateReconnectTimer()
            }
        case .unknown:
            print("Bluetooth state is Unknown.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Bluetooth Unknown State"
                self.isConnected = false
                self.invalidateReconnectTimer()
            }
        case .unsupported:
            print("Bluetooth is Unsupported.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Bluetooth Not Supported"
                self.isConnected = false
                self.invalidateReconnectTimer()
            }
        @unknown default:
            print("A new Bluetooth state was added.")
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "Bluetooth Unknown State"
                self.isConnected = false
                self.invalidateReconnectTimer()
            }
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
        // Update status on main thread
        DispatchQueue.main.async {
            self.connectionStatus = "Scanning..."
        }
        // Scan for *any* peripherals, filtering will happen in didDiscover
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
         print("Stopping scan.")
         centralManager.stopScan()
         // Update status on main thread only if currently scanning
         DispatchQueue.main.async {
             if self.connectionStatus == "Scanning..." {
                 self.connectionStatus = "Scan stopped"
             }
         }
     }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if the name matches (optional but good practice)
        if let name = peripheral.name, name == "KaiTag" {
            print("Discovered KaiTag: \(name) with RSSI: \(RSSI)")
            kaiTagPeripheral = peripheral
            kaiTagPeripheral?.delegate = self // Set the delegate
            // Update status on main thread
            DispatchQueue.main.async {
                self.connectionStatus = "KaiTag Found. Connecting..."
            }
            centralManager.stopScan() // Stop scanning once found
            centralManager.connect(kaiTagPeripheral!, options: nil)
        } else if peripheral.name != nil {
            print("Discovered other peripheral: \(peripheral.name ?? "Unknown Name")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "device")")
        // Stop any reconnection attempts
        invalidateReconnectTimer()
        // Update status on main thread
        DispatchQueue.main.async {
            self.connectionStatus = "Connected. Discovering services..."
            self.isConnected = true
        }
        // Discover the specific service we need
        peripheral.discoverServices([kServiceUUID])
    }

     func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
         print("Failed to connect to \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "Unknown error")")
         // Update status on main thread
         DispatchQueue.main.async {
            self.connectionStatus = "Connection Failed"
            self.isConnected = false
         }
         kaiTagPeripheral = nil
         // Optionally schedule reconnection attempt
         scheduleReconnect()
     }

     func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
         print("Disconnected from \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "No error info")")
         let wasConnected = isConnected // Check if we thought we were connected
         // Update status on main thread
         DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
            self.isConnected = false
            self.quaternion = Quaternion() // Reset quaternion data
         }
         kaiTagPeripheral = nil

         // Only attempt reconnect if it was an unexpected disconnect (error != nil or wasConnected)
         // and Bluetooth is powered on.
         if (error != nil || wasConnected) && centralManager.state == .poweredOn {
            print("Unexpected disconnect. Scheduling reconnect attempt...")
            scheduleReconnect()
         } else {
             print("Disconnect seems intentional or Bluetooth is off. Not attempting reconnect.")
             invalidateReconnectTimer() // Ensure timer is stopped
         }
     }

    // MARK: - CBPeripheralDelegate Methods

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            // Update status on main thread
             DispatchQueue.main.async {
                 self.connectionStatus = "Error discovering services"
             }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            print("Discovered service: \(service.uuid)")
            if service.uuid == kServiceUUID {
                // Update status on main thread
                 DispatchQueue.main.async {
                    self.connectionStatus = "Service Found. Discovering characteristics..."
                 }
                // Discover the specific characteristic we need
                peripheral.discoverCharacteristics([kQuaternionCharacteristicUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            // Update status on main thread
             DispatchQueue.main.async {
                 self.connectionStatus = "Error discovering characteristics"
             }
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == kQuaternionCharacteristicUUID {
                print("Found Quaternion characteristic. Subscribing...")
                // Update status on main thread
                 DispatchQueue.main.async {
                     self.connectionStatus = "Subscribing to Quaternion..."
                 }
                // Subscribe to notifications
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

     func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
         if let error = error {
             print("Error changing notification state for \(characteristic.uuid): \(error.localizedDescription)")
             // Update status on main thread
             DispatchQueue.main.async {
                 self.connectionStatus = "Subscription Error"
             }
             return
         }

         // Update status on main thread
         DispatchQueue.main.async {
             if characteristic.isNotifying {
                 print("Successfully subscribed to notifications for \(characteristic.uuid)")
                 self.connectionStatus = "Connected and Listening"
             } else {
                 print("Stopped notifications for \(characteristic.uuid)")
                 // Potentially update status if needed, e.g., if disconnect wasn't called yet
                 // self.connectionStatus = "Notifications Stopped"
             }
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
        // Stop trying to reconnect automatically if user tries manually
        invalidateReconnectTimer()

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
        // Stop trying to reconnect automatically if user disconnects manually
        invalidateReconnectTimer()

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

    // MARK: - Reconnection Logic

    private func scheduleReconnect() {
        // Invalidate existing timer first
        invalidateReconnectTimer()

        // Don't try if Bluetooth isn't powered on
        guard centralManager.state == .poweredOn else {
            print("Cannot schedule reconnect, Bluetooth is not powered on.")
            return
        }

        print("Scheduling reconnect attempt in 5 seconds...")
        // Schedule a timer to try scanning again after a delay
        // Ensure timer runs on the main run loop for safety with UI updates
        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                print("Reconnect timer fired. Attempting to scan...")
                self?.startScan()
            }
        }
    }

    private func invalidateReconnectTimer() {
        // Make sure timer is invalidated on the main thread where it was scheduled
        DispatchQueue.main.async {
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = nil
           // print("Reconnect timer invalidated.") // Optional log
        }
    }
}

// Helper to access Float from Data easily
extension Data {
    func readFloat(at offset: Int) -> Float {
        // Assumes little-endian based on JS `true` argument
        return self.subdata(in: offset..<(offset+4)).withUnsafeBytes { $0.load(as: Float.self) }
    }
} 