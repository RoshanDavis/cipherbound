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
  "gesture_recognized": "air_blast|water|shield|lightning|swipe|...|null",
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
│   └── player_animator.gd    # AnimationTree driver (BlendSpace2D locomotion, StateMachine states)
├── spells/                   # Spell system
│   ├── spell_manager.gd      # Autoload singleton for spell registration & dispatch
│   └── effects/              # GPUParticles3D-based spell VFX
│       ├── base_effect.gd    # Base class for all effects
│       ├── foot_effect.gd    # Effects at player feet (jump, dash)
│       ├── ground_effect.gd  # Effects on ground surface (smash)
│       ├── body_effect.gd    # Effects expanding from body (shield)
│       └── hand_effect.gd    # Effects near hands (projectile, slash)
├── managers/                 # Global manager autoloads
│   ├── game_manager.gd       # Player stats (health/mana), wave tracking, game state
│   ├── audio_manager.gd      # SFX pool, music playback, volume control
│   └── scene_manager.gd      # Scene transitions with fade effects
├── ui/                       # UI scripts
│   └── game_hud.gd           # Consolidated HUD - health/mana, cipher drawing, status
├── enemies/                  # Enemy AI system
│   ├── base_enemy.gd         # Base class with health, AI states, navigation
│   └── enemy_spawner.gd      # Wave-based enemy spawning
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
│   ├── AnimationPlayer (with animation libraries, active=OFF)
│   └── PlayerAnimator (AnimationTree) - player_animator.gd
│       └── Root StateMachine:
│           ├── Locomotion (BlendTree) ─ Start Node
│           │   └── Stance Transition: Basic Movement / Cipher Movement
│           │       └── BlendSpace2D with nested Idle Turn BlendSpace1D at (0,0)
│           ├── Cipher Casting (BlendTree)
│           │   └── AbilitySelector Transition (8 abilities)
│           │       ├── Jump, DashLeft, DashRight (Sub-StateMachines with Fall/Land)
│           │       └── SmashGround, ThrowForward, Shield, Swipes (Animations)
│           └── Death (Animation)
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
│   │   │   └── effects/     # GPUParticles3D effect scripts
│   │   ├── managers/        # Global autoload managers
│   │   ├── ui/              # UI scripts (HUD, menus)
│   │   ├── enemies/         # Enemy AI and spawning
│   │   └── deprecated/      # Legacy scripts (reference only)
│   ├── scenes/              # .tscn scene files
│   │   ├── player/          # Player scene
│   │   ├── particles/       # GPUParticles3D VFX scenes
│   │   ├── ui/              # UI scene files
│   │   ├── enemies/         # Enemy prefabs
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
| `^` Chevron up | `air_blast` | Jump | 💨 A blast of air launches you skyward |
| `v` Chevron down | `water` | Smash Ground | 💧 Ground-pound area attack |
| `□` Square | `shield` | Shield | 🛡️ Magical barrier surrounds player |
| `Z` Zigzag | `lightning` | Throw Forward | ⚡ Projectile thrown forward |
| `>` Chevron right | `arrow_right` | Dash Right | ➡️ Lateral dash to the right |
| `<` Chevron left | `arrow_left` | Dash Left | ⬅️ Lateral dash to the left |
| `-` Line | `swipe` | Swipe Horizontal | 💨 Horizontal slash attack |
| `\|` Line | `swipe_vertical` | Swipe Up | ⬆️ Vertical strike attack |



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
- **PlayerAnimator (AnimationTree):**
  - **Root:** AnimationNodeStateMachine with states: Locomotion, Cipher Casting, Death.
  - **Locomotion BlendTree:** Stance Transition between Basic/Cipher movement.
    - Each stance is a BlendSpace2D (strafe/forward) with nested BlendSpace1D at (0,0) for idle turning.
    - Stance switches automatically when entering gesture drawing mode.
  - **Cipher Casting BlendTree:** AbilitySelector Transition with 8 indexed abilities.
    - Physics abilities (Jump, DashLeft, DashRight) are sub-StateMachines: Action→Fall→Land.
    - Script calls `update_floor_status()` to advance Fall→Land based on physics.
  - **Signals:** `jump_launch`, `dash_impulse`, `spell_effect`, `landing_finished` for timing-critical events.
  - **Call Method Tracks:** Keyframed on animations to emit signals at precise moments.
- **Third-Person Camera:**
  - Over-the-shoulder view with SpringArm collision avoidance.
  - Smooth rotation following head tracking input.

## 7. Current Development State

### Completed ✅
- [x] **Vision Core:** MediaPipe Holistic tracking (Face/Body/Hands).
- [x] **Movement:** Head tracking (Camera), Body leaning (Strafe), Depth (Walk).
- [x] **Hand Tracking:** Hand detection, gesture state machine.
- [x] **Shape Recognition:** $1 Recognizer with configurable templates.
- [x] **Ciphers:** 8 active ciphers (Jump, Smash Ground, Shield, Throw Forward, Dashes, Swipes).
- [x] **Networking:** UDP communication of state + stroke points.
- [x] **Game Client:** Godot character controller with "Side-Car" integration.
- [x] **Visuals:** Real-time stroke drawing on HUD.
- [x] **Third-Person Camera:** SpringArm3D camera rig with collision avoidance.
- [x] **Animation System (Scripts):** PlayerAnimator with stance switching, ability selector, physics-dependent sub-state machines.
- [x] **Spell System:** SpellManager singleton with GPUParticles3D visual effects.
- [x] **Manager Systems:** GameManager, AudioManager, SceneManager autoloads.
- [x] **UI System:** GameHUD with health/mana bars, wave info, cipher visualization.
- [x] **Enemy System:** Base enemy class with AI state machine, wave spawning.

### Next Goals 🎯
1. **AnimationTree Editor Setup:** Build the tree structure in Godot (see setup guide below).
2. **Add Animations to Libraries:** Import FBX animations into library .res files.
3. **Add Call Method Tracks:** Keyframe animation events in AnimationPlayer.
4. **Audio Assets:** Add sound effects and music tracks to AudioManager.
5. **Game Environment:** Create a test dungeon/arena with navigation mesh.
6. **Polish & Balancing:** Tune enemy stats, wave difficulty, spell costs.

## 9. Spell Effects System

### Overview
Each cipher triggers a unique visual effect at different spawn locations relative to the player. Effects use a combination of GPUParticles3D, shaders, and mesh-based effects for a **Fantasy Magic** aesthetic (glowing runes, mystical particles, ethereal auras).

### Spell Effect Spawn Locations

| Cipher | Spell | Spawn Location | Effect Type |
|--------|-------|----------------|-------------|
| `air_blast` | Jump | **Player's feet** | Air burst particles pushing upward |
| `arrow_left` | Dash Left | **Player's feet** | Trail particles + wind burst |
| `arrow_right` | Dash Right | **Player's feet** | Trail particles + wind burst |
| `water` | Smash Ground | **Ground in front** | Impact wave expanding outward |
| `shield` | Shield | **Expanding from player** | Dome/sphere mesh growing outward |
| `lightning` | Throw Forward | **Near hands** | Projectile spawned at hand position |
| `swipe` | Swipe Horizontal | **Near hands** | Arc slash effect at hand level |
| `swipe_vertical` | Swipe Up | **Near hands** | Vertical slash effect at hand level |

### Effect Architecture

```text
cipherbound-game/
├── scenes/
│   └── effects/                    # VFX scene files (.tscn)
│       ├── foot_effects/
│       │   ├── air_burst.tscn      # Jump wind effect
│       │   └── dash_trail.tscn     # Dash movement trail
│       ├── ground_effects/
│       │   └── ground_slam.tscn    # Smash ground impact
│       ├── body_effects/
│       │   └── shield_dome.tscn    # Expanding shield
│       └── hand_effects/
│           ├── projectile.tscn     # Lightning/throw projectile
│           └── slash_arc.tscn      # Swipe effects
├── scripts/
│   └── spells/
│       ├── spell_manager.gd        # Singleton - spell dispatch
│       └── effects/                # Effect scripts
│           ├── base_effect.gd      # Base class for all effects
│           ├── foot_effect.gd      # Effects at player feet
│           ├── ground_effect.gd    # Effects on ground surface
│           ├── body_effect.gd      # Effects expanding from body
│           └── hand_effect.gd      # Effects near hands
└── assets/
    └── materials/
        └── spell_vfx/             # Shader materials for effects
            ├── magic_particle.tres
            ├── shield_shader.tres
            └── slash_trail.tres
```

### Spawn Point References (Player Scene)

The player scene needs multiple `Marker3D` nodes for effect spawn points:

```text
Player (CharacterBody3D)
├── SpellOrigin (Marker3D) - existing, chest height
├── FeetOrigin (Marker3D)  - ground level, at feet center
├── GroundTarget (Marker3D) - 1-2m in front of player at ground level
├── LeftHandOrigin (Marker3D) - bound to left hand bone (optional)
└── RightHandOrigin (Marker3D) - bound to right hand bone (optional)
```

### SpellManager Enhancement

The `spell_manager.gd` will be enhanced to:
1. Preload effect scenes
2. Determine spawn location based on spell type
3. Instantiate effects with proper positioning/rotation
4. Handle effect lifecycle (auto-free after completion)

### Effect Base Class

```gdscript
# scripts/spells/effects/base_effect.gd
extends Node3D
class_name BaseSpellEffect

signal effect_finished

@export var lifetime := 2.0
@export var auto_free := true

func _ready() -> void:
    if auto_free:
        await get_tree().create_timer(lifetime).timeout
        effect_finished.emit()
        queue_free()

func play() -> void:
    # Override in subclasses to trigger particles/animations
    pass
```

### Visual Effect Details

**Air Burst (Jump/Dash):**
- GPUParticles3D with upward/directional velocity
- Cyan-white color gradient
- Wind-like streaks + dust particles
- Brief flash of light

**Ground Slam:**
- Expanding ring mesh with shader
- Debris particles outward
- Screen shake (camera impulse)
- Ground decal (optional)

**Shield Dome:**
- Animated mesh sphere scaling from 0 to full size
- Fresnel shader for ethereal edge glow
- Hexagonal pattern texture (optional)
- Particles along surface

**Hand Effects (Projectile/Slash):**
- Trail renderer for movement
- Glowing rune particles
- Color-coded per element (cyan=wind, yellow=lightning)

### Setup Notes
To complete the transition to third-person:
1. Open Godot and go to Project → Project Settings → Autoload.
2. Autoloads are pre-configured in `project.godot`:
   - `GameManager` - `res://scripts/managers/game_manager.gd`
   - `AudioManager` - `res://scripts/managers/audio_manager.gd`
   - `SceneManager` - `res://scripts/managers/scene_manager.gd`
   - `SpellManager` - `res://scripts/spells/spell_manager.gd`
3. Follow the **AnimationTree Setup Guide** below to configure the AnimationTree.
4. Run the game and test with the Python vision server.

## 10. Manager Systems

### GameManager (Autoload Singleton)
Manages player stats, wave tracking, and game state.

**Signals:**
- `health_changed(current, maximum)` - Player health updated
- `mana_changed(current, maximum)` - Player mana updated
- `wave_started(wave_number, enemy_count)` - Wave begins
- `wave_completed(wave_number)` - Wave cleared
- `enemy_killed(enemy, points)` - Enemy defeated
- `score_changed(new_score)` - Score updated
- `game_over(victory)` - Game ended

**Properties:**
```gdscript
@export var max_health := 100.0
@export var max_mana := 100.0
@export var mana_regen_rate := 5.0  # Per second
var current_health: float
var current_mana: float
var current_wave := 0
var score := 0
var game_state: GameState  # MENU, PLAYING, PAUSED, GAME_OVER, VICTORY
```

**Usage:**
```gdscript
# Take damage
GameManager.take_damage(20)

# Use mana for spell
if GameManager.use_mana(25):
    # Cast spell
    pass

# Check game state
if GameManager.game_state == GameManager.GameState.PLAYING:
    # Game logic
    pass
```

### AudioManager (Autoload Singleton)
Handles sound effects and music with pooling and volume control.

**Features:**
- SFX pool (8 AudioStreamPlayer3D instances)
- 2D SFX support
- Music player with crossfade
- Volume control (master, SFX, music)
- Runtime audio bus creation

**Usage:**
```gdscript
# Play 3D sound effect at position
AudioManager.play_sfx("sword_hit", global_position)

# Play 2D UI sound
AudioManager.play_sfx_2d("menu_click")

# Play background music
AudioManager.play_music("battle_theme")

# Adjust volumes (0.0 to 1.0)
AudioManager.set_master_volume(0.8)
AudioManager.set_sfx_volume(0.7)
AudioManager.set_music_volume(0.5)
```

**Adding Sounds:**
```gdscript
# In AudioManager or at runtime
sfx_library["sword_hit"] = preload("res://assets/audio/sfx/sword_hit.wav")
music_library["battle_theme"] = preload("res://assets/audio/music/battle.ogg")
```

### SceneManager (Autoload Singleton)
Manages scene transitions with fade effects.

**Features:**
- Fade-to-black transitions
- Scene dictionary for easy access
- Signals for transition events
- Screen flash effect

**Usage:**
```gdscript
# Change to a scene
SceneManager.change_scene("main_menu")
SceneManager.change_scene("game")

# Reload current scene
SceneManager.reload_current_scene()

# With custom transition time
SceneManager.change_scene("game", 0.5)  # 0.5 second fade

# Screen flash (for damage, etc.)
SceneManager.fade_flash(0.1)
```

**Configuring Scenes:**
```gdscript
# In scene_manager.gd
const SCENES := {
    "main_menu": "res://scenes/menus/main_menu.tscn",
    "game": "res://scenes/game.tscn",
    "game_over": "res://scenes/menus/game_over.tscn",
}
```

## 11. UI System

### GameHUD
The main in-game HUD displaying player stats, wave information, and cipher visualization.

**Scene:** `scenes/ui/game_hud.tscn`
**Script:** `scripts/ui/game_hud.gd`

**Components:**
- **Health Bar:** Top-left, red ProgressBar with label (100/100)
- **Mana Bar:** Below health, blue ProgressBar with label
- **Wave Label:** Top-right, current wave number
- **Score Label:** Below wave, current score
- **Spell Feedback:** Center screen, shows cast spell names
- **Cipher Canvas:** Full-screen Control for stroke drawing

**Features:**
- Automatic connection to GameManager signals
- Smooth bar animations (lerp-based)
- Spell feedback with fade-out
- Cipher stroke visualization (from original CipherHUD)

**Usage:**
Add the scene to your game:
```gdscript
var hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
add_child(hud)

# Manual updates (if not using GameManager)
hud.update_health(80, 100)
hud.update_mana(50, 100)

# Show spell feedback
hud.show_spell_cast("Lightning Bolt", "⚡")

# Update cipher stroke
hud.update_stroke([[100, 200], [150, 250], [200, 200]])
```

## 12. Enemy System

### BaseEnemy
Base class for all enemies with health, AI states, and combat.

**File:** `scripts/enemies/base_enemy.gd`

**AI States:**
- `IDLE` - Standing still, scanning for player
- `PATROL` - Following patrol points
- `CHASE` - Pursuing the player
- `ATTACK` - In attack range, dealing damage
- `HURT` - Briefly stunned after taking damage
- `DEAD` - Death state, queued for removal

**Exported Properties:**
```gdscript
@export var max_health := 30.0
@export var move_speed := 3.0
@export var chase_speed := 5.0
@export var attack_damage := 10.0
@export var attack_range := 2.0
@export var detection_range := 10.0
@export var attack_cooldown := 1.5
@export var score_value := 100
@export var knockback_resistance := 0.0
@export var patrol_points: Array[Vector3] = []
```

**Signals:**
- `health_changed(current, maximum)`
- `died(enemy)`
- `attacked(target)`

**Creating Custom Enemies:**
```gdscript
# Extend BaseEnemy for custom behavior
extends BaseEnemy
class_name GoblinEnemy

func _ready() -> void:
    max_health = 50.0
    attack_damage = 15.0
    chase_speed = 6.0
    super._ready()

func _perform_attack() -> void:
    # Custom attack logic
    super._perform_attack()
```

### Slime Enemy
Basic enemy prefab extending BaseEnemy.

**Scene:** `scenes/enemies/slime.tscn`

**Stats:**
- Health: 30
- Speed: 2.0 (walk) / 4.0 (chase)
- Damage: 10
- Attack Range: 1.5m
- Detection: 10m
- Score: 100 points

### EnemySpawner
Wave-based enemy spawning system.

**Scene:** `scenes/enemies/enemy_spawner.tscn`
**Script:** `scripts/enemies/enemy_spawner.gd`

**Features:**
- Configurable waves with enemy count and types
- Spawn point markers (Marker3D children)
- Spawn around player option
- Automatic wave progression
- Integration with GameManager

**Exported Properties:**
```gdscript
@export var waves: Array[WaveData] = []
@export var slime_scene: PackedScene
@export var spawn_radius := 15.0
@export var spawn_delay := 0.5
@export var wave_delay := 3.0
@export var auto_start := false
@export var spawn_around_player := false
```

**Signals:**
- `wave_started(wave_number, enemy_count)`
- `wave_completed(wave_number)`
- `all_waves_completed()`
- `enemy_spawned(enemy)`

**Usage:**
```gdscript
# Get spawner reference
@onready var spawner: EnemySpawner = $EnemySpawner

# Start wave spawning
spawner.start_waves()

# Spawn specific wave
spawner.spawn_wave(2)

# Spawn single enemy at position
spawner.spawn_enemy_at("slime", Vector3(10, 0, 5))

# Check alive enemies
var alive := spawner.get_alive_count()
```

**Default Waves (if none configured):**
| Wave | Enemies | Type | Interval |
|------|---------|------|----------|
| 1 | 3 | slime | 0.5s |
| 2 | 5 | slime | 0.45s |
| 3 | 7 | slime | 0.4s |
| 4 | 9 | slime | 0.35s |
| 5 | 11 | slime | 0.3s |

## 8. AnimationTree Editor Setup Guide

This guide walks through building the new AnimationTree structure in Godot's editor.

### Prerequisites
Before starting, ensure:
- Animation libraries exist: `basic_movement_library.res`, `cipher_movement_library.res`, `cipher_casting_library.res`
- Animations are imported into the libraries from FBX files
- The player scene is open in the editor

### Step 1: Prepare the Node
1. Open `scenes/player/player.tscn`
2. Find `PlayerModel > AnimationTree` (or create one if missing)
3. Rename it to `PlayerAnimator`
4. Attach `scripts/player/player_animator.gd` to it
5. In Inspector:
   - Set **Anim Player** → `../AnimationPlayer`
   - Set **Active** → ON
   - Set **Process Mode** → Inherit
6. On `AnimationPlayer`: Set **Active** → OFF (tree drives it now)

### Step 2: Build Root StateMachine
1. Double-click `PlayerAnimator` to open AnimationTree editor
2. Ensure root is `AnimationNodeStateMachine` (default)
3. Right-click canvas → Add nodes:
   - **Add BlendTree** → rename to `Locomotion`
   - **Add BlendTree** → rename to `Cipher Casting`
   - **Add Animation** → rename to `Death`, set animation = `basic_movement_library/death`
4. Right-click `Locomotion` → **Set as Start Node** (green arrow)
5. Draw transitions (click-drag between nodes):

| From | To | Switch Mode | Advance Mode | Xfade |
|------|----|-------------|--------------|-------|
| Locomotion | Cipher Casting | Immediate | Enabled | 0.15 |
| Cipher Casting | Locomotion | AtEnd | Auto | 0.15 |
| Locomotion | Death | Immediate | Enabled | 0.1 |

### Step 3: Build Locomotion BlendTree
1. Double-click `Locomotion` to enter it
2. Add node: **Transition** → rename to `Stance`
3. Select `Stance`, in Inspector:
   - Set **Input Count** = 2
   - Rename: `[0]` = `Basic Movement`, `[1]` = `Cipher Movement`
   - Set **Xfade Time** = 0.2
4. Connect `Output` → `Stance`
5. For **each stance** (Basic Movement, Cipher Movement):
   
   a) Add node: **BlendSpace2D** → rename to match stance
   
   b) Connect `Stance` output → BlendSpace2D
   
   c) Double-click BlendSpace2D to configure:
      - **X**: Min=-1, Max=1, Label="Strafe"
      - **Y**: Min=-1, Max=1, Label="Forward"
      - **Blend Mode**: Interpolated
   
   d) Add blend points (click in grid, type coordinates):
   
   | Position | Animation (use library prefix) |
   |----------|-------------------------------|
   | (0, 0) | **Add BlendSpace1D here** (see below) |
   | (0, 0.5) | basic_movement_library/walking |
   | (0, -0.5) | basic_movement_library/walking back |
   | (0, 1.0) | basic_movement_library/running |
   | (0, -1.0) | basic_movement_library/running back |
   | (-1, 0) | basic_movement_library/walking left |
   | (1, 0) | basic_movement_library/walking right |
   
   e) **Nested Idle Turn** at (0, 0):
      - Add point at (0, 0), but instead of animation, select **Add BlendSpace1D**
      - Configure BlendSpace1D: Min=-1, Max=1, Label="Turn"
      - Add 3 points:
        - (-1.0) = `basic_movement_library/turning left`
        - (0.0) = `basic_movement_library/idle`
        - (1.0) = `basic_movement_library/turning right`

6. Repeat for Cipher Movement using `cipher_movement_library/*`

### Step 4: Build Cipher Casting BlendTree
1. Go back to root (click "Root" breadcrumb)
2. Double-click `Cipher Casting` to enter it
3. Add node: **Transition** → rename to `AbilitySelector`
4. Select `AbilitySelector`, in Inspector:
   - Set **Input Count** = 8
   - Rename inputs:
     - `[0]` = `Jump`
     - `[1]` = `SmashGround`
     - `[2]` = `DashLeft`
     - `[3]` = `DashRight`
     - `[4]` = `ThrowForward`
     - `[5]` = `Shield`
     - `[6]` = `SwipeHorizontal`
     - `[7]` = `SwipeUp`
   - Set **Xfade Time** = 0.1
5. Connect `Output` → `AbilitySelector`

6. **For simple animations** (indices 1, 4, 5, 6, 7):
   - Add node: **Animation** → rename appropriately
   - Set animation from `cipher_casting_library/*`
   - Connect `AbilitySelector` → Animation node

7. **For physics abilities** (Jump, DashLeft, DashRight):
   - Add node: **StateMachine** → rename to match
   - Connect `AbilitySelector` → StateMachine

### Step 5: Build Sub-StateMachines (Jump, DashLeft, DashRight)
For **each** physics ability (Jump, DashLeft, DashRight):

1. Double-click to enter the StateMachine
2. Add Animation nodes (all from `basic_movement_library`):
   - `Action`:
     - Jump → `basic_movement_library/jumping`
     - DashLeft → `basic_movement_library/dashing left`
     - DashRight → `basic_movement_library/dashing right`
   - `Fall` → `basic_movement_library/falling`
   - `Land` → `basic_movement_library/landing`
3. Set `Action` as **Start Node**
4. Draw transitions:

| From | To | Switch Mode | Advance Mode |
|------|----|-------------|--------------|
| Action | Fall | Immediate | Enabled |
| Fall | Land | Immediate | Enabled |
| Land | End | AtEnd | Auto |

### Step 6: Configure Fall Animation Loop
1. In `AnimationPlayer`, find the falling animation
2. Select it, click the loop icon (🔁) in timeline toolbar
3. Set Wrap Mode = **Loop**

### Step 7: Add Call Method Tracks
In `AnimationPlayer`, for each animation:

**A) Jump animation @ 70%:**
1. Select animation, click **Add Track** → **Call Method**
2. Set track target: `../PlayerAnimator`
3. Right-click at 70% → **Insert Key**
4. Set method: `_on_anim_event_jump_launch`

**B) DashLeft/DashRight animations @ 20%:**
- Target: `../PlayerAnimator`
- Method: `_on_anim_event_dash_impulse`

**C) Landing animation @ last frame:**
- Target: `../PlayerAnimator`
- Method: `_on_anim_event_landing_done`

**D) Spell animations @ cast point (40-60%):**
- Target: `../PlayerAnimator`
- Method: `_on_anim_event_spell_effect`

**E) Death animation @ last frame:**
- Target: `../PlayerAnimator`
- Method: `_on_anim_event_death_done`

### Animation Library Reference

**Required animations per library:**

| Library | Animations Needed |
|---------|-------------------|
| basic_movement_library | idle, walking, running, walking back, running back, walking left, walking right, turning left, turning right, jumping, falling, landing, dashing left, dashing right, death |
| cipher_movement_library | idle, walking, running, walking back, running back, walking left, walking right, turning left, turning right (combat stance variants) |
| cipher_casting_library | shielding, smashing ground, swiping horizontal, swiping up, throwing forward, throwing up |

**FBX sources in assets/animations/:**
- `Player/` - Dash Left, Dash Right, Jump, Fall, Land
- `Magic Locomotion Pack/` - Walking, Running, Turning, Idle
- `Magic Spell Pack/` - Magic attacks
- `Pro Magic Pack/` - Additional combat animations

### Verification Checklist
After setup, verify:
- [ ] PlayerAnimator script attached and active
- [ ] AnimationPlayer active = OFF
- [ ] Root StateMachine has Locomotion (start), Cipher Casting, Death
- [ ] Locomotion has Stance transition with 2 BlendSpace2D inputs
- [ ] Each BlendSpace2D has nested BlendSpace1D at (0,0)
- [ ] Cipher Casting has AbilitySelector with 8 inputs
- [ ] Jump/DashLeft/DashRight are sub-StateMachines with Action→Fall→Land
- [ ] Fall animation loops
- [ ] Call Method Tracks added to key animations
- [ ] SpellManager registered as autoload
