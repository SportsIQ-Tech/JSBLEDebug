import SwiftUI
import MapKit // Import MapKit
import CoreLocation

// Note: This file depends on the LocationManager class which is defined in LocationManager.swift
// and the BluetoothManager and Quaternion from BluetoothManager.swift

// Local struct for quaternion data to avoid import issues
struct MapQuaternion {
    var w: Float = 0.0
    var x: Float = 0.0
    var y: Float = 0.0
    var z: Float = 0.0
    
    // Constructor to convert from BluetoothManager's Quaternion
    init(from quaternion: Any) {
        if let q = quaternion as? [String: Float] {
            self.w = q["w"] ?? 0.0
            self.x = q["x"] ?? 0.0
            self.y = q["y"] ?? 0.0
            self.z = q["z"] ?? 0.0
        } else {
            // Handle other cases - this allows flexibility with how the quaternion is passed
            // We'll use reflection to try to extract values dynamically
            let mirror = Mirror(reflecting: quaternion)
            for child in mirror.children {
                if child.label == "w" { self.w = child.value as? Float ?? 0.0 }
                if child.label == "x" { self.x = child.value as? Float ?? 0.0 }
                if child.label == "y" { self.y = child.value as? Float ?? 0.0 }
                if child.label == "z" { self.z = child.value as? Float ?? 0.0 }
            }
        }
    }
}

struct DrawingPath {
    var geoPoints: [CLLocationCoordinate2D] = []
    var color: Color = .red
    var lineWidth: CGFloat = 3
}

struct MapView: View {
    // Observe the LocationManager passed from ContentView
    @ObservedObject var locationManager: LocationManager
    // Observe the BluetoothManager passed from ContentView
    @ObservedObject var bluetoothManager: BluetoothManager

    // State variable to hold the map region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312), // Default to Apple Park
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Default zoom
    )
    
    // Drawing state
    @State private var paths: [DrawingPath] = []
    @State private var currentPath = DrawingPath()
    @State private var isDrawingEnabled = false
    @State private var selectedColor: Color = .red
    
    // Direction indicator settings
    @State private var directionLineLength: Double = 500.0 // Length in meters (increased 10x)
    @State private var showDirectionLine: Bool = true
    
    // Reference to the map for coordinate conversion
    @State private var mapRect: MKMapRect?

    var body: some View {
        ZStack {
            // Map layer
            Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: .constant(.follow))
                .onAppear {
                    // Optionally start location updates when the map appears
                    // locationManager.startUpdatingLocation() // Already started in ContentView usually
                }
                .onChange(of: locationManager.location) { newValue in
                    // Update the map region when the location changes
                    if let coordinate = locationManager.location?.coordinate {
                        region.center = coordinate
                        print("MapView updated region to: Lat \(coordinate.latitude), Lon \(coordinate.longitude)")
                    }
                }
                .ignoresSafeArea(edges: .all)
                .disabled(isDrawingEnabled) // Disable map interaction when drawing is enabled
                .background(
                    // Use GeometryReader to get map frame for coordinate conversions
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                // Initialize mapRect based on geometry
                                updateMapRect(for: geometry)
                            }
                            // Use .id() modifier to force view recreation when region changes
                            .id("\(region.center.latitude),\(region.center.longitude),\(region.span.latitudeDelta)")
                    }
                )
            
            // Drawing layer - full screen transparent layer when drawing is enabled
            if isDrawingEnabled {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle()) // Make the entire area interactive
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    let screenPoint = value.location
                                    if let geoCoordinate = convertToCoordinate(screenPoint, in: geometry) {
                                        if currentPath.geoPoints.isEmpty {
                                            currentPath.geoPoints.append(geoCoordinate)
                                        } else if let lastPoint = currentPath.geoPoints.last,
                                                  distance(from: lastPoint, to: geoCoordinate) > 0.00001 { // Small geo distance
                                            currentPath.geoPoints.append(geoCoordinate)
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    if !currentPath.geoPoints.isEmpty {
                                        paths.append(currentPath)
                                        currentPath = DrawingPath(color: selectedColor)
                                    }
                                }
                        )
                }
            }
            
            // Render all paths and current path (map coordinates to screen coordinates)
            GeometryReader { geometry in
                ZStack {
                    // Draw completed paths
                    ForEach(0..<paths.count, id: \.self) { index in
                        Path { path in
                            let points = paths[index].geoPoints
                            if let firstPoint = points.first, 
                               let screenPoint = convertToScreenPoint(firstPoint, in: geometry) {
                                path.move(to: screenPoint)
                                for geoPoint in points.dropFirst() {
                                    if let screenPoint = convertToScreenPoint(geoPoint, in: geometry) {
                                        path.addLine(to: screenPoint)
                                    }
                                }
                            }
                        }
                        .stroke(paths[index].color, lineWidth: paths[index].lineWidth)
                    }
                    
                    // Draw current path
                    Path { path in
                        let points = currentPath.geoPoints
                        if let firstPoint = points.first,
                           let screenPoint = convertToScreenPoint(firstPoint, in: geometry) {
                            path.move(to: screenPoint)
                            for geoPoint in points.dropFirst() {
                                if let screenPoint = convertToScreenPoint(geoPoint, in: geometry) {
                                    path.addLine(to: screenPoint)
                                }
                            }
                        }
                    }
                    .stroke(currentPath.color, lineWidth: currentPath.lineWidth)
                    
                    // Draw direction indicator from user location
                    if showDirectionLine && !isDrawingEnabled, 
                       let userLocation = locationManager.location?.coordinate,
                       let userScreenPoint = convertToScreenPoint(userLocation, in: geometry) {
                        
                        // Calculate direction from quaternion
                        let direction = quaternionToDirection(bluetoothManager.quaternion)
                        
                        // Calculate the endpoint using the direction vector
                        let destinationCoordinate = calculateDestinationPoint(
                            from: userLocation,
                            direction: direction,
                            distance: directionLineLength
                        )
                        
                        if let endScreenPoint = convertToScreenPoint(destinationCoordinate, in: geometry) {
                            // Draw a simple line without arrowhead
                            Path { path in
                                path.move(to: userScreenPoint)
                                path.addLine(to: endScreenPoint)
                            }
                            .stroke(Color.blue, lineWidth: 4)
                            
                            // Remove arrowhead code
                        }
                    }
                }
            }
            
            // Controls overlay
            VStack {
                Spacer()
                
                HStack {
                    // Drawing mode toggle
                    Button(action: {
                        isDrawingEnabled.toggle()
                        // Reset current path when toggling drawing mode
                        if isDrawingEnabled {
                            currentPath = DrawingPath(color: selectedColor)
                        }
                    }) {
                        Image(systemName: isDrawingEnabled ? "pencil.slash" : "pencil")
                            .padding()
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .foregroundColor(isDrawingEnabled ? .red : .blue)
                    }
                    
                    Spacer()
                    
                    // Direction indicator toggle
                    Button(action: {
                        showDirectionLine.toggle()
                    }) {
                        Image(systemName: showDirectionLine ? "location.north.line.fill" : "location.north.line")
                            .padding()
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .foregroundColor(showDirectionLine ? .blue : .gray)
                    }
                    
                    Spacer()
                    
                    // Color picker
                    if isDrawingEnabled {
                        HStack {
                            ForEach([Color.red, Color.blue, Color.green, Color.black, Color.yellow], id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                        currentPath.color = color
                                    }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.8)))
                    }
                    
                    Spacer()
                    
                    // Clear all button
                    if isDrawingEnabled && !paths.isEmpty {
                        Button(action: {
                            paths = []
                            currentPath = DrawingPath(color: selectedColor)
                        }) {
                            Image(systemName: "trash")
                                .padding()
                                .background(Circle().fill(Color.white.opacity(0.8)))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Helper functions for coordinate conversion
    private func updateMapRect(for geometry: GeometryProxy) {
        let mapWidth = Double(geometry.size.width)
        let mapHeight = Double(geometry.size.height)
        
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta
        
        mapRect = MKMapRect(
            x: 0,
            y: 0,
            width: mapWidth,
            height: mapHeight
        )
    }
    
    private func convertToCoordinate(_ point: CGPoint, in geometry: GeometryProxy) -> CLLocationCoordinate2D? {
        let mapSize = geometry.size
        
        // Calculate the relative position within the map view (0-1)
        let relativeX = Double(point.x / mapSize.width)
        let relativeY = Double(point.y / mapSize.height)
        
        // Convert to coordinate relative to the current map view
        let longitude = region.center.longitude - (region.span.longitudeDelta / 2) + (relativeX * region.span.longitudeDelta)
        let latitude = region.center.latitude + (region.span.latitudeDelta / 2) - (relativeY * region.span.latitudeDelta)
        
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    private func convertToScreenPoint(_ coordinate: CLLocationCoordinate2D, in geometry: GeometryProxy) -> CGPoint? {
        let mapSize = geometry.size
        
        // Calculate relative position in map (0-1)
        let longitudeDelta = region.span.longitudeDelta
        let latitudeDelta = region.span.latitudeDelta
        
        let relativeX = (coordinate.longitude - (region.center.longitude - longitudeDelta / 2)) / longitudeDelta
        let relativeY = 1.0 - ((coordinate.latitude - (region.center.latitude - latitudeDelta / 2)) / latitudeDelta)
        
        // Convert to screen points
        let screenX = CGFloat(relativeX) * mapSize.width
        let screenY = CGFloat(relativeY) * mapSize.height
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    // Helper to calculate geographic distance between coordinates
    private func distance(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2) // Distance in meters
    }
    
    // Convert quaternion to a 2D heading direction
    private func quaternionToDirection(_ quaternionData: Any) -> Double {
        // Convert incoming quaternion to our local MapQuaternion type
        let quaternion = MapQuaternion(from: quaternionData)
        
        // Calculate heading/yaw from quaternion (rotation around Y axis)
        // Formula: atan2(2*(q.y*q.z + q.w*q.x), q.w*q.w - q.x*q.x - q.y*q.y + q.z*q.z)
        
        let q = quaternion
        let headingFloat = atan2(2 * (q.y * q.z + q.w * q.x), 
                        q.w * q.w - q.x * q.x - q.y * q.y + q.z * q.z)
        
        return Double(headingFloat) // Convert Float to Double
    }
    
    // Calculate destination point given a starting point, direction and distance
    private func calculateDestinationPoint(from startCoordinate: CLLocationCoordinate2D, 
                                          direction: Double,
                                          distance: Double) -> CLLocationCoordinate2D {
        // Earth's radius in meters
        let earthRadius = 6371000.0
        
        // Convert latitude and longitude from degrees to radians
        let lat1 = startCoordinate.latitude * Double.pi / 180
        let lon1 = startCoordinate.longitude * Double.pi / 180
        
        // Calculate the destination latitude
        let lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
                        cos(lat1) * sin(distance / earthRadius) * cos(direction))
        
        // Calculate the destination longitude
        let lon2 = lon1 + atan2(sin(direction) * sin(distance / earthRadius) * cos(lat1),
                               cos(distance / earthRadius) - sin(lat1) * sin(lat2))
        
        // Convert back to degrees
        let latitudeDegrees = lat2 * 180 / Double.pi
        let longitudeDegrees = lon2 * 180 / Double.pi
        
        return CLLocationCoordinate2D(latitude: latitudeDegrees, longitude: longitudeDegrees)
    }
}

// Preview Provider (optional, might need a mock LocationManager)
// #Preview {
//     // You'd need to create a mock or use a temporary LocationManager for preview
//     MapView(locationManager: LocationManager())
// } 