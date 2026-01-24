import socket
import json
from config import UDP_IP, UDP_PORT


class UDPSender:
    """Handles UDP communication with Godot."""
    
    def __init__(self, ip: str = UDP_IP, port: int = UDP_PORT):
        self.ip = ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    def send(self, data: dict) -> bool:
        """Send data packet to Godot. Returns True on success."""
        try:
            message = json.dumps(data).encode('utf-8')
            self.sock.sendto(message, (self.ip, self.port))
            return True
        except Exception as e:
            print(f"Network Error: {e}")
            return False
    
    def close(self):
        """Clean up socket."""
        self.sock.close()
