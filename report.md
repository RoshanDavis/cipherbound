# Cipherbound — Project Report

## What Problem Is Being Solved

Traditional video game input relies entirely on physical controllers — gamepads, keyboards, and mice — creating a barrier between the player and the game world. The player's body becomes a passive participant, limited to pressing buttons rather than performing the actions their character takes on screen. **Cipherbound** addresses this disconnect by removing the controller entirely and replacing it with the player's own body as the input device. Using a standard webcam and computer vision, the system tracks the player's head movements for camera control, body lean for character movement, and hand gestures for spell casting, creating a fully immersive "no-controller" gameplay experience. The core challenge is building a real-time computer vision pipeline that can simultaneously track face, body, and hand landmarks at 30+ FPS, interpret those landmarks as meaningful game inputs (look direction, strafe/walk velocity, gesture recognition), and transmit that data with minimal latency to a live 3D game engine — all while remaining robust to varying lighting, camera quality, and user physiology.

## Approach Taken

The project uses a **"Side-Car" architecture** — two independent processes running concurrently and communicating over local UDP. The **Vision Server** is a Python application built on Google's MediaPipe Holistic model that captures webcam frames, extracts face, pose, and hand landmarks, and converts them into game-ready control values through a modular tracker pipeline. A `LookTracker` maps nose displacement from a calibrated center into joystick-style camera rotation; a `StrafeTracker` uses shoulder center offset for left/right movement; a `DepthTracker` derives forward/backward motion from relative face size (eye distance); and a `HandTracker` + `GestureTracker` pipeline detects hand states (open, closed, pointing) and recognizes drawn shapes using the **$1 Unistroke Recognizer** algorithm with orientation-sensitive template matching. Each frame produces a JSON data packet sent via UDP to `localhost:5005`. The **Game Client** is a Godot 4.5 project using GDScript that receives this data through a `UDPServer`, drives a third-person character controller with SpringArm3D camera collision avoidance, an AnimationTree-based locomotion and combat animation system, a spell effects system using GPUParticles3D, a wave-based enemy AI spawner, and a full HUD with health/mana bars and real-time cipher stroke visualization.

## What Was Achieved

The result is a fully functional third-person wizard RPG controlled entirely by body movements through a webcam. The vision system performs real-time auto-calibration (the player stands still for ~1 second on startup), then continuously tracks head, body, and hands simultaneously. Eight distinct cipher spells are recognized — upward chevron for Air Jump, downward chevron for Ground Smash, square for AOE Shield, circle for AOE Attack, Z-shape for Fireball, right/left chevrons for directional dashes, and horizontal/vertical lines for strike attacks — each with unique GPUParticles3D visual effects spawned at contextually appropriate locations (feet, ground, body, or hands). The game features a complete enemy system with AI state machines (idle, patrol, chase, attack, hurt, dead), wave-based spawning, a GameManager tracking health/score/waves, an AudioManager with SFX pooling, and a SceneManager with fade transitions. The vision server maintains 30+ FPS processing with debug visualization showing calibration progress, landmark tracking, deadzone/max-radius overlays, and real-time stroke rendering. Camera switching (press 'C') and recalibration (press 'R') are supported at runtime.

---

## How to Execute the Code

### Prerequisites

This project was developed and tested on a **Windows 11 (64-bit) laptop**. Ensure the following are available on your system before running:

| Requirement | Details |
|---|---|
| **Operating System** | **Windows 11 (64-bit)** — developed and tested on this OS. Windows 10 (64-bit) may also work but has not been verified. macOS and Linux are **not supported**. |
| **Python** | **Python 3.11.9** (exact version required — other versions may cause MediaPipe compatibility issues) |
| **Webcam** | Any USB or built-in webcam (640×480 minimum resolution) |
| **Godot Engine** | Included in the submission as `godot.exe` (Godot 4.5, Forward Plus renderer) — **do not download separately** |

> **Important:** Python 3.11.9 is strictly required. MediaPipe and its dependencies are pinned to versions that are only guaranteed to work with Python 3.11.x. Using Python 3.12+ or 3.10 and below may result in installation failures or runtime errors. The Python installer can be downloaded from https://www.python.org/downloads/release/python-3119/ — choose the **"Windows installer (64-bit)"** option and ensure **"Add Python to PATH"** is checked during installation.

### Step-by-Step Execution Instructions

#### Step 1: Extract the Submission

Extract the submitted `.zip` file to any location on your computer. After extraction you should see the following top-level contents:

```
<extracted-folder>/
├── cipherbound-game/     ← Godot game project
├── vision/               ← Python vision server (no venv included)
└── godot.exe             ← Godot 4.5 game engine executable
```

#### Step 2: Set Up the Python Virtual Environment

Open a **PowerShell** or **Command Prompt** terminal and navigate to the `vision` folder inside the extracted directory.

```powershell
cd <path-to-extracted-folder>\vision
```

Create a new Python 3.11.9 virtual environment:

```powershell
py -3.11 -m venv venv
```

> **Note:** If `py -3.11` does not work, use the full path to your Python 3.11.9 installation:
> ```powershell
> "C:\Users\<YourUser>\AppData\Local\Programs\Python\Python311\python.exe" -m venv venv
> ```

Activate the virtual environment:

```powershell
.\venv\Scripts\Activate
```

You should see `(venv)` appear at the beginning of your terminal prompt.

#### Step 3: Install Python Dependencies

With the virtual environment activated, install all required packages:

```powershell
pip install -r requirements.txt
```

This will install: MediaPipe (≥0.10.18), OpenCV (4.13.0.90), NumPy (2.4.1), Matplotlib (3.10.8), and all other dependencies.

Wait for the installation to complete. This may take 1–3 minutes depending on your internet speed.

#### Step 4: Start the Vision Server

With the virtual environment still activated, run the vision server:

```powershell
python src/main.py
```

You should see output similar to:

```
--- CIPHERBOUND VISION SERVER ---
Target: 127.0.0.1:5005
Press 'ESC' to quit, 'R' to recalibrate, 'C' to switch camera
Mode: Holistic (Face + Body + Hands)
Handedness: Right-handed

Opening camera 0...
Waiting for camera to initialize...
Camera ready: 640x480
Starting vision loop...
Debug window created - should appear on screen
```

A debug window titled **"Cipherbound Vision Eye"** will appear showing your webcam feed with tracking overlays.

**Calibration:** Stand still and face the camera for approximately 1 second. The display will show "CALIBRATING... X%" until it reaches 100%. Once calibrated, head and body tracking values will appear on screen.

> **Troubleshooting:** If no camera is detected, the server will print an error. If your webcam is not index 0, press **'C'** to cycle through available camera indices.

#### Step 5: Run the Game

**Keep the vision server running** in its terminal. Open a **second terminal** or use File Explorer.

Double-click the included `godot.exe` at the root of the extracted folder. The Godot Project Manager will open.

First, import the project:

1. Click **"Import"** in the Project Manager
2. Navigate to `<extracted-folder>\cipherbound-game\`
3. Select the `project.godot` file and click **"Open"**

Once the project appears in the Project Manager list, there are **two ways** to run the game:

**Option A — Run Directly from the Project Manager (Quick Method):**

1. Select the **cipherbound-game** project in the Project Manager list
2. Click the **"Run"** button (▶) at the top-right of the Project Manager
3. The game will launch immediately without opening the editor

**Option B — Open the Editor First, Then Run:**

1. Select the **cipherbound-game** project in the Project Manager list
2. Click **"Edit"** to open the project in the Godot editor
3. Once the editor loads, press **F5** (or click the ▶ Play button in the top-right toolbar) to run the game

Either method will start the game, which will automatically connect to the vision server on `localhost:5005`. You should see the third-person view of the wizard character.

#### Step 7: Play!

With both the vision server and the game running simultaneously:

| Action | How to Perform |
|---|---|
| **Look around** | Move your head left/right/up/down |
| **Walk forward/back** | Lean your body toward or away from the camera |
| **Strafe left/right** | Lean your body left or right |
| **Enter spell mode** | Open your left hand (palm facing camera) |
| **Draw a cipher** | Point with your right index finger and draw a shape |
| **Cast the spell** | Open your right hand to finish drawing |
| **Cancel spell** | Close your left hand (make a fist) |
| **Recalibrate vision** | Press 'R' in the vision debug window |
| **Switch camera** | Press 'C' in the vision debug window |
| **Quit vision server** | Press 'ESC' in the vision debug window |

**Available Cipher Shapes:**

| Shape You Draw | Spell Triggered | Effect |
|---|---|---|
| `^` Chevron up | Air Jump | Wind burst launches player skyward |
| `v` Chevron down | Ground Smash | Ground-pound area attack |
| `□` Square | AOE Attack | Area of effect blast |
| `○` Circle | AOE Attack | Area of effect blast |
| `Z` Zigzag | Fireball | Projectile thrown forward |
| `>` Chevron right | Dash Right | Lateral dash to the right |
| `<` Chevron left | Dash Left | Lateral dash to the left |
| `—` Horizontal line | Horizontal Strike | Horizontal slash attack |
| `|` Vertical line | Vertical Strike | Vertical upward strike |

---

## Folder Structure

```
<submission-root>/
│
├── godot.exe                          # Godot 4.5 game engine (included — do NOT download separately)
│
├── cipherbound-game/                  # Godot 4.5 Game Project
│   ├── project.godot                  # Godot project configuration (autoloads, settings)
│   ├── export_presets.cfg             # Export configuration for Windows Desktop
│   ├── icon.svg                       # Project icon
│   │
│   ├── scenes/                        # Scene files (.tscn)
│   │   ├── game.tscn                  # Main game scene (world, enemies, player)
│   │   ├── player/
│   │   │   └── player.tscn           # Player character scene (CharacterBody3D)
│   │   ├── enemies/
│   │   │   ├── slime.tscn            # Slime enemy prefab
│   │   │   └── enemy_spawner.tscn    # Wave-based enemy spawner
│   │   ├── particles/                 # GPU particle effect scenes (11 .tscn files)
│   │   │   ├── air_burst_particles.tscn
│   │   │   ├── dash_trail_particles.tscn
│   │   │   ├── ground_slam_particles.tscn
│   │   │   ├── ground_wave_particles.tscn
│   │   │   ├── horizontal_strike_particles.tscn
│   │   │   ├── projectile_core_particles.tscn
│   │   │   ├── projectile_trail_particles.tscn
│   │   │   ├── shield_burst_particles.tscn
│   │   │   ├── shield_sustain_particles.tscn
│   │   │   ├── slash_particles.tscn
│   │   │   └── vertical_strike_particles.tscn
│   │   └── ui/
│   │       └── game_hud.tscn         # In-game HUD (health, mana, cipher canvas)
│   │
│   ├── scripts/                       # GDScript source files
│   │   ├── player/
│   │   │   ├── player_controller.gd  # Main player controller — UDP, movement, spell dispatch
│   │   │   ├── camera_rig.gd         # Third-person SpringArm3D camera with head tracking
│   │   │   └── player_animator.gd    # AnimationTree driver (locomotion + combat states)
│   │   ├── spells/
│   │   │   ├── spell_manager.gd      # Autoload singleton — spell registration and dispatch
│   │   │   └── effects/
│   │   │       ├── base_effect.gd    # Base class for all spell effects
│   │   │       ├── foot_effect.gd    # Effects at player feet (jump, dash)
│   │   │       ├── ground_effect.gd  # Effects on ground (smash)
│   │   │       ├── body_effect.gd    # Effects from body center (shield)
│   │   │       └── hand_effect.gd    # Effects near hands (projectile, slash)
│   │   ├── managers/
│   │   │   ├── game_manager.gd       # Autoload — health, score, wave state, game state
│   │   │   ├── audio_manager.gd      # Autoload — SFX pool, music playback, volume
│   │   │   └── scene_manager.gd      # Autoload — scene transitions with fade effects
│   │   ├── ui/
│   │   │   └── game_hud.gd           # HUD script (health/mana bars, cipher visualization)
│   │   ├── enemies/
│   │   │   ├── base_enemy.gd         # Base enemy class (AI states, health, combat)
│   │   │   ├── enemy_spawner.gd      # Wave-based spawning system
│   │   │   └── slime.gd             # Slime enemy (extends BaseEnemy)
│   │   └── deprecated/               # Legacy scripts (reference only, not used)
│   │       ├── Arms.gd
│   │       ├── CipherDrawer.gd
│   │       └── HeadController.gd
│   │
│   ├── assets/
│   │   ├── models/
│   │   │   ├── Characters/           # Character 3D models
│   │   │   └── Environment/          # Environment 3D models
│   │   └── animations/
│   │       └── Player/               # Player animation FBX files
│   │
│   └── .godot/                        # Godot cache/import directory (auto-generated)
│
└── vision/                            # Python Vision Server
    ├── requirements.txt               # Python dependency list (pip install -r)
    └── src/                           # Python source code
        ├── main.py                    # Entry point — webcam capture, main loop, debug overlay
        ├── config.py                  # Configuration constants (UDP, camera, deadzones)
        ├── network.py                 # UDPSender class (JSON over UDP)
        └── trackers/                  # Modular tracking pipeline
            ├── __init__.py            # Package exports
            ├── base.py               # BaseTracker ABC (calibration framework)
            ├── look.py               # LookTracker (nose → camera rotation)
            ├── strafe.py             # StrafeTracker (shoulders → left/right movement)
            ├── depth.py              # DepthTracker (face size → forward/back movement)
            ├── hands.py              # HandTracker (hand positions and gesture states)
            ├── shape_recognizer.py   # $1 Unistroke Recognizer + GestureTracker
            ├── cipher_templates.py   # Cipher shape definitions (editable templates)
            └── gestures.py           # Legacy gesture recognizer (reference only)
```

---

## Required Setup Details

### Development Environment

This project was developed and tested on the following system:

| Component | Details |
|---|---|
| **Operating System** | Windows 11 (64-bit) |
| **Python Version** | 3.11.9 |
| **Godot Version** | 4.5 (Forward Plus renderer) |
| **Input Device** | Built-in laptop webcam (640×480) |

### Software Requirements

| Software | Version | Purpose | Notes |
|---|---|---|---|
| **Windows** | **11 (64-bit)** | Operating system | Developed and tested on Windows 11. Windows 10 (64-bit) may work but is untested. **macOS and Linux are not supported.** |
| **Python** | **3.11.9** | Vision server runtime | **Exact version required** for MediaPipe compatibility. Download from https://www.python.org/downloads/release/python-3119/ |
| **pip** | (bundled with Python) | Package installation | Used to install `requirements.txt` |
| **Godot Engine** | 4.5 (Forward Plus) | Game engine | **Included as `godot.exe`** in the submission — do not download separately |
| **Webcam** | Any | Computer vision input | USB or built-in; 640×480 minimum resolution |

### Python Dependencies (installed via `requirements.txt`)

| Package | Version | Purpose |
|---|---|---|
| `mediapipe` | ≥0.10.18 | Face, pose, and hand landmark detection (Holistic model) |
| `opencv-contrib-python` | 4.13.0.90 | Webcam capture, image processing, debug visualization |
| `opencv-python` | 4.13.0.90 | Core OpenCV bindings |
| `numpy` | 2.4.1 | Numerical computation for tracking math |
| `matplotlib` | 3.10.8 | Plotting utilities (used in testing/debug) |
| `sounddevice` | 0.5.5 | Audio device access |
| `pillow` | 12.1.0 | Image processing |
| `flatbuffers` | 25.12.19 | MediaPipe model serialization |
| `absl-py` | 2.3.1 | MediaPipe dependency |

### Godot Autoloads (Pre-configured in `project.godot`)

The following singleton scripts are automatically loaded when the game starts — no manual setup is required:

| Autoload Name | Script Path |
|---|---|
| `GameManager` | `res://scripts/managers/game_manager.gd` |
| `AudioManager` | `res://scripts/managers/audio_manager.gd` |
| `SceneManager` | `res://scripts/managers/scene_manager.gd` |
| `SpellManager` | `res://scripts/spells/spell_manager.gd` |

### Network Configuration

The vision server and Godot game communicate via **UDP on localhost (127.0.0.1) port 5005**. This is a local-only connection — no internet access or firewall changes are needed. If your firewall prompts for permission, allow the connection for `python.exe` and `godot.exe` on private networks.

### Configuration Options (Optional)

The file `vision/src/config.py` contains tunable parameters:

| Parameter | Default | Description |
|---|---|---|
| `WEBCAM_ID` | `0` (or `$env:WEBCAM_ID`) | Camera index (0 = default webcam) |
| `DEBUG_MODE` | `True` | Show debug visualization window |
| `UDP_IP` | `127.0.0.1` | Target IP for UDP packets |
| `UDP_PORT` | `5005` | Target port for UDP packets |
| `CALIBRATION_FRAMES` | `30` | Samples needed for auto-calibration |
| `LEFT_HANDED` | `False` | Swap control/drawing hand roles |
| `LOOK_DEADZONE_RADIUS` | `0.015` | Head movement deadzone (prevents jitter) |
| `LOOK_MAX_RADIUS` | `0.07` | Head movement max speed threshold |
| `MOVE_DEADZONE_RADIUS` | `0.02` | Body lean deadzone |
| `MOVE_MAX_RADIUS` | `0.08` | Body lean max speed threshold |

---

## Quick-Start Summary

```
1.  Extract the zip file
2.  Open PowerShell, navigate to the vision folder
3.  Run:   py -3.11 -m venv venv
4.  Run:   .\venv\Scripts\Activate
5.  Run:   pip install -r requirements.txt
6.  Run:   python src/main.py
7.  Stand still facing the camera until calibration completes (about 1 second)
8.  Double-click godot.exe at the root of the extracted folder
9.  Import the cipherbound-game folder (select project.godot)
10. Run the game — EITHER click "Run" in the Project Manager
    OR click "Edit" to open the editor, then press F5
11. Play using your body — move your head, lean, and draw cipher shapes with your hands!
```
