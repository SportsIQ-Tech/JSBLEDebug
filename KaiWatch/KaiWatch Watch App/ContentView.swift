import SwiftUI
import CoreLocation // Import CoreLocation
import MapKit // Import MapKit

struct ContentView: View {
    // Create instances of the managers
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var socketManager = RESTAPIManager() // Updated to RESTAPIManager

    // UI State
    @State private var selectedTeam: String? = nil // Track selected team ("red" or "blue")
    let teams = ["red", "blue"]

    // Map State
    // Note: Using cameraPosition directly might be better for watchOS
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
    )
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    // Aiming line coordinates
    @State private var aimingLineCoordinates: [CLLocationCoordinate2D] = []
    private let aimingLineDistanceMeters: Double = 50 // Length of the line on map

    // State for throttling updates
    @State private var lastSentTimestamp: Date = Date(timeIntervalSince1970: 0)
    private let updateInterval: TimeInterval = 0.05 // Increased to 20 times/sec (was 0.1)
    @State private var lastBearingTimestamp: Date = Date(timeIntervalSince1970: 0)
    private let bearingUpdateInterval: TimeInterval = 0.1 // Increased to 10 times/sec (was 0.2)

    var body: some View {
        // Show Team Selection Overlay if no team is selected
        if selectedTeam == nil {
            TeamSelectionView(selectedTeam: $selectedTeam)
        } else {
            // Main Map and Status View
            ZStack(alignment: .bottom) { // Use ZStack to overlay status
                Map(position: $cameraPosition) {
                    // User location annotation (blue dot)
                    UserAnnotation()

                    // Aiming line overlay (needs coordinates)
                    if !aimingLineCoordinates.isEmpty {
                        MapPolyline(coordinates: aimingLineCoordinates)
                            .stroke(.green, lineWidth: 3)
                    }

                    // Display other clients from socketManager.allClientStates
                    // (Example: drawing markers - requires more complex logic)
                    // ForEach(Array(socketManager.allClientStates.values)) { client in
                    //     if client.id != socketManager.myClientId,
                    //        let lat = client.lat, let lon = client.lon {
                    //         Marker(client.team ?? "", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    //             .tint(client.team == "red" ? .red : .blue)
                    //     }
                    // }
                }
                .mapControls {
                     // Add map controls if desired (zoom, etc.) - might clutter watch face
                     // MapUserLocationButton()
                     // MapCompass()
                     // MapScaleView()
                }
                .onChange(of: locationManager.lastLocation) { _, newLocation in
                     updateMapAndMaybeSendState(location: newLocation,
                                                bearing: bluetoothManager.currentBearing,
                                                btConnected: bluetoothManager.isConnected,
                                                team: selectedTeam)
                }
                .onChange(of: bluetoothManager.currentBearing) { _, newBearing in
                    updateMapAndMaybeSendState(location: locationManager.lastLocation,
                                               bearing: newBearing,
                                               btConnected: bluetoothManager.isConnected,
                                               team: selectedTeam)
                    
                    // Send bearing updates separately with their own throttling
                    sendBearingUpdate(bearing: newBearing)
                }
                .onChange(of: bluetoothManager.isConnected) { _, newBtConnected in
                    updateMapAndMaybeSendState(location: locationManager.lastLocation,
                                               bearing: bluetoothManager.currentBearing,
                                               btConnected: newBtConnected,
                                               team: selectedTeam)
                }
                .onAppear {
                     // Connect socket when view appears (if team is selected)
                     socketManager.connect()
                     // Initial update
                     updateMapAndMaybeSendState(location: locationManager.lastLocation,
                                                bearing: bluetoothManager.currentBearing,
                                                btConnected: bluetoothManager.isConnected,
                                                team: selectedTeam)
                }
                .onDisappear {
                    // Disconnect socket when view disappears
                    socketManager.disconnect()
                }
                .ignoresSafeArea(edges: .top) // Allow map to go to screen top

                // Status Overlay Panel
                statusOverlay
            }
        }
    }

    // Extracted Status Overlay View
    private var statusOverlay: some View {
         HStack {
             // Bluetooth Connect Button
             Button {
                if bluetoothManager.isConnected {
                    bluetoothManager.disconnect()
                } else {
                    bluetoothManager.startScanning()
                }
            } label: {
                Image(systemName: bluetoothManager.isConnected ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
            }
            .tint(bluetoothManager.isConnected ? .green : .gray) // Green when connected
            .buttonStyle(.bordered)
            .controlSize(.small)

             // Socket Connect/Disconnect Button
             Button {
                 if socketManager.isConnected {
                     socketManager.disconnect()
                 } else {
                     socketManager.connect() // Allow manual reconnect
                 }
             } label: {
                 Image(systemName: socketManager.isConnected ? "network.slash" : "network")
             }
             .tint(socketManager.isConnected ? .blue : .gray)
             .buttonStyle(.bordered)
             .controlSize(.small)

             VStack(alignment: .leading) {
                 Text("BT: \(bluetoothManager.statusMessage)").font(.caption2).lineLimit(1)
                 Text("GPS: \(locationManager.statusMessage)").font(.caption2).lineLimit(1)
                 Text("NET: \(socketManager.statusMessage)").font(.caption2).lineLimit(1)
                 Text(String(format: "Bearing: %.1f°", bluetoothManager.currentBearing)).font(.caption2)
             }
             .frame(maxWidth: .infinity) // Allow text to take available space

             // Display selected team
            if let team = selectedTeam {
                Text(team.uppercased())
                    .font(.caption.bold())
                    .padding(3)
                    .background(team == "red" ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(3)
            }

         }
         .padding(.horizontal, 6)
         .padding(.vertical, 4)
         .background(.thinMaterial)
    }

    // MARK: - Helper Functions

    private func updateMapAndMaybeSendState(location: CLLocation?, bearing: Double, btConnected: Bool, team: String?) {
        // 1. Update the local map aiming line
        updateAimingLine(location: location, bearing: bearing)

        // 2. Check if ready to send state
        guard let currentCoord = location?.coordinate,
              let currentTeam = team,
              socketManager.isConnected,
              socketManager.myClientId != nil
        else {
            // Add print statement here to see if guard fails
             print("DEBUG: Conditions not met for sending state. Socket Connected: \(socketManager.isConnected), Client ID: \(socketManager.myClientId ?? "nil"), Team: \(team ?? "nil"), Location: \(location != nil)")
            return
        }

        // 3. Throttle the updates
        let now = Date()
        guard now.timeIntervalSince(lastSentTimestamp) >= updateInterval else {
             // Add print statement here to see if throttled
             // print("DEBUG: Throttled state update.")
            return
        }
        lastSentTimestamp = now

        // 4. Create payload and send
        let payload = StateUpdatePayload(
            team: currentTeam,
            latitude: currentCoord.latitude,
            longitude: currentCoord.longitude
        )

        // Add print statement here before sending
        print("DEBUG: Sending state update: Team=\(payload.team), Lat=\(payload.latitude), Lon=\(payload.longitude)")
        socketManager.sendStateUpdate(payload: payload)
    }
    
    private func sendBearingUpdate(bearing: Double) {
        // Check if ready to send bearing
        guard socketManager.isConnected,
              socketManager.myClientId != nil
        else {
            return
        }
        
        // Throttle bearing updates
        let now = Date()
        guard now.timeIntervalSince(lastBearingTimestamp) >= bearingUpdateInterval else {
            return
        }
        lastBearingTimestamp = now
        
        print("DEBUG: Sending bearing update: \(bearing)")
        socketManager.sendBearingUpdate(bearing: bearing)
    }

    private func updateAimingLine(location: CLLocation?, bearing: Double) {
        guard let currentCoord = location?.coordinate else {
            aimingLineCoordinates = []
            return
        }
        let endCoord = calculateDestinationPoint(lat: currentCoord.latitude,
                                                lon: currentCoord.longitude,
                                                bearing: bearing,
                                                distance: aimingLineDistanceMeters)
        aimingLineCoordinates = [currentCoord, endCoord]
    }

    // Helper to calculate destination point (Ported from JS version)
    private func calculateDestinationPoint(lat: Double, lon: Double, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let R = 6371e3 // Earth radius in meters
        let phi1 = lat * .pi / 180 // φ, λ in radians
        let lambda1 = lon * .pi / 180
        let brng = bearing * .pi / 180
        let d = distance

        let phi2 = asin(sin(phi1) * cos(d / R) +
                      cos(phi1) * sin(d / R) * cos(brng))
        let lambda2 = lambda1 + atan2(sin(brng) * sin(d / R) * cos(phi1),
                                       cos(d / R) - sin(phi1) * sin(phi2))

        let lat2 = phi2 * 180 / .pi
        let lon2 = lambda2 * 180 / .pi

        return CLLocationCoordinate2D(latitude: lat2, longitude: lon2)
    }
}

// --- Team Selection View ---
struct TeamSelectionView: View {
    @Binding var selectedTeam: String?
    let teams = ["red", "blue"]

    var body: some View {
        VStack {
            Text("Choose Your Team")
                .font(.title2)

            HStack(spacing: 20) {
                ForEach(teams, id: \.self) { team in
                    Button(team.capitalized) {
                        selectedTeam = team
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(team == "red" ? .red : .blue)
                }
            }
        }
    }
}

// Preview needs adjustment
#Preview {
    ContentView()
} 
