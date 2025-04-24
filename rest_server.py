import os
import json
import logging
import time
import uuid
from flask import Flask, send_from_directory, request, render_template_string, jsonify
from flask_cors import CORS

logging.basicConfig(level=logging.INFO)

app = Flask(__name__)
# Use a secret key for session management
app.config['SECRET_KEY'] = os.urandom(24)
# Enable CORS for REST API
CORS(app)

# In-memory storage for client states
# CLIENT_STATES: { client_id: { lat, lon, bearing, timestamp, team, kaiTagConnected, isDead } }
CLIENT_STATES = {}

# --- HTTP Routes ---

@app.route('/')
def index():
    """Serve the main HTML page."""
    # Read index.html content
    try:
        with open('index.html', 'r') as f:
            html_content = f.read()
        # Render it as a template string (allows potential future templating)
        return render_template_string(html_content)
    except FileNotFoundError:
        return "Error: index.html not found.", 404
    except Exception as e:
         logging.error(f"Error reading index.html: {e}")
         return "Internal Server Error", 500

@app.route('/models/<path:filename>')
def serve_model(filename):
    """Serve files from the 'models' directory."""
    return send_from_directory('models', filename)

# --- REST API Routes for Watch App ---

@app.route('/api/clients', methods=['GET'])
def get_all_clients():
    """Get all client states."""
    return jsonify(CLIENT_STATES)

@app.route('/api/clients/register', methods=['POST'])
def register_client():
    """Register a new client and return its ID."""
    client_id = str(uuid.uuid4())
    # Initialize client state with defaults
    CLIENT_STATES[client_id] = {
        "lat": 0,
        "lon": 0,
        "bearing": 0,
        "timestamp": time.time(),
        "team": "blue",
        "kaiTagConnected": True,
        "isDead": False
    }
    logging.info(f"REST API: Client registered: {client_id}")
    
    return jsonify({"client_id": client_id, "states": CLIENT_STATES})

@app.route('/api/clients/<client_id>', methods=['DELETE'])
def unregister_client(client_id):
    """Unregister a client."""
    if client_id in CLIENT_STATES:
        CLIENT_STATES.pop(client_id, None)
        logging.info(f"REST API: Client unregistered: {client_id}")
        return jsonify({"status": "success"})
    return jsonify({"status": "error", "message": "Client not found"}), 404

@app.route('/api/clients/<client_id>/state', methods=['POST'])
def update_client_state(client_id):
    """Update a client's state."""
    data = request.json
    
    if not data or not isinstance(data, dict):
        return jsonify({"status": "error", "message": "Invalid request data"}), 400
    
    if client_id not in CLIENT_STATES:
        CLIENT_STATES[client_id] = {}
    
    # Update state, preserving existing values if not provided
    CLIENT_STATES[client_id]["lat"] = data.get("lat", CLIENT_STATES[client_id].get("lat", 0))
    CLIENT_STATES[client_id]["lon"] = data.get("lon", CLIENT_STATES[client_id].get("lon", 0))
    CLIENT_STATES[client_id]["bearing"] = data.get("bearing", CLIENT_STATES[client_id].get("bearing", 0))
    CLIENT_STATES[client_id]["kaiTagConnected"] = data.get("kaiTagConnected", CLIENT_STATES[client_id].get("kaiTagConnected", True))
    CLIENT_STATES[client_id]["isDead"] = data.get("isDead", CLIENT_STATES[client_id].get("isDead", False))
    
    # Update team only if provided or not already set
    if "team" in data:
        CLIENT_STATES[client_id]["team"] = data.get("team", "blue")
    elif "team" not in CLIENT_STATES[client_id]:
        CLIENT_STATES[client_id]["team"] = "blue"
    
    CLIENT_STATES[client_id]["timestamp"] = time.time()
    
    logging.info(f"REST API: Updated state for {client_id}: {CLIENT_STATES[client_id]}")
    
    return jsonify({"status": "success", "states": CLIENT_STATES})

@app.route('/api/clients/<client_id>/bearing', methods=['POST'])
def update_client_bearing(client_id):
    """Update a client's bearing."""
    data = request.json
    
    if not data or "bearing" not in data:
        return jsonify({"status": "error", "message": "Invalid request data"}), 400
    
    bearing = data.get("bearing")
    
    if not isinstance(bearing, (int, float)):
        return jsonify({"status": "error", "message": "Bearing must be a number"}), 400
    
    if client_id not in CLIENT_STATES:
        CLIENT_STATES[client_id] = {
            "lat": 0, "lon": 0, "bearing": 0, "timestamp": 0,
            "team": "blue", "kaiTagConnected": True, "isDead": False
        }
    
    current_time = time.time()
    CLIENT_STATES[client_id]["bearing"] = bearing
    CLIENT_STATES[client_id]["timestamp"] = current_time
    
    logging.info(f"REST API: Updated bearing for {client_id} to {bearing}")
    
    return jsonify({"status": "success"})

# --- Main Execution ---

if __name__ == '__main__':
    port = 8000
    host = "0.0.0.0"
    logging.info(f"Starting Flask server on {host}:{port}")
    # Use threaded=True for better handling of multiple requests
    app.run(host=host, port=port, debug=False, threaded=True) 