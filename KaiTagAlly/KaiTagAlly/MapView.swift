import SwiftUI
import MapKit // Import MapKit

struct MapView: View {
    // Observe the LocationManager passed from ContentView
    @ObservedObject var locationManager: LocationManager

    // State variable to hold the map region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312), // Default to Apple Park
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Default zoom
    )

    var body: some View {
        // Use the new Map view available in iOS 17+/macOS 14+
        // For broader compatibility, you might use the older MapKit UIViewRepresentable
        Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: .constant(.follow))
            .onAppear {
                // Optionally start location updates when the map appears
                // locationManager.startUpdatingLocation() // Already started in ContentView usually
            }
             // Simpler onChange syntax for newer SwiftUI versions
            .onChange(of: locationManager.location) {
                // Update the map region when the location changes
                if let coordinate = locationManager.location?.coordinate {
                    region.center = coordinate
                    print("MapView updated region to: Lat \(coordinate.latitude), Lon \(coordinate.longitude)")
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// Preview Provider (optional, might need a mock LocationManager)
// #Preview {
//     // You'd need to create a mock or use a temporary LocationManager for preview
//     MapView(locationManager: LocationManager())
// } 