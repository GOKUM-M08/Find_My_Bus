# simulate_bus.py — run this to test your system
import socket
import time
import math

def simulate_bus(device_id: str, start_lat: float, start_lon: float):
    """Simulates a bus moving along a path."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('localhost', 9000))
    
    lat, lon = start_lat, start_lon
    
    print(f"Simulating bus: {device_id}")
    while True:
        # Move bus slightly (simulates movement)
        lat += 0.0001
        lon += 0.0001
        speed = 35.0
        
        # Send GPS data in the format your parser expects
        data = f"{device_id},{lat},{lon},{speed}\n"
        sock.sendall(data.encode())
        print(f"Sent: {data.strip()}")
        time.sleep(5)  # Send every 5 seconds

if __name__ == "__main__":
    # Use the device_id you registered in your database
    simulate_bus("DEVICE123", 13.0827, 80.2707)
