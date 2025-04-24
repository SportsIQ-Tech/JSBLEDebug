import Foundation
import Combine

// Maintain your existing model types
struct StateUpdatePayload: Codable {
    let team: String
    let latitude: Double
    let longitude: Double
    // Add other fields as needed
}

struct ClientState: Codable, Identifiable {
    var id: String = ""
    var team: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var bearing: Double = 0
    var timestamp: TimeInterval = 0
    var kaiTagConnected: Bool = true
    var isDead: Bool = false
}

struct BearingUpdate: Codable {
    let clientId: String
    let bearing: Double
    let timestamp: TimeInterval
}

class RESTAPIManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var statusMessage = "Initializing..."
    @Published var myClientId: String? = nil
    @Published var allClientStates: [String: ClientState] = [:]
    
    // MARK: - Properties
    private let baseURL = "http://192.168.1.74:8000/api"
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 0.5 // Poll every 0.5 seconds (was 1.0)
    
    // MARK: - Initialization
    init() {
        print("RESTAPIManager Initialized for URL: \(baseURL)")
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public Methods
    func connect() {
        guard myClientId == nil else {
            print("Already connected or connecting.")
            return
        }
        
        print("Attempting to connect...")
        statusMessage = "Connecting..."
        
        // Register with server to get a client ID
        registerClient { [weak self] success in
            guard let self = self else { return }
            
            if success {
                // Start polling for updates
                self.startPolling()
            } else {
                DispatchQueue.main.async {
                    self.statusMessage = "Connection failed. Retrying..."
                    
                    // Schedule a retry after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.connect()
                    }
                }
            }
        }
    }
    
    func disconnect() {
        print("Disconnecting...")
        stopPolling()
        
        // If we have a client ID, unregister from the server
        if let clientId = myClientId {
            unregisterClient(clientId: clientId)
        }
        
        // Reset state
        isConnected = false
        myClientId = nil
        allClientStates = [:]
        statusMessage = "Disconnected"
    }
    
    func sendStateUpdate(payload: StateUpdatePayload) {
        guard let clientId = myClientId else {
            print("Cannot send state update: Not connected or no client ID.")
            return
        }
        
        let stateData: [String: Any] = [
            "lat": payload.latitude,
            "lon": payload.longitude,
            "team": payload.team,
            "kaiTagConnected": true,
            "isDead": false
        ]
        
        updateClientState(clientId: clientId, stateData: stateData)
    }
    
    func sendBearingUpdate(bearing: Double) {
        guard let clientId = myClientId else {
            print("Cannot send bearing update: Not connected or no client ID.")
            return
        }
        
        updateClientBearing(clientId: clientId, bearing: bearing)
    }
    
    // MARK: - Private Methods
    private func startPolling() {
        stopPolling() // Ensure we don't start multiple timers
        
        DispatchQueue.main.async {
            self.pollingTimer = Timer.scheduledTimer(withTimeInterval: self.pollingInterval, repeats: true) { [weak self] _ in
                self?.fetchAllClientStates()
            }
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - API Methods
    private func registerClient(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/clients/register") else {
            print("Invalid URL for client registration")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10 // Set a timeout
        
        print("Sending registration request to \(url.absoluteString)")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Registration failed with error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Registration failed: Invalid response")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            print("Registration response status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("Registration failed with status code: \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            guard let data = data else {
                print("Registration failed: No data received")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            do {
                print("Parsing registration response data: \(String(data: data, encoding: .utf8) ?? "nil")")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let clientId = json["client_id"] as? String {
                    
                    let states = json["states"] as? [String: [String: Any]] ?? [:]
                    
                    print("Successfully registered with client ID: \(clientId)")
                    
                    DispatchQueue.main.async {
                        self.myClientId = clientId
                        self.isConnected = true
                        self.statusMessage = "Connected (ID: \(clientId.prefix(6)))"
                        self.processClientStates(states)
                        completion(true)
                    }
                } else {
                    print("Registration failed: Invalid JSON format")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            } catch {
                print("Error parsing registration response: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
        
        task.resume()
    }
    
    private func unregisterClient(clientId: String) {
        guard let url = URL(string: "\(baseURL)/clients/\(clientId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let task = URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("Error unregistering client: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func fetchAllClientStates() {
        guard let url = URL(string: "\(baseURL)/clients") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                print("Error fetching client states: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                if let states = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    DispatchQueue.main.async {
                        self.processClientStates(states)
                    }
                }
            } catch {
                print("Error parsing client states: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func updateClientState(clientId: String, stateData: [String: Any]) {
        guard let url = URL(string: "\(baseURL)/clients/\(clientId)/state") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: stateData)
        } catch {
            print("Error serializing state data: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error updating client state: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func updateClientBearing(clientId: String, bearing: Double) {
        guard let url = URL(string: "\(baseURL)/clients/\(clientId)/bearing") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bearingData = ["bearing": bearing]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: bearingData)
        } catch {
            print("Error serializing bearing data: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error updating bearing: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func processClientStates(_ states: [String: [String: Any]]) {
        var decodedStates: [String: ClientState] = [:]
        
        for (clientId, stateDict) in states {
            // Skip ourselves if needed
            if clientId == myClientId {
                // Optionally skip or handle differently
            }
            
            do {
                // Convert dictionary to Client State
                var clientState = ClientState(id: clientId)
                
                if let lat = stateDict["lat"] as? Double {
                    clientState.latitude = lat
                }
                if let lon = stateDict["lon"] as? Double {
                    clientState.longitude = lon
                }
                if let bearing = stateDict["bearing"] as? Double {
                    clientState.bearing = bearing
                }
                if let team = stateDict["team"] as? String {
                    clientState.team = team
                }
                if let timestamp = stateDict["timestamp"] as? TimeInterval {
                    clientState.timestamp = timestamp
                }
                if let kaiTagConnected = stateDict["kaiTagConnected"] as? Bool {
                    clientState.kaiTagConnected = kaiTagConnected
                }
                if let isDead = stateDict["isDead"] as? Bool {
                    clientState.isDead = isDead
                }
                
                decodedStates[clientId] = clientState
            } catch {
                print("Error processing state for client \(clientId): \(error)")
            }
        }
        
        // Check for clients that were removed
        let oldClientIds = Set(allClientStates.keys)
        let newClientIds = Set(decodedStates.keys)
        let removedClientIds = oldClientIds.subtracting(newClientIds)
        
        for clientId in removedClientIds {
            print("Client removed: \(clientId)")
        }
        
        allClientStates = decodedStates
    }
} 
