import SwiftUI

struct ContentView: View {
    // Create an instance of the BluetoothManager
    // @StateObject ensures it persists for the life of the view
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        VStack(spacing: 15) {
            // Connection Status
            Text(bluetoothManager.statusMessage)
                .font(.footnote)
                .multilineTextAlignment(.center)

            // Connect/Disconnect Button
            Button {
                if bluetoothManager.isConnected {
                    bluetoothManager.disconnect()
                } else {
                    bluetoothManager.startScanning()
                }
            } label: {
                Text(bluetoothManager.isConnected ? "Disconnect KaiTag" : "Connect KaiTag")
            }
            .tint(bluetoothManager.isConnected ? .red : .blue) // Change button color based on state

            // Display Quaternion Data (optional, for debugging)
            if bluetoothManager.isConnected {
                 VStack {
                     Text("Quaternion Data:")
                         .font(.headline)
                     Text(String(format: "W: %.3f", bluetoothManager.lastQuaternion.w))
                     Text(String(format: "X: %.3f", bluetoothManager.lastQuaternion.x))
                     Text(String(format: "Y: %.3f", bluetoothManager.lastQuaternion.y))
                     Text(String(format: "Z: %.3f", bluetoothManager.lastQuaternion.z))
                 }
                 .font(.caption)
            }

            Spacer() // Pushes content to the top
        }
        .padding()
    }
}

// Preview remains the same
#Preview {
    ContentView()
} 