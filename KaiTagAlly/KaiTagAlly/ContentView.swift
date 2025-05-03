//
//  ContentView.swift
//  KaiTagAlly
//
//  Created by Paulius Velesko on 02/05/2025.
//

import SwiftUI

struct ContentView: View {
    // Instantiate the BluetoothManager as a StateObject
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("KaiTag Ally")
                .font(.largeTitle)

            Divider()

            // Connection Status and Control
            Text("Status: \(bluetoothManager.connectionStatus)")
                .font(.headline)

            HStack {
                Button(bluetoothManager.isConnected ? "Disconnect" : "Connect KaiTag") {
                    if bluetoothManager.isConnected {
                        bluetoothManager.disconnect()
                    } else {
                        // Start scanning/connecting
                        bluetoothManager.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(bluetoothManager.isConnected ? .red : .blue)

                // Optional: Add a dedicated scan button if needed
                // Button("Scan") {
                //     bluetoothManager.startScan()
                // }
                // .buttonStyle(.bordered)
                // .disabled(bluetoothManager.isConnected || bluetoothManager.connectionStatus == "Scanning...")
            }


            Divider()

            // Display Quaternion Data
            Text("Quaternion Data")
                .font(.headline)
            if bluetoothManager.isConnected {
                VStack(alignment: .leading) {
                    Text(String(format: "W: %.4f", bluetoothManager.quaternion.w))
                    Text(String(format: "X: %.4f", bluetoothManager.quaternion.x))
                    Text(String(format: "Y: %.4f", bluetoothManager.quaternion.y))
                    Text(String(format: "Z: %.4f", bluetoothManager.quaternion.z))
                }
                .font(.body.monospaced()) // Use monospaced font for numbers
            } else {
                Text("Connect to view data...")
                    .foregroundColor(.gray)
            }


            Spacer() // Pushes content to the top

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
