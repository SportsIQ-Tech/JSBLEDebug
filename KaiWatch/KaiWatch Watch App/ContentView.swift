import SwiftUI
import CoreLocation // Import CoreLocation
import MapKit // Import MapKit

struct ContentView: View {
    // Create instances of the managers
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()

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

    var body: some View {
        VStack { // Use VStack instead of ScrollView if Map is primary
            // --- Map View ---
            Map(position: $cameraPosition) {
                // User location annotation (blue dot)
                UserAnnotation()

                // Aiming line overlay (needs coordinates)
                if !aimingLineCoordinates.isEmpty {
                    MapPolyline(coordinates: aimingLineCoordinates)
                        .stroke(.green, lineWidth: 3)
                }
            }
            .mapControls {
                 // Add map controls if desired (zoom, etc.) - might clutter watch face
                 // MapUserLocationButton()
                 // MapCompass()
                 // MapScaleView()
            }
            .onChange(of: locationManager.lastLocation) { _, newLocation in
                 updateMapAndAimingLine(location: newLocation, bearing: bluetoothManager.currentBearing)
            }
            .onChange(of: bluetoothManager.currentBearing) { _, newBearing in
                updateMapAndAimingLine(location: locationManager.lastLocation, bearing: newBearing)
            }
            .onAppear {
                 // Initial update when view appears
                updateMapAndAimingLine(location: locationManager.lastLocation, bearing: bluetoothManager.currentBearing)
            }

            // --- Status Overlay (Optional) ---
            // Consider moving status text/button to an overlay or separate view
            // to avoid taking space from the map.
             HStack {
                 Button {
                    if bluetoothManager.isConnected {
                        bluetoothManager.disconnect()
                    } else {
                        bluetoothManager.startScanning()
                    }
                } label: {
                    Image(systemName: bluetoothManager.isConnected ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                }
                .tint(bluetoothManager.isConnected ? .red : .blue)
                .buttonStyle(.bordered)
                .controlSize(.small)

                 VStack {
                    Text(bluetoothManager.statusMessage).font(.caption2)
                    Text(locationManager.statusMessage).font(.caption2)
                    Text(String(format: "Bearing: %.1f°", bluetoothManager.currentBearing)).font(.caption2)
                 }
                 Spacer() // Push button/text left/right
             }
             .padding(.horizontal)
             .padding(.vertical, 4)
             .background(.thinMaterial) // Make status stand out

        }
        .ignoresSafeArea(edges: .top) // Allow map to go to screen top

    }

    // MARK: - Helper Functions

    private func updateMapAndAimingLine(location: CLLocation?, bearing: Double) {
        guard let currentCoord = location?.coordinate else {
             // If no location, clear the line
             aimingLineCoordinates = []
             return
         }

        // Update map position (optional, as .userLocation might handle it)
        // cameraPosition = .region(MKCoordinateRegion(center: currentCoord, span: mapRegion.span))

        // Calculate endpoint for the aiming line
        let endCoord = calculateDestinationPoint(lat: currentCoord.latitude,
                                                lon: currentCoord.longitude,
                                                bearing: bearing,
                                                distance: aimingLineDistanceMeters)

        // Update the state variable which redraws the MapPolyline
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

// Preview needs adjustment
#Preview {
    ContentView()
} 
