import Foundation
import SocketIO
import CoreLocation

class SocketManager: ObservableObject {
    // Published properties that the UI can observe
    @Published var isConnected = false
    @Published var otherClients: [String: ClientState] = [:]
    
    // Socket.IO manager and socket
    private let manager: SocketManager
    private let socket: SocketIOClient
    private var clientId: String?
    private var selectedTeam: String?
    
    // Structure to store client state information
    struct ClientState {
        var lat: Double
        var lon: Double
        var bearing: Double
        var team: String
        var isDead: Bool
        var kaiTagConnected: Bool
        var timestamp: Double
    }
    
    init(serverURL: URL = URL(string: "http://localhost:8080")!) {
        // Initialize Socket.IO manager and socket
        self.manager = SocketIO.SocketManager(socketURL: serverURL, config: [.log(true), .compress])
        self.socket = manager.defaultSocket
        
        // Set up event handlers
        setupEventHandlers()
        
        // Connect to the server
        connect()
    }
    
    // MARK: - Connection Management
    
    func connect() {
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
    }
    
    // MARK: - Team Selection
    
    func selectTeam(_ team: String) {
        guard team == "red" || team == "blue" else { return }
        selectedTeam = team
        // Update state on server if already connected
        if isConnected {
            sendStateUpdate()
        }
    }
    
    // MARK: - State Updates
    
    func sendStateUpdate(location: CLLocation? = nil, quaternion: Quaternion? = nil, isDead: Bool = false) {
        guard let team = selectedTeam else {
            print("Cannot send update: team not selected")
            return
        }
        
        // Create state data object
        var stateData: [String: Any] = [
            "team": team,
            "isDead": isDead,
            "kaiTagConnected": true // Assuming connected if sending updates
        ]
        
        // Add location data if available
        if let location = location {
            stateData["lat"] = location.coordinate.latitude
            stateData["lon"] = location.coordinate.longitude
        }
        
        // Add bearing data calculated from quaternion if available
        if let quaternion = quaternion {
            // Simple calculation of bearing from quaternion (approximation)
            // In a real app, you might need more complex calculations
            let bearing = calculateBearing(from: quaternion)
            stateData["bearing"] = bearing
        }
        
        // Send to server
        socket.emit("update_state", stateData)
    }
    
    // MARK: - Private Methods
    
    private func setupEventHandlers() {
        // Connection events
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self = self else { return }
            print("Socket connected")
            self.isConnected = true
            
            // If team is selected, send initial state
            if self.selectedTeam != nil {
                self.sendStateUpdate()
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self = self else { return }
            print("Socket disconnected")
            self.isConnected = false
        }
        
        socket.on("your_id") { [weak self] data, _ in
            guard let self = self, let id = data[0] as? String else { return }
            print("Received client ID: \(id)")
            self.clientId = id
        }
        
        // Data events
        socket.on("all_states") { [weak self] data, _ in
            guard let self = self, let statesDict = data[0] as? [String: [String: Any]] else { return }
            
            var newStates: [String: ClientState] = [:]
            
            for (clientId, stateData) in statesDict {
                // Skip self
                if clientId == self.clientId {
                    continue
                }
                
                // Extract values with appropriate defaults
                let lat = stateData["lat"] as? Double ?? 0
                let lon = stateData["lon"] as? Double ?? 0
                let bearing = stateData["bearing"] as? Double ?? 0
                let team = stateData["team"] as? String ?? "blue"
                let isDead = stateData["isDead"] as? Bool ?? false
                let kaiTagConnected = stateData["kaiTagConnected"] as? Bool ?? false
                let timestamp = stateData["timestamp"] as? Double ?? 0
                
                // Only show clients from the same team
                if team == self.selectedTeam {
                    newStates[clientId] = ClientState(
                        lat: lat,
                        lon: lon,
                        bearing: bearing,
                        team: team,
                        isDead: isDead,
                        kaiTagConnected: kaiTagConnected,
                        timestamp: timestamp
                    )
                }
            }
            
            // Update observed property on main thread
            DispatchQueue.main.async {
                self.otherClients = newStates
            }
        }
        
        socket.on("bearing_updated") { [weak self] data, _ in
            guard let self = self,
                  let updateData = data[0] as? [String: Any],
                  let clientId = updateData["clientId"] as? String,
                  let bearing = updateData["bearing"] as? Double,
                  let timestamp = updateData["timestamp"] as? Double,
                  clientId != self.clientId, // Skip updates about self
                  var clientState = self.otherClients[clientId],
                  clientState.team == self.selectedTeam // Only process updates for same team
            else { return }
            
            // Update bearing and timestamp
            clientState.bearing = bearing
            clientState.timestamp = timestamp
            
            // Update on main thread
            DispatchQueue.main.async {
                self.otherClients[clientId] = clientState
            }
        }
    }
    
    // Calculate bearing (heading) from quaternion
    // This is a simplified version - you may need a more accurate calculation
    private func calculateBearing(from quaternion: Quaternion) -> Double {
        // In a real implementation, this would convert quaternion to Euler angles
        // and extract the heading/bearing (yaw)
        // For simplicity, here's an approximation:
        
        // Convert quaternion to bearing in degrees (0-360)
        // This assumes quaternion represents device orientation in a way that 
        // bearing can be derived (typically from w and y components for heading)
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z
        let w = quaternion.w
        
        // Basic yaw calculation from quaternion
        // atan2(2.0 * (w * y + x * z), 1.0 - 2.0 * (y * y + x * x))
        let yaw = atan2(2.0 * (w * y + x * z), 1.0 - 2.0 * (y * y + x * x))
        
        // Convert from radians to degrees and normalize to 0-360
        var bearingDegrees = yaw * (180.0 / Double.pi)
        bearingDegrees = (bearingDegrees + 360).truncatingRemainder(dividingBy: 360)
        
        return bearingDegrees
    }
} 