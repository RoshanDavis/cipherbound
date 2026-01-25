# PROJECT CONTEXT: CIPHERBOUND

## 1. Project Overview
**Name:** Cipherbound
**Genre:** First-Person Wizard RPG (FPV)
**Core Mechanic:** "No-Controller" Input. The player controls the game entirely using computer vision (Head tracking for camera, Body lean for movement, Hand gestures for magic).
**Goal:** Build a cohesive "Side-Car" application where a lightweight Python vision server drives a Godot 4 game client in real-time.

## 2. Technical Architecture: "The Side-Car Pattern"
The project consists of two independent processes communicating via local UDP.

### A. The Vision Server (Python)
* **Role:** The "Eye". Captures webcam input, processes it via AI, and blasts JSON coordinates to Godot.
* **Tech Stack:** Python 3.10+, MediaPipe (Holistic/FaceMesh), OpenCV, NumPy, Socket (UDP).
* **Output:** Sends JSON packets to `localhost:5005`.
* **Constraint:** Must run at 30+ FPS. No heavy game logic here, only detection logic.

**Modular Structure:**
```text
vision/src/
├── config.py          # All configuration constants
├── network.py         # UDP sender class
├── main.py            # Main entry point
└── trackers/
    ├── __init__.py    # Package exports
    ├── base.py        # BaseTracker with calibration logic
    ├── look.py        # LookTracker (nose → camera rotation)
    ├── strafe.py      # StrafeTracker (shoulders → left/right)
    └── depth.py       # DepthTracker (face size → forward/back)
```

**Current Data Packet:**
```jsonc
{
  "has_face": true,
  "look_x": 0.0,      // -1 to +1, joystick-style camera rotation
  "look_y": 0.0,      // -1 to +1, joystick-style camera rotation  
  "has_body": true,
  "lean_x": 0.0,      // -1 to +1, strafe left/right (shoulder tracking)
  "lean_y": 0.0,      // -1 to +1, walk forward/back (face depth/size)
  "calibrated": true
}
```

### B. The Game Client (Godot 4)
* **Role:** The "World". Renders the game and interprets raw data into game actions.
* **Tech Stack:** Godot 4.x, GDScript.
* **Input:** Listens on UDP Port 5005 via `UDPServer`.
* **Logic:**
  * **Player.gd:** CharacterBody3D with Camera3D child. Handles joystick-style look input with smoothing/curves, strafe and walk movement.

## 3. Directory Structure
```text
ROOT (cipherbound/)
├── cipherbound-game/        # Godot Project Root
│   ├── scripts/             # All GDScript files
│   │   └── Player.gd        # Main player controller
│   └── scenes/              # .tscn files
│       └── game.tscn        # Main game scene
├── vision/                  # Python Project Root
│   ├── src/                 # Python source code (modular)
│   ├── venv/                # Virtual environment
│   └── requirements.txt     # pip dependencies
├── CONTEXT.md               # This file
└── README.md
```

## 4. Coding Guidelines & Standards

### Python Rules
* **Type Hinting:** Use `def function() -> dict:` for clarity.
* **Performance:** Avoid `for` loops over pixel arrays. Use NumPy vectorization.
* **Networking:** Always use `json.dumps()` encoded to `utf-8`.
* **Error Handling:** Wrap camera access in `try/except` to prevent crashes if the webcam is busy.
* **Modularity:** Each tracker is a separate class inheriting from `BaseTracker`.

### Godot (GDScript) Rules
* **Typing:** Strong typing is required (e.g., `var speed: float = 10.0`).
* **Exports:** Use `@export` with ranges for editor-adjustable settings.
* **Networking:** Use `server.poll()` in `_physics_process()` to keep the UDP buffer clear.
* **Interpolation:** Apply input curves and smoothing to prevent jitter.
* **Safety:** Check `data.get("key", default)` to prevent crashes on malformed packets.

## 5. Control Mapping

| Input | Tracking Method | Game Action |
|-------|----------------|-------------|
| Look Left/Right | Nose X offset from center | Camera Yaw (continuous rotation) |
| Look Up/Down | Nose Y offset from center | Camera Pitch (continuous rotation) |
| Strafe Left/Right | Shoulder center X offset | Player strafe movement |
| Walk Forward/Back | Face size (eye distance) | Player walk movement |

**Joystick-Style Controls:**
- Deadzone circle (inner) - no movement when inside
- Max radius circle (outer) - full speed when at edge
- Input curve applies for precision near center
- Body offset compensation prevents strafe from affecting look

## 6. Current Development State

### Completed ✅
- [x] Basic folder structure
- [x] Python vision server with MediaPipe Holistic
- [x] Head tracking (nose position) → Camera rotation
- [x] Joystick-style controls with deadzone and max radius
- [x] Body tracking (shoulders) → Strafe movement
- [x] Depth tracking (face size) → Forward/back movement
- [x] Calibration system (30 frames averaged for stability)
- [x] Body offset compensation (strafe doesn't affect camera)
- [x] Modular Python codebase with separate tracker classes
- [x] Editor-adjustable settings in Godot (sensitivity, curves, speeds)
- [x] Debug visualization overlay (circles, values, calibration progress)

### Next Goal 🎯: Implement Arms/Hands + Cipher Casting System

The player will draw symbols (ciphers) in the air with their hand to cast spells:

| Symbol | Spell | Effect |
|--------|-------|--------|
| Triangle △ | Fireball | Shoots a fireball projectile |
| Circle ○ | Shield | Creates a protective barrier |
| Square □ | TBD | TBD |
| Line — | TBD | TBD |

**Implementation Plan:**
1. **Hand Tracking:** Use MediaPipe hand landmarks to track fingertip position
2. **Gesture Recording:** Record hand path when "drawing" (e.g., while making a fist or pinching)
3. **Symbol Recognition:** Compare drawn path against known cipher patterns
4. **Spell Trigger:** Send recognized cipher name to Godot to trigger spell effects
5. **Visual Feedback:** Show drawn path in debug view, particle effects in game

**New Tracker to Create:** `trackers/gesture.py` - GestureTracker for symbol recognition

### Future Ideas 💡
- Multiple spell types and combinations
- Mana/cooldown system
- Enemy AI that reacts to spells
- Dungeon exploration
- VR support
