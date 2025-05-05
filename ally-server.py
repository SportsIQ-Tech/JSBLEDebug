#!/usr/bin/env python3

import socketio
import eventlet
from eventlet import wsgi
import json
import time
import logging
import os
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger('ally-server')

# Create a SocketIO server instance
sio = socketio.Server(cors_allowed_origins='*')
app = socketio.WSGIApp(sio, static_files={
    '/': {'content_type': 'text/html', 'filename': 'index.html'},
    '/models': 'models',  # Serve the models directory for 3D assets
})

# Store connected clients and their states
clients = {}
client_states = {}

@sio.event
def connect(sid, environ):
    """Handle client connection"""
    client_ip = environ.get('REMOTE_ADDR', 'unknown')
    logger.info(f'Client connected: {sid} from {client_ip}')
    clients[sid] = {
        'connected_at': time.time(),
        'ip': client_ip,
        'last_update': time.time()
    }
    
    # Send the client their ID
    sio.emit('your_id', sid, to=sid)
    
    # Send all current client states to the new client
    sio.emit('all_states', client_states, to=sid)

@sio.event
def disconnect(sid):
    """Handle client disconnection"""
    logger.info(f'Client disconnected: {sid}')
    
    # Remove client from tracking
    if sid in clients:
        del clients[sid]
    
    # Remove client state
    if sid in client_states:
        del client_states[sid]
    
    # Notify other clients about the disconnection
    sio.emit('client_disconnected', sid, skip_sid=sid)
    
    # Update all clients with the new state
    sio.emit('all_states', client_states, skip_sid=sid)

@sio.event
def update_state(sid, data):
    """Handle client sending their updated state (location, bearing, etc.)"""
    if not isinstance(data, dict):
        logger.warning(f'Invalid update_state data from {sid}: {data}')
        return
    
    # Update client's last activity time
    if sid in clients:
        clients[sid]['last_update'] = time.time()
    
    # Process and store the client state
    client_states[sid] = {
        'lat': data.get('lat', 0),
        'lon': data.get('lon', 0),
        'bearing': data.get('bearing', 0),
        'team': data.get('team', 'blue'),
        'isDead': data.get('isDead', False),
        'kaiTagConnected': data.get('kaiTagConnected', False),
        'timestamp': time.time() * 1000  # Timestamp in milliseconds
    }
    
    # If bearing changed significantly, send specific bearing update
    # (All clients will get full state updates periodically)
    sio.emit('bearing_updated', {
        'clientId': sid,
        'bearing': data.get('bearing', 0),
        'timestamp': client_states[sid]['timestamp']
    }, skip_sid=sid)
    
    # Periodically send full state updates to all clients
    # We could optimize to only do this occasionally, but for now, do it on every update
    sio.emit('all_states', client_states)

@sio.event
def share_drawing(sid, data):
    """Handle client sharing a drawing"""
    if not isinstance(data, dict):
        logger.warning(f'Invalid share_drawing data from {sid}: {data}')
        return
    
    # Add client ID to the drawing data
    drawing_data = {
        'clientId': sid,
        'geojson': data.get('geojson', {}),
        'team': data.get('team', 'blue'),
        'timestamp': time.time() * 1000
    }
    
    # Only broadcast drawings to teammates
    team = data.get('team', 'blue')
    
    # Find all clients on the same team
    teammates = [client_id for client_id, state in client_states.items() 
                if state.get('team') == team and client_id != sid]
    
    # Send the drawing to all teammates
    for teammate_sid in teammates:
        sio.emit('new_drawing', drawing_data, to=teammate_sid)
    
    logger.info(f'Drawing shared by {sid} to {len(teammates)} teammates')

def cleanup_stale_clients():
    """Remove clients that haven't updated in a while"""
    current_time = time.time()
    stale_threshold = 60  # seconds
    
    stale_clients = []
    for sid, client_data in clients.items():
        if current_time - client_data.get('last_update', 0) > stale_threshold:
            stale_clients.append(sid)
    
    for sid in stale_clients:
        logger.info(f'Cleaning up stale client: {sid}')
        if sid in clients:
            del clients[sid]
        if sid in client_states:
            del client_states[sid]
        # Note: We don't emit disconnection events here as the client might reconnect
    
    if stale_clients:
        # Update all clients with the new state if we removed any stale clients
        sio.emit('all_states', client_states)

def periodic_tasks():
    """Run periodic tasks like client cleanup"""
    while True:
        cleanup_stale_clients()
        eventlet.sleep(30)  # Run cleanup every 30 seconds

if __name__ == '__main__':
    # Start the periodic tasks in a background thread
    eventlet.spawn(periodic_tasks)
    
    # Determine host and port
    host = os.environ.get('HOST', '0.0.0.0')
    port = int(os.environ.get('PORT', 8080))
    
    # Start server
    logger.info(f'Starting KaiTag Ally server on {host}:{port}')
    wsgi.server(eventlet.listen((host, port)), app) 