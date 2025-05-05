# KaiTag Ally Server

A real-time server for the KaiTag Ally web application that enables sharing location and orientation data between users.

## Features

- Real-time location and orientation sharing between team members
- Team-based filtering (red team vs blue team)
- Support for drawing sharing between teammates
- Automatic cleanup of stale clients

## Requirements

- Python 3.6+
- Dependencies listed in `requirements.txt`

## Installation

1. Clone the repository
2. Install the dependencies:

```bash
pip install -r requirements.txt
```

## Running the Server

Run the server with:

```bash
python ally-server.py
```

By default, the server runs on port 8080. You can configure the host and port using environment variables:

```bash
HOST=127.0.0.1 PORT=5000 python ally-server.py
```

## Accessing the Application

Once the server is running, open a web browser and navigate to:

```
http://localhost:8080
```

Replace `localhost` with your server's IP address if accessing from other devices on the network.

## How It Works

- The server uses Socket.IO for real-time bidirectional communication
- Clients send their GPS location and orientation (from the KaiTag device)
- The server broadcasts this information to other clients on the same team
- The app displays other team members' positions and orientations on the map

## License

This software is provided as-is with no warranties.
