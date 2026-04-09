# 🧙 Cipherbound

**A gesture-controlled fantasy RPG where your body is the controller.**

Use computer vision–powered hand tracking and body pose detection to cast spells, move through the world, and battle enemies — all without touching a keyboard or gamepad.

> **Note:** This repository contains the source code for Cipherbound. Game assets (3D models, animations, textures) are not included due to licensing and file size constraints. The game cannot be run directly from a clone of this repo — this repository is provided for reference and code review purposes.

---

## 🎮 What Is Cipherbound?

Traditional video game input relies entirely on physical controllers — gamepads, keyboards, and mice — creating a barrier between the player and the game world. **Cipherbound** removes the controller entirely and replaces it with the player's own body as the input device.

Using a standard webcam and real-time computer vision, the system tracks:

- **Head movements** → Camera control (look around)
- **Body lean** → Character movement (walk, strafe)
- **Hand gestures** → Spell casting (draw shapes in the air to cast magic)

The result is a fully immersive "no-controller" third-person wizard RPG.

---

## 🏗️ Architecture

Cipherbound uses a **"Side-Car" architecture** — two independent processes running concurrently and communicating over local UDP.

```
┌──────────────────────────┐        UDP (JSON)        ┌──────────────────────────┐
│     VISION SERVER        │ ──── localhost:5005 ────▶ │      GAME CLIENT         │
│        (Python)          │                           │      (Godot 4.5)         │
│                          │                           │                          │
│  • Webcam capture        │                           │  • 3D world rendering    │
│  • MediaPipe tracking    │                           │  • Character controller  │
│  • Gesture recognition   │                           │  • Spell VFX system      │
│  • 30+ FPS processing    │                           │  • Enemy AI & waves      │
└──────────────────────────┘                           └──────────────────────────┘
```

### Vision Server (Python)

The "Eye" of the system. Captures webcam frames, processes them through Google's MediaPipe Holistic model, and converts landmark data into game-ready control values through a modular tracker pipeline:

| Tracker | Input | Output |
|---------|-------|--------|
| `LookTracker` | Nose displacement from calibrated center | Joystick-style camera yaw/pitch |
| `StrafeTracker` | Shoulder center X offset | Left/right movement velocity |
| `DepthTracker` | Face size (inter-eye distance) | Forward/backward movement velocity |
| `HandTracker` | Hand landmark positions | Hand states (open, closed, pointing) |
| `GestureTracker` | Stroke path drawn by pointing finger | Shape recognition via $1 Unistroke Recognizer |

### Game Client (Godot 4.5)

The "World" of the system. A third-person RPG built in Godot 4.5 with GDScript featuring:

- **SpringArm3D camera** with collision avoidance driven by head tracking
- **AnimationTree** locomotion and combat system with blend spaces
- **Spell effects** using GPUParticles3D at contextual spawn locations
- **Wave-based enemy AI** with state machines (idle, patrol, chase, attack)
- **Full HUD** with health/mana bars and real-time cipher stroke visualization

---

## ✨ Features

- **Full body tracking** — Head, torso, and dual-hand tracking running simultaneously
- **Auto-calibration** — Stand still for ~1 second on startup; the system adapts to your position
- **8 unique cipher spells** — Draw shapes in the air to trigger different abilities
- **Real-time stroke visualization** — See your drawn cipher on the HUD as you trace it
- **Wave-based combat** — Fight increasingly difficult waves of enemies
- **Modular tracker pipeline** — Each tracking axis is an independent, swappable module
- **Configurable deadzones** — Adjustable sensitivity for head/body/hand tracking
- **Debug visualization** — Overlay showing landmarks, deadzones, and calibration status
- **Runtime camera switching** — Cycle through available webcams with a keypress

---

## 🔮 Cipher Spells

Draw these shapes in the air with your right index finger (while your left hand is open) to cast spells:

| Shape | Cipher | Spell | Effect |
|-------|--------|-------|--------|
| `^` Chevron up | `air_blast` | Air Jump | 💨 Wind burst launches player skyward |
| `v` Chevron down | `water` | Ground Smash | 💧 Ground-pound area attack |
| `□` Square | `shield` | Shield | 🛡️ Magical barrier surrounds player |
| `Z` Zigzag | `lightning` | Fireball | ⚡ Projectile thrown forward |
| `>` Chevron right | `arrow_right` | Dash Right | ➡️ Lateral dash to the right |
| `<` Chevron left | `arrow_left` | Dash Left | ⬅️ Lateral dash to the left |
| `—` Horizontal line | `swipe` | Horizontal Strike | ⚔️ Horizontal slash attack |
| `|` Vertical line | `swipe_vertical` | Vertical Strike | ⬆️ Vertical upward strike |

### How Cipher Casting Works

1. **Open your left hand** (palm facing camera) → Enters drawing mode
2. **Point with your right index finger** → Trace a shape in the air
3. **Open your right hand** → Finishes the stroke and casts the recognized spell
4. **Close your left fist** → Cancels the current spell

Recognition uses the **$1 Unistroke Recognizer** algorithm with orientation-sensitive template matching.

---

## 🗂️ Project Structure

```
cipherbound/
├── vision/                          # Python Vision Server
│   ├── requirements.txt             # Python dependencies
│   └── src/
│       ├── main.py                  # Entry point — webcam capture, main loop, debug overlay
│       ├── config.py                # Configuration constants (UDP, camera, deadzones)
│       ├── network.py               # UDPSender class (JSON over UDP)
│       └── trackers/                # Modular tracking pipeline
│           ├── base.py              # BaseTracker ABC with calibration framework
│           ├── look.py              # LookTracker — nose → camera rotation
│           ├── strafe.py            # StrafeTracker — shoulders → left/right
│           ├── depth.py             # DepthTracker — face size → forward/back
│           ├── hands.py             # HandTracker — hand positions & gesture states
│           ├── shape_recognizer.py  # $1 Unistroke Recognizer + GestureTracker
│           └── cipher_templates.py  # Editable cipher shape definitions
│
├── cipherbound-game/                # Godot 4.5 Game Project
│   ├── project.godot                # Godot project configuration
│   ├── scripts/
│   │   ├── player/
│   │   │   ├── player_controller.gd # Main controller — UDP input, movement, spell dispatch
│   │   │   ├── camera_rig.gd        # Third-person SpringArm3D camera
│   │   │   └── player_animator.gd   # AnimationTree driver
│   │   ├── spells/
│   │   │   ├── spell_manager.gd     # Autoload singleton — spell registration & dispatch
│   │   │   └── effects/             # GPUParticles3D spell effect scripts
│   │   ├── managers/
│   │   │   ├── game_manager.gd      # Health, mana, score, wave state
│   │   │   ├── audio_manager.gd     # SFX pool and music playback
│   │   │   └── scene_manager.gd     # Scene transitions with fade effects
│   │   ├── ui/
│   │   │   └── game_hud.gd          # HUD — health/mana bars, cipher visualization
│   │   └── enemies/
│   │       ├── base_enemy.gd        # Base enemy class with AI state machine
│   │       └── enemy_spawner.gd     # Wave-based spawning system
│   └── scenes/                      # .tscn scene files (game, player, particles, UI)
│
├── CONTEXT.md                       # Detailed technical context document
└── README.md                        # This file
```

> **Note:** The `cipherbound-game/assets/` directory (3D models, animations, textures) is not included in this repository due to their large size.

---

## 🛠️ Tech Stack

| Component | Technology |
|-----------|------------|
| **Vision Server** | Python 3.11, MediaPipe Holistic, OpenCV, NumPy |
| **Game Engine** | Godot 4.5 (Forward Plus renderer), GDScript |
| **Networking** | UDP (JSON packets on `localhost:5005`) |
| **Gesture Recognition** | $1 Unistroke Recognizer (geometric template matching) |
| **Particle Effects** | GPUParticles3D with custom shader materials |
| **Animation** | AnimationTree with BlendSpace2D locomotion + StateMachine combat |

---

## 🎮 Controls

| Action | How |
|--------|-----|
| **Look around** | Move your head |
| **Walk / strafe** | Lean your torso forward, backward, left, or right |
| **Enter spell mode** | Open your left hand (palm facing camera) |
| **Draw a cipher** | Point with your right index finger and trace a shape |
| **Cast the spell** | Open your right hand |
| **Cancel the spell** | Close your left hand into a fist |

### Vision Server Hotkeys

| Key | Action |
|-----|--------|
| `R` | Recalibrate tracking |
| `C` | Cycle through available cameras |
| `Esc` | Quit the vision server |

---

