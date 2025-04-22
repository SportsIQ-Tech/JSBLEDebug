import Foundation
import CoreLocation
import Combine // For ObservableObject

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published Properties for UI Updates
    @Published var lastLocation: CLLocation? // Store the full CLLocation object
    @Published var locationStatus: CLAuthorizationStatus? = nil // Track permission status
    @Published var statusMessage: String = "Initializing Location..."

    // MARK: - Core Location Properties
    private let locationManager = CLLocationManager()

    // MARK: - Initialization
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest // High accuracy
        locationManager.distanceFilter = kCLDistanceFilterNone // Update regardless of distance moved (can adjust later for battery)
        print("LocationManager Initialized")
        // Request permission immediately upon initialization
        requestPermission()
    }

    // MARK: - Public Methods
    func requestPermission() {
        print("Requesting location permission...")
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else {
            statusMessage = "Location permission not granted."
            print("Cannot start location updates: Permission not granted.")
            return
        }
        statusMessage = "Starting location updates..."
        print("Starting location updates.")
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        statusMessage = "Stopped location updates."
        print("Stopping location updates.")
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate Methods

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus // Update published status

        switch manager.authorizationStatus {
        case .notDetermined:
            statusMessage = "Location permission not determined."
            print("Location auth status: notDetermined")
            requestPermission() // Request again if somehow missed
        case .restricted:
            statusMessage = "Location access restricted."
            print("Location auth status: restricted")
        case .denied:
            statusMessage = "Location access denied. Please enable in Settings."
            print("Location auth status: denied")
        case .authorizedAlways, .authorizedWhenInUse:
            statusMessage = "Location access granted."
            print("Location auth status: authorized")
            startUpdatingLocation() // Start updates once authorized
        @unknown default:
            statusMessage = "Unknown location authorization status."
            print("Location auth status: unknown default")
            stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Update the published property. This will likely happen on the main thread
        // because the CLLocationManager delegate methods are typically called there.
        self.lastLocation = location
        self.statusMessage = "Location Updated"

        // Optional: Print for debugging (can be noisy)
         // let timestamp = location.timestamp.formatted(date: .omitted, time: .standard)
         // let coord = location.coordinate
         // print("Location Updated [\(timestamp)]: Lat \(coord.latitude), Lon \(coord.longitude), Alt \(location.altitude), Acc \(location.horizontalAccuracy)m")

        // Optional: Stop updates after getting one good location? (For battery saving)
        // if location.horizontalAccuracy < 100 { // Example threshold
        //     stopUpdatingLocation()
        // }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "Location Error: \(error.localizedDescription)"
        print("Location manager failed with error: \(error.localizedDescription)")
        // Consider stopping updates on failure, depending on the error
        // stopUpdatingLocation()
    }
} 