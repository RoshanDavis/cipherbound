import socket
import json
from config import UDP_IP, UDP_PORT


class UDPSender:
    """Handles UDP communication with Godot."""
    
    def __init__(self, ip: str = UDP_IP, port: int = UDP_PORT):
        """
        Initialize the UDPSender with a destination address and create a UDP socket.
        
        Parameters:
            ip (str): Destination IPv4 address to send UDP packets to. Defaults to UDP_IP from configuration.
            port (int): Destination port number to send UDP packets to. Defaults to UDP_PORT from configuration.
        """
        self.ip = ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    def send(self, data: dict) -> bool:
        """
        Send a dictionary as a JSON-encoded UDP packet to the configured destination.
        
        Parameters:
            data (dict): The payload to serialize to JSON and transmit.
        
        Returns:
            `True` if the message was sent successfully, `False` otherwise.
        """
        try:
            message = json.dumps(data).encode('utf-8')
            self.sock.sendto(message, (self.ip, self.port))
            return True
        except Exception as e:
            print(f"Network Error: {e}")
            return False
    
    def close(self):
        """
        Close the UDP socket and release its underlying resources.
        
        After calling this method, the sender's socket is no longer usable for sending messages.
        """
        self.sock.close()