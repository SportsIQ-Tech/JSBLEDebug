import SwiftUI
import CoreLocation // Import CoreLocation

struct ContentView: View {
    // Create instances of the managers
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ScrollView { // Use ScrollView in case content exceeds screen height
            VStack(alignment: .leading, spacing: 15) {
                // --- Bluetooth Section ---
                Text("Bluetooth")
                    .font(.title3)
                Text(bluetoothManager.statusMessage)
                    .font(.footnote)
                Button {
                    if bluetoothManager.isConnected {
                        bluetoothManager.disconnect()
                    } else {
                        bluetoothManager.startScanning()
                    }
                } label: {
                    Text(bluetoothManager.isConnected ? "Disconnect KaiTag" : "Connect KaiTag")
                }
                .tint(bluetoothManager.isConnected ? .red : .blue)

                if bluetoothManager.isConnected {
                     VStack(alignment: .leading) {
                         Text("Quaternion:")
                             .font(.headline)
                         Text(String(format: " W: %.3f, X: %.3f", bluetoothManager.lastQuaternion.w, bluetoothManager.lastQuaternion.x))
                         Text(String(format: " Y: %.3f, Z: %.3f", bluetoothManager.lastQuaternion.y, bluetoothManager.lastQuaternion.z))
                     }
                     .font(.caption)
                     .padding(.bottom, 5)
                }

                Divider()

                // --- Location Section ---
                Text("GPS Location")
                     .font(.title3)
                Text(locationManager.statusMessage)
                    .font(.footnote)

                if let location = locationManager.lastLocation {
                    VStack(alignment: .leading) {
                        Text("Coordinates:")
                             .font(.headline)
                        Text(String(format: "Lat: %.6f", location.coordinate.latitude))
                        Text(String(format: "Lon: %.6f", location.coordinate.longitude))
                        Text(String(format: "Alt: %.1f m", location.altitude))
                        Text(String(format: "Acc: %.1f m", location.horizontalAccuracy))
                        Text("Time: \(location.timestamp)" )
                    }
                    .font(.caption)
                } else {
                     Text("Acquiring location...")
                         .font(.caption)
                         .foregroundColor(.gray)
                }

                // Debug: Show Location Auth Status
                // Text("Auth: \(String(describing: locationManager.locationStatus))")
                //    .font(.caption2)
                //    .foregroundColor(.gray)

                Spacer() // Pushes content to the top within the ScrollView
            }
            .padding()
        }
    }
}

// Preview needs adjustment if it depends on managers, but often okay for layout
#Preview {
    ContentView()
} 
