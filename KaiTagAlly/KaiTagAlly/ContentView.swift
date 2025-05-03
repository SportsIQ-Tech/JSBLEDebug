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
    // Instantiate the LocationManager as a StateObject
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        // Wrap in NavigationView for navigation capabilities
        NavigationView {
            VStack(spacing: 20) {
                Text("KaiTag Ally")
                    .font(.largeTitle)

                Divider()

                // Connection Status and Control
                Text("Status: \(bluetoothManager.connectionStatus)")
                    .font(.headline)

                HStack(spacing: 20) {
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

                    NavigationLink(destination: MapView(locationManager: locationManager)) {
                        Label("Go to Map", systemImage: "map.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // Location Status / Info
                VStack {
                    Text("Location Status: \(locationManager.authorizationStatus.description)")
                        .font(.caption)
                    if let location = locationManager.location {
                        Text(String(format: "Lat: %.4f, Lon: %.4f", location.coordinate.latitude, location.coordinate.longitude))
                           .font(.caption)
                    } else {
                        Text("Location: Not available")
                           .font(.caption)
                    }
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

                Divider()

                Spacer() // Pushes content to the top

            }
            .padding()
            .navigationTitle("KaiTag Control") // Add a title to the main view
            .navigationBarHidden(true) // Hide the navigation bar for the root view if desired
        }
        .onAppear {
            // Optionally start location updates when the content view appears
            // locationManager.startUpdatingLocation() // Already started by LocationManager init if authorized
        }
    }
}

#Preview {
    ContentView()
}
