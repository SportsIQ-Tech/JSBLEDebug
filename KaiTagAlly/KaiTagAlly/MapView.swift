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
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var socketManager: SocketManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    @State private var selectedTeam: String = ""
    @State private var showingTeamSelection = true
    
    var body: some View {
        ZStack {
            // Map
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: annotationItems) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    VStack {
                        // Direction indicator
                        if !item.isDead && item.kaiTagConnected {
                            Image(systemName: "arrow.up")
                                .foregroundColor(.blue)
                                .rotationEffect(Angle(degrees: item.bearing))
                                .frame(width: 30, height: 30)
                        }
                        
                        // Marker
                        ZStack {
                            Circle()
                                .fill(item.isDead ? .gray : (item.kaiTagConnected ? item.teamColor : .gray))
                                .frame(width: 15, height: 15)
                            
                            if item.isDead {
                                Text("X")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Name
                        Text(item.title)
                            .font(.caption)
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // Team selection overlay
            if showingTeamSelection {
                Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Text("Choose Your Team")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 30) {
                        Button(action: {
                            selectedTeam = "red"
                            socketManager.selectTeam("red")
                            showingTeamSelection = false
                        }) {
                            Text("Team Red")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(width: 120)
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        
                        Button(action: {
                            selectedTeam = "blue"
                            socketManager.selectTeam("blue")
                            showingTeamSelection = false
                        }) {
                            Text("Team Blue")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(width: 120)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .onAppear {
            // Center map on user's location when view appears
            if let location = locationManager.location?.coordinate {
                region = MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            }
        }
        .onChange(of: locationManager.location) { newLocation in
            if let location = newLocation?.coordinate {
                // Center map on new location
                withAnimation {
                    region = MKCoordinateRegion(
                        center: location,
                        span: region.span
                    )
                }
                
                // Send location update to server
                socketManager.sendStateUpdate(
                    location: newLocation,
                    quaternion: bluetoothManager.quaternion,
                    isDead: false // Could be calculated from quaternion in a real app
                )
            }
        }
        .onChange(of: bluetoothManager.quaternion) { _ in
            // If we have location and quaternion, send update
            if let location = locationManager.location {
                socketManager.sendStateUpdate(
                    location: location,
                    quaternion: bluetoothManager.quaternion,
                    isDead: false // Could be calculated from quaternion in a real app
                )
            }
        }
    }
    
    // Model for map annotations
    struct MapAnnotationItem: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let bearing: Double
        let teamColor: Color
        let isDead: Bool
        let kaiTagConnected: Bool
    }
    
    // Generate annotation items from socket data
    var annotationItems: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        
        // Add items for other clients
        for (clientId, state) in socketManager.otherClients {
            let teamColor: Color = state.team == "red" ? .red : .blue
            
            items.append(MapAnnotationItem(
                id: clientId,
                coordinate: CLLocationCoordinate2D(latitude: state.lat, longitude: state.lon),
                title: "Team \(state.team.capitalized)",
                bearing: state.bearing,
                teamColor: teamColor,
                isDead: state.isDead,
                kaiTagConnected: state.kaiTagConnected
            ))
        }
        
        return items
    }
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView(
            locationManager: LocationManager(),
            bluetoothManager: BluetoothManager(),
            socketManager: SocketManager()
        )
    }
} 