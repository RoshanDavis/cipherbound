# --- CONFIGURATION ---
# Network settings
UDP_IP = "127.0.0.1"
UDP_PORT = 5005

# Camera settings
import os
WEBCAM_ID = int(os.getenv("WEBCAM_ID", 1))
DEBUG_MODE = True

# Calibration
CALIBRATION_FRAMES = 30

# --- HAND SETTINGS ---
# Set to True if user is left-handed (swaps control and drawing hand roles)
LEFT_HANDED = False

# --- JOYSTICK ZONES ---
# Look (face tracking) - normalized coordinates (0.0 to 1.0 of screen)
LOOK_DEADZONE_RADIUS = 0.015  # Inner circle - no movement (~1.5% of screen)
LOOK_MAX_RADIUS = 0.07        # Outer circle - max look speed (~7% of screen)

# Movement (body lean) - normalized coordinates
MOVE_DEADZONE_RADIUS = 0.02   # Inner circle for body lean
MOVE_MAX_RADIUS = 0.08        # Outer circle for body lean

# Depth (face size) - ratio-based
DEPTH_DEADZONE = 0.08         # 8% change in face size = deadzone (increased to prevent accidental movement)
DEPTH_MAX = 0.25              # 25% change = max speed (wider range for gradual control)
