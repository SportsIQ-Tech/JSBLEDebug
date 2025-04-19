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
# CLIENT_STATES: { client_sid: { lat: number, lon: number, bearing: number, timestamp: number } }
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
        # Update or add state for this client
        # Ensure state exists before trying to update (might receive update before connect fully establishes state)
        if client_sid not in CLIENT_STATES:
            CLIENT_STATES[client_sid] = {}

        CLIENT_STATES[client_sid]["lat"] = data.get("lat", CLIENT_STATES[client_sid].get("lat", 0))
        CLIENT_STATES[client_sid]["lon"] = data.get("lon", CLIENT_STATES[client_sid].get("lon", 0))
        CLIENT_STATES[client_sid]["bearing"] = data.get("bearing", CLIENT_STATES[client_sid].get("bearing", 0))
        # Update team only if provided in this update
        if "team" in data:
            CLIENT_STATES[client_sid]["team"] = data.get("team", "blue") # Default to blue
        elif "team" not in CLIENT_STATES[client_sid]: # Set default if not set previously
            CLIENT_STATES[client_sid]["team"] = "blue"

        CLIENT_STATES[client_sid]["timestamp"] = time.time() # Use server time

        logging.info(f"Updated state for {client_sid}: {CLIENT_STATES[client_sid]}")
        # Broadcast the updated states to ALL clients (including sender for consistency)
        emit('all_states', CLIENT_STATES, broadcast=True)
        # logging.info(f"Broadcasted states to all clients.")
    else:
        logging.warning(f"Received invalid state update from {client_sid}: {data}")

@socketio.on('update_bearing')
def handle_update_bearing(bearing):
    """Handle bearing-only update from a client."""
    client_sid = request.sid
    if client_sid not in CLIENT_STATES:
        # Client might have connected but not sent initial state yet, or state was cleared
        logging.warning(f"Received bearing update from {client_sid} but no existing state found.")
        # Create a default state (including default team)
        CLIENT_STATES[client_sid] = {"lat": 0, "lon": 0, "bearing": 0, "timestamp": 0, "team": "blue"}
        # return # Or just return if we don't want to create dummy state

    if isinstance(bearing, (int, float)):
        current_time = time.time()
        CLIENT_STATES[client_sid]["bearing"] = bearing
        CLIENT_STATES[client_sid]["timestamp"] = current_time
        logging.debug(f"Updated bearing for {client_sid} to {bearing}")

        # Broadcast only the change to all clients (including sender is fine)
        emit('bearing_updated', {
             'clientId': client_sid,
             'bearing': bearing,
             'timestamp': current_time
             }, broadcast=True)
        # logging.debug(f"Broadcasted bearing update for {client_sid}")
    else:
        logging.warning(f"Received invalid bearing update from {client_sid}: {bearing}")

# --- Main Execution ---

if __name__ == '__main__':
    port = 8000
    host = "0.0.0.0"
    logging.info(f"Starting Flask-SocketIO server on {host}:{port}")
    # Use socketio.run with eventlet
    socketio.run(app, host=host, port=port, debug=False) # Set debug=True for development if needed 