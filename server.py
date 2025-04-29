import os
import json
import logging
import time
from flask import Flask, send_from_directory, request, render_template_string
from flask_socketio import SocketIO, emit

logging.basicConfig(level=logging.INFO)

app = Flask(__name__)
# Use a secret key for session management (optional but recommended)
app.config['SECRET_KEY'] = os.urandom(24)
# Use eventlet for async mode
socketio = SocketIO(app, async_mode='eventlet')

# In-memory storage for client states
# CLIENT_STATES: { client_sid: { lat, lon, bearing, timestamp, team, kaiTagConnected, isDead } }
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

# --- SocketIO Event Handlers ---

@socketio.on('connect')
def handle_connect():
    """Handle new client connection."""
    client_sid = request.sid
    logging.info(f"Client connected: {client_sid}")
    # Send the client its ID (which is its session ID)
    emit('your_id', client_sid)
    logging.info(f"Sent ID {client_sid} to client.")
    # Send the current state of all OTHER clients
    emit('all_states', CLIENT_STATES)
    logging.info(f"Sent initial states ({len(CLIENT_STATES)} clients) to {client_sid}")

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection."""
    client_sid = request.sid
    logging.info(f"Client disconnected: {client_sid}")
    # Remove client state if it exists
    CLIENT_STATES.pop(client_sid, None)
    # Notify remaining clients about the disconnect
    emit('client_disconnected', client_sid, broadcast=True)
    logging.info(f"Broadcasted disconnect of {client_sid} to others.")

@socketio.on('update_state')
def handle_update_state(data):
    """Handle state update from a client."""
    client_sid = request.sid
    if isinstance(data, dict):
        if client_sid not in CLIENT_STATES:
            CLIENT_STATES[client_sid] = {}

        # Update state, preserving existing values if not provided
        CLIENT_STATES[client_sid]["lat"] = data.get("lat", CLIENT_STATES[client_sid].get("lat", 0))
        CLIENT_STATES[client_sid]["lon"] = data.get("lon", CLIENT_STATES[client_sid].get("lon", 0))
        CLIENT_STATES[client_sid]["bearing"] = data.get("bearing", CLIENT_STATES[client_sid].get("bearing", 0))
        CLIENT_STATES[client_sid]["kaiTagConnected"] = data.get("kaiTagConnected", CLIENT_STATES[client_sid].get("kaiTagConnected", True))
        CLIENT_STATES[client_sid]["isDead"] = data.get("isDead", CLIENT_STATES[client_sid].get("isDead", False))
        # Update team only if provided or not already set
        if "team" in data:
            CLIENT_STATES[client_sid]["team"] = data.get("team", "blue")
        elif "team" not in CLIENT_STATES[client_sid]:
            CLIENT_STATES[client_sid]["team"] = "blue" # Set default team if needed

        CLIENT_STATES[client_sid]["timestamp"] = time.time()

        logging.info(f"Updated state for {client_sid}: {CLIENT_STATES[client_sid]}")
        emit('all_states', CLIENT_STATES, broadcast=True)
    else:
        logging.warning(f"Received invalid state update from {client_sid}: {data}")

@socketio.on('update_bearing')
def handle_update_bearing(bearing):
    """Handle bearing-only update from a client."""
    client_sid = request.sid
    if client_sid not in CLIENT_STATES:
        logging.warning(f"Received bearing update from {client_sid} but no existing state found.")
        # Create a default state including kaiTagConnected and isDead
        CLIENT_STATES[client_sid] = {
            "lat": 0, "lon": 0, "bearing": 0, "timestamp": 0,
            "team": "blue", "kaiTagConnected": True, "isDead": False
            }

    if isinstance(bearing, (int, float)):
        current_time = time.time()
        CLIENT_STATES[client_sid]["bearing"] = bearing
        CLIENT_STATES[client_sid]["timestamp"] = current_time
        # Don't update kaiTagConnected status from bearing-only update
        logging.debug(f"Updated bearing for {client_sid} to {bearing}")

        emit('bearing_updated', {
             'clientId': client_sid,
             'bearing': bearing,
             'timestamp': current_time
             }, broadcast=True)
    else:
        logging.warning(f"Received invalid bearing update from {client_sid}: {bearing}")

@socketio.on('share_drawing')
def handle_share_drawing(data):
    """Handle drawing data shared by a client and broadcast it."""
    client_sid = request.sid
    if isinstance(data, dict) and 'geojson' in data and 'team' in data:
        # Add client_id to the data to be broadcasted
        drawing_data = {
            'geojson': data.get('geojson'),
            'clientId': client_sid,
            'team': data.get('team')
        }
        logging.info(f"Received drawing from {client_sid} (Team: {data.get('team')}), broadcasting...")
        # Broadcast to all other clients
        emit('new_drawing', drawing_data, broadcast=True, include_self=False)
    else:
        logging.warning(f"Received invalid drawing data from {client_sid}: {data}")

# --- Main Execution ---

if __name__ == '__main__':
    port = 8000
    host = "0.0.0.0"
    logging.info(f"Starting Flask-SocketIO server on {host}:{port}")
    # Use socketio.run with eventlet
    socketio.run(app, host=host, port=port, debug=False) # Set debug=True for development if needed 