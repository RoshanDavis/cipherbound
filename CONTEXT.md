# PROJECT CONTEXT: CIPHERBOUND

## 1. Project Overview
**Name:** Cipherbound  
**Genre:** Third-Person Wizard RPG  
**Core Mechanic:** "No-Controller" Input. The player controls the game entirely using computer vision (Head tracking for camera, Body lean for movement, Hand gestures for magic).  
**Goal:** Build a cohesive "Side-Car" application where a lightweight Python vision server drives a Godot 4 game client in real-time.

## 2. Technical Architecture: "The Side-Car Pattern"
The project consists of two independent processes communicating via local UDP.

### A. The Vision Server (Python)
* **Role:** The "Eye". Captures webcam input, processes it via AI, and blasts JSON coordinates to Godot.
* **Tech Stack:** Python 3.10+, MediaPipe (Holistic/Hands), OpenCV, NumPy, Socket (UDP).
* **Output:** Sends JSON packets to `localhost:5005`.
* **Constraint:** Must run at 30+ FPS. No heavy game logic here, only detection logic.

**Modular Structure:**
```text
vision/src/
├── config.py              # All configuration constants
├── network.py             # UDP sender class
├── main.py                # Main entry point & debug visualization
└── trackers/
    ├── __init__.py        # Package exports
    ├── base.py            # BaseTracker with calibration logic
    ├── look.py            # LookTracker (nose → camera rotation)
    ├── strafe.py          # StrafeTracker (shoulders → left/right)
    ├── depth.py           # DepthTracker (face size → forward/back)
    ├── hands.py           # HandTracker (hand positions & gestures)
    ├── cipher_templates.py # Configurable cipher shape definitions
    ├── gestures.py        # $1 Unistroke Recognizer (legacy/reference)
    └── shape_recognizer.py # Shape recognition implementation
```

**Current Data Packet:**
```jsonc
{
  "has_face": true,
  "look_x": 0.0,          // -1 to +1, joystick-style camera rotation
  "look_y": 0.0,          // -1 to +1, joystick-style camera rotation  
  "has_body": true,
  "lean_x": 0.0,          // -1 to +1, strafe left/right (shoulder tracking)
  "lean_y": 0.0,          // -1 to +1, walk forward/back (face depth/size)
  "calibrated": true,
  
  // Hand tracking
  "has_left_hand": true,
  "has_right_hand": true,
  "left_hand": {
    "palm": {"x": 0.0, "y": 0.0, "z": 0.0},
    "is_open": false,
    "is_pointing": true,
    "is_closed": false
  },
  "right_hand": { /* same structure */ },
  
  // Gesture recognition (Python-side)
  "gesture_state": "idle|ready_to_draw|drawing",
  "gesture_recognized": "fire|water|shield|lightning|swipe|...|null",
  "gesture_score": 0.85,
  "stroke_points": [[x, y], ...]  // For Godot visualization (downsampled stroke)
}
```

### B. The Game Client (Godot 4)
* **Role:** The "World". Renders the game and interprets raw data into game actions.
* **Tech Stack:** Godot 4.x, GDScript.
* **Input:** Listens on UDP Port 5005 via `UDPServer`.
* **View:** Third-person over-the-shoulder camera with SpringArm3D collision avoidance.
* **Gesture Recognition:** Handled Python-side; Godot receives recognized gestures and triggers character animations/spells.

**Godot Script Structure (Feature-Based Organization):**
```text
cipherbound-game/scripts/
├── player/                   # Player-related scripts
│   ├── player_controller.gd  # Main player controller - UDP, movement, spell dispatch
│   ├── camera_rig.gd         # Third-person SpringArm camera with head tracking
│   └── player_animator.gd    # Animation state machine (idle, walk, run, cast)
├── vision/                   # Vision/HUD integration
│   └── cipher_hud.gd         # HUD for stroke visualization & spell feedback
├── spells/                   # Spell system
│   └── spell_manager.gd      # Autoload singleton for spell registration & dispatch
└── deprecated/               # Legacy scripts (kept for reference)
    ├── Arms.gd               # Old first-person arm visualization
    ├── CipherDrawer.gd       # Old Godot-side pattern matching
    └── HeadController.gd     # Old head controller
```

**Player Scene Node Structure:**
```text
Player (CharacterBody3D) - player_controller.gd
├── CameraRig (Node3D) - camera_rig.gd
│   └── SpringArm3D
│       └── Camera3D
├── CollisionShape3D
├── PlayerModel (Node3D)
│   ├── GeneralSkeleton (Skeleton3D)
│   │   ├── Body, Lower_Armor, Head_Hands (MeshInstance3D)
│   ├── AnimationPlayer (with player_library)
│   └── PlayerAnimator (Node) - player_animator.gd
└── SpellOrigin (Marker3D) - spell spawn point
```

## 3. Directory Structure
```text
ROOT (cipherbound/)
├── cipherbound-game/        # Godot Project Root
│   ├── scripts/             # All GDScript files
│   │   ├── player/          # Player controller, camera, animator
│   │   ├── vision/          # HUD and vision integration
│   │   ├── spells/          # Spell manager and effects
│   │   └── deprecated/      # Legacy scripts (reference only)
│   ├── scenes/              # .tscn scene files
│   │   ├── player/          # Player scene
│   │   └── game.tscn        # Main game scene
│   └── assets/              # Models, animations, textures
│       ├── models/          # Character and environment models
│       └── animation libraries/ # Animation resources
├── vision/                  # Python Project Root
│   ├── src/                 # Python source code
│   │   ├── trackers/        # Tracker modules
│   │   │   └── cipher_templates.py  # User-editable shape templates
│   │   ├── main.py
│   │   └── ...
├── CONTEXT.md               # This file
└── README.md
```

## 4. Coding Guidelines & Standards

### Python Rules
* **Type Hinting:** Use `def function() -> dict:` for clarity.
* **Performance:** Use NumPy. Avoid heavy loops in main thread.
* **Networking:** JSON over UDP.
* **Modularity:** Separate tracking logic from main loop.

### Godot (GDScript) Rules
* **Typing:** Strong typing required.
* **Nodes:** Create UI nodes dynamically in `_ready()` if scripts are attached at runtime (fixes `@onready` issues).
* **Networking:** Poll server in `_physics_process`.

## 5. Control Mapping

| Input | Tracking Method | Game Action |
|-------|----------------|-------------|
| Look Left/Right | Nose X offset from center | Camera Yaw |
| Look Up/Down | Nose Y offset from center | Camera Pitch |
| Strafe Left/Right | Shoulder center X offset | Player Strafe |
| Walk Forward/Back | Face size (eye distance) | Player Walk |
| Cast Spell | Draw shape with pointing finger | Trigger Magic |

## 6. Cipher Casting System

### Mechanics
1. **Control Hand (Left):** OPEN to enable drawing mode. CLOSED to cancel.
2. **Drawing Hand (Right):** POINT to draw. OPEN/CLOSE to finish.
3. **Recognition:** Shape is matched against templates when stroke ends.
4. **Spell Cast:** Python sends `gesture_recognized` event → Godot triggers spell.

### Supported Ciphers (Current)

| Symbol | Cipher Name | Spell | Effect |
|--------|-------------|-------|--------|
| `^` Chevron up | `fire` | Fireball | 🔥 Fire erupts from hands |
| `v` Chevron down | `water` | Water Wave | 💧 Water flows around player |
| `□` Square | `shield` | Shield | 🛡️ Magical barrier surrounds player |
| `Z` Zigzag | `lightning` | Lightning | ⚡ Lightning crackles through air |
| `>` Chevron right | `arrow_right` | Dash Forward | ➡️ Forward dash |
| `<` Chevron left | `arrow_left` | Backstep | ⬅️ Backward leap |
| `-` Line | `swipe` | Quick Slash | 💨 Quick physical slash |
| `\|` Line | `swipe_vertical` | Vertical Strike | ⬆️ Vertical strike |



### Shape Recognition
- **Algorithm:** $1 Unistroke Recognizer (Geometric template matching).
- **Implementation:** `trackers/shape_recognizer.py` + `cipher_templates.py`.
- **Features:**
  - Orientation-sensitive (rotation invariance disabled).
  - Multiple templates per shape (for different stroke directions).
  - Configurable via `cipher_templates.py`.

### Visual Feedback
- **CipherHUD:**
  - Draws the user's stroke in real-time (cyan glow).
  - Fades out stroke on completion/cancellation.
  - Displays recognized spell name and tracking status.
- **PlayerAnimator:**
  - Character performs casting animations when spells are triggered.
  - State machine handles transitions (idle → casting → back to locomotion).
- **Third-Person Camera:**
  - Over-the-shoulder view with SpringArm collision avoidance.
  - Smooth rotation following head tracking input.

## 7. Current Development State

### Completed ✅
- [x] **Vision Core:** MediaPipe Holistic tracking (Face/Body/Hands).
- [x] **Movement:** Head tracking (Camera), Body leaning (Strafe), Depth (Walk).
- [x] **Hand Tracking:** Hand detection, gesture state machine.
- [x] **Shape Recognition:** $1 Recognizer with configurable templates.
- [x] **Ciphers:** 8 active ciphers (Fire, Water, Shield, Lightning, Arrows, Swipes).
- [x] **Networking:** UDP communication of state + stroke points.
- [x] **Game Client:** Godot character controller with "Side-Car" integration.
- [x] **Visuals:** Real-time stroke drawing on HUD.
- [x] **Third-Person Camera:** SpringArm3D camera rig with collision avoidance.
- [x] **Animation System:** PlayerAnimator state machine (structure ready).
- [x] **Spell System:** SpellManager singleton foundation (needs autoload registration).

### Next Goals 🎯
1. **Register SpellManager Autoload:** Add to Project Settings → Autoload.
2. **Animation Integration:** Configure animation names in PlayerAnimator exports.
3. **Spell Visual Effects:** Implement actual spell particle effects.
4. **Game Environment:** Create a test dungeon/arena.
5. **Gameplay Loop:** Add enemies or targets to use spells on.

### Setup Notes
To complete the transition to third-person:
1. Open Godot and go to Project → Project Settings → Autoload.
2. Add `res://scripts/spells/spell_manager.gd` as `SpellManager` (singleton).
3. Verify AnimationPlayer has animations named: `idle`, `walking`, `running`, `casting`.
4. Run the game and test with the Python vision server.
