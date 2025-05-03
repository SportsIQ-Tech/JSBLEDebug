import Foundation
import CoreLocation
import Combine // For ObservableObject

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var location: CLLocation? = nil
    @Published var authorizationStatus: CLAuthorizationStatus

    override init() {
        // Check availability for macOS if necessary, but CoreLocation handles it reasonably well
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self

        // Configure for highest accuracy and update rate
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone // Update for any movement
        locationManager.activityType = .otherNavigation // Hint for higher power usage/accuracy

        print("LocationManager initialized.")

        // Request authorization if needed
        requestAuthorizationIfNeeded()
    }

    private func requestAuthorizationIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            print("Requesting Always location authorization.")
            // On macOS, requestAlwaysAuthorization might behave like requestWhenInUse depending on settings
            locationManager.requestAlwaysAuthorization()
        case .restricted, .denied:
            print("Location access is restricted or denied.")
            // Handle appropriately - show alert, guide user to settings etc.
        case .authorizedWhenInUse: // This case might be less common/differently handled on macOS
            print("Location access is WhenInUse (or equivalent macOS setting). Requesting Always.")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            print("Location access is Always (or equivalent macOS setting).")
            startUpdatingLocation()
        @unknown default:
            print("Unknown location authorization status.")
        }
    }

    func startUpdatingLocation() {
        // Check if location services are enabled on the device
        guard CLLocationManager.locationServicesEnabled() else {
            print("Location services are disabled on this device.")
            // Update UI or state to reflect this
            return
        }
        // Check if we have the required authorization
        // On macOS, .authorizedWhenInUse might not exist; rely on checking for .authorizedAlways or just .authorized (which covers relevant macOS states)
        // Simplified check for macOS compatibility:
        let hasAuthorization = (authorizationStatus == .authorizedAlways || authorizationStatus.rawValue == CLAuthorizationStatus.authorized.rawValue) // Check for Always or the general 'authorized' state

        guard hasAuthorization else {
            print("Cannot start location updates without appropriate authorization. Current: \(authorizationStatus)")
            return
        }

        print("Starting location updates.")
        locationManager.startUpdatingLocation()
        // Enable background location updates if needed (already declared in Info.plist)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // Prevent system from pausing updates
    }

    func stopUpdatingLocation() {
        print("Stopping location updates.")
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate Methods

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }

        // Publish the latest location
        DispatchQueue.main.async {
            self.location = latestLocation
        }

        // --- DEBUG PRINT --- //
        let timestamp = DateFormatter.localizedString(from: latestLocation.timestamp, dateStyle: .none, timeStyle: .medium)
        print("*** Location Update [\(timestamp)]: Lat=\(String(format: "%.6f", latestLocation.coordinate.latitude)), Lon=\(String(format: "%.6f", latestLocation.coordinate.longitude)), Alt=\(String(format: "%.2f", latestLocation.altitude))m, Acc=\(String(format: "%.1f", latestLocation.horizontalAccuracy))m, Spd=\(String(format: "%.2f", latestLocation.speed))m/s")
        // ------------------- //
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
        // Handle errors appropriately, e.g., stop updates, show alert
        // Consider specific CL Errors like kCLErrorDenied etc.
        if let clError = error as? CLError, clError.code == .denied {
             print("Location access denied by user.")
             // Update state to reflect denial
             DispatchQueue.main.async {
                 self.authorizationStatus = .denied // Update status
             }
             stopUpdatingLocation()
         }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        print("Location authorization status changed to: \(newStatus)")
        DispatchQueue.main.async {
            self.authorizationStatus = newStatus // Update published status
        }

        // Handle status change
        switch newStatus {
        case .authorizedAlways:
            startUpdatingLocation()
        case .authorizedWhenInUse: // Less direct equivalent on macOS
             print("Warning: Only 'When In Use' equivalent authorization granted. Requesting 'Always'.")
             locationManager.requestAlwaysAuthorization() // Request again
             startUpdatingLocation() // Start anyway
        case .denied, .restricted:
            print("Location access denied or restricted after status change.")
            stopUpdatingLocation()
            // Clear location data? Show message?
             DispatchQueue.main.async {
                 self.location = nil
             }
        case .notDetermined:
            print("Location authorization reset to notDetermined?") // Should not happen often after initial request
            requestAuthorizationIfNeeded()
        @unknown default:
            print("Unhandled location authorization status change.")
        }
    }
}

// Helper to make CLAuthorizationStatus printable
extension CLAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }
} 