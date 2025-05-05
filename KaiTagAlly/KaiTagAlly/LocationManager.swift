import Foundation
import CoreLocation
import Combine // For ObservableObject

class LocationManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5 // Update when moved 5 meters
        
        #if os(iOS)
        locationManager.requestWhenInUseAuthorization()
        #endif
        
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Public Methods
    
    func startUpdatingLocation() {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
        }
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Use the most recent location
        guard let newLocation = locations.last else { return }
        
        // Update the published property
        DispatchQueue.main.async {
            self.location = newLocation
        }

        // --- DEBUG PRINT --- //
        let timestamp = DateFormatter.localizedString(from: newLocation.timestamp, dateStyle: .none, timeStyle: .medium)
        print("*** Location Update [\(timestamp)]: Lat=\(String(format: "%.6f", newLocation.coordinate.latitude)), Lon=\(String(format: "%.6f", newLocation.coordinate.longitude)), Alt=\(String(format: "%.2f", newLocation.altitude))m, Acc=\(String(format: "%.1f", newLocation.horizontalAccuracy))m, Spd=\(String(format: "%.2f", newLocation.speed))m/s")
        // ------------------- //
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        // If authorized, start updating location
        #if os(iOS)
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #else
        if status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #endif
    }
}

// MARK: - Helper extension for authorization status description

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Authorized Always"
        #if os(iOS)
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        #endif
        @unknown default:
            return "Unknown"
        }
    }
} 