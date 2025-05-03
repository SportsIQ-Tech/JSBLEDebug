import SwiftUI
import MapKit // Import MapKit
import CoreLocation

// Note: This file depends on the LocationManager class which is defined in LocationManager.swift

struct DrawingPath {
    var points: [CGPoint] = []
    var color: Color = .red
    var lineWidth: CGFloat = 3
}

struct DrawingView: View {
    @Binding var paths: [DrawingPath]
    @Binding var currentPath: DrawingPath
    @Binding var isDrawingEnabled: Bool
    
    var body: some View {
        ZStack {
            // Draw completed paths
            ForEach(0..<paths.count, id: \.self) { index in
                Path { path in
                    guard let firstPoint = paths[index].points.first else { return }
                    path.move(to: firstPoint)
                    for point in paths[index].points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(paths[index].color, lineWidth: paths[index].lineWidth)
            }
            
            // Draw current path
            Path { path in
                guard let firstPoint = currentPath.points.first else { return }
                path.move(to: firstPoint)
                for point in currentPath.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(currentPath.color, lineWidth: currentPath.lineWidth)
        }
        .opacity(isDrawingEnabled ? 1.0 : 0.0) // Hide when drawing is disabled
        .allowsHitTesting(isDrawingEnabled) // Prevent interaction when disabled
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let location = value.location
                    if currentPath.points.isEmpty {
                        currentPath.points.append(location)
                    } else if let lastPoint = currentPath.points.last, 
                              distance(from: lastPoint, to: location) > 5 {
                        currentPath.points.append(location)
                    }
                }
                .onEnded { _ in
                    if !currentPath.points.isEmpty {
                        paths.append(currentPath)
                        currentPath = DrawingPath()
                    }
                }
        )
    }
    
    // Helper function to calculate distance between points
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        return sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
    }
}

struct MapView: View {
    // Observe the LocationManager passed from ContentView
    @ObservedObject var locationManager: LocationManager

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

    var body: some View {
        ZStack {
            // Map layer
            Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: .constant(.follow))
                .onAppear {
                    // Optionally start location updates when the map appears
                    // locationManager.startUpdatingLocation() // Already started in ContentView usually
                }
                .onChange(of: locationManager.location) {
                    // Update the map region when the location changes
                    if let coordinate = locationManager.location?.coordinate {
                        region.center = coordinate
                        print("MapView updated region to: Lat \(coordinate.latitude), Lon \(coordinate.longitude)")
                    }
                }
                .ignoresSafeArea(edges: .all)
                .disabled(isDrawingEnabled) // Disable map interaction when drawing is enabled
            
            // Drawing layer - full screen transparent layer when drawing is enabled
            if isDrawingEnabled {
                Color.clear
                    .contentShape(Rectangle()) // Make the entire area interactive
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                let location = value.location
                                if currentPath.points.isEmpty {
                                    currentPath.points.append(location)
                                } else if let lastPoint = currentPath.points.last, 
                                          distance(from: lastPoint, to: location) > 2 {
                                    currentPath.points.append(location)
                                }
                            }
                            .onEnded { _ in
                                if !currentPath.points.isEmpty {
                                    paths.append(currentPath)
                                    currentPath = DrawingPath(color: selectedColor)
                                }
                            }
                    )
            }
            
            // Render all paths and current path
            ZStack {
                // Draw completed paths
                ForEach(0..<paths.count, id: \.self) { index in
                    Path { path in
                        guard let firstPoint = paths[index].points.first else { return }
                        path.move(to: firstPoint)
                        for point in paths[index].points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(paths[index].color, lineWidth: paths[index].lineWidth)
                }
                
                // Draw current path
                Path { path in
                    guard let firstPoint = currentPath.points.first else { return }
                    path.move(to: firstPoint)
                    for point in currentPath.points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(currentPath.color, lineWidth: currentPath.lineWidth)
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
    
    // Helper function to calculate distance between points
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        return sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
    }
}

// Preview Provider (optional, might need a mock LocationManager)
// #Preview {
//     // You'd need to create a mock or use a temporary LocationManager for preview
//     MapView(locationManager: LocationManager())
// } 