# Current Setup Instructions

## Quick Start

### 1. Run the Vision Server
```powershell
cd vision/src
py main.py
```
Keep this terminal running - it sends tracking data to Godot via UDP.

### 2. Open Godot Project
Open `cipherbound-game/project.godot` in Godot 4.5.

---

## New Systems Setup

### Autoloads (Already Configured)
The following autoloads are pre-registered in `project.godot`:
- ✅ **GameManager** - Player stats, waves, game state
- ✅ **AudioManager** - Sound effects and music
- ✅ **SceneManager** - Scene transitions
- ✅ **SpellManager** - Spell effects dispatch

To verify: Project → Project Settings → Autoload

### Add the Game HUD to Your Scene
1. Open `scenes/game.tscn`
2. Instance the HUD: Right-click root → **Instance Child Scene**
3. Select `scenes/ui/game_hud.tscn`
4. The HUD auto-connects to GameManager signals

### Add the Enemy Spawner (Optional)
1. In `scenes/game.tscn`, instance `scenes/enemies/enemy_spawner.tscn`
2. Position it at world origin or wherever you want enemies to spawn
3. Configure in Inspector:
   - `Auto Start` = true (to start waves automatically)
   - `Spawn Around Player` = true (spawn relative to player)
   - `Spawn Radius` = 15-20 (distance from player)

### Add Player to "player" Group
For enemies to detect the player:
1. Select the Player node in the scene tree
2. Go to Node → Groups tab
3. Add group: `player`

---

## Audio Setup (Optional)

### Add Sound Effects
1. Create folder: `assets/audio/sfx/`
2. Add .wav or .ogg files
3. Register in `scripts/managers/audio_manager.gd`:
```gdscript
func _ready() -> void:
    # Add your sounds here
    sfx_library["spell_cast"] = preload("res://assets/audio/sfx/spell_cast.wav")
    sfx_library["enemy_hit"] = preload("res://assets/audio/sfx/enemy_hit.wav")
```

### Add Music
1. Create folder: `assets/audio/music/`
2. Add .ogg files (better for music)
3. Register in audio_manager.gd:
```gdscript
music_library["battle"] = preload("res://assets/audio/music/battle.ogg")
```

---

## Testing the Systems

### Test Health/Mana (in any script or console)
```gdscript
# Take damage
GameManager.take_damage(20)

# Use mana
GameManager.use_mana(15)

# Heal
GameManager.heal(10)
```

### Test Wave Spawning
```gdscript
# Start waves manually
$EnemySpawner.start_waves()

# Or spawn a single enemy
$EnemySpawner.spawn_enemy_at("slime", Vector3(10, 0, 5))
```

### Test Scene Transitions
```gdscript
SceneManager.change_scene("game")
SceneManager.reload_current_scene()
```

---

## AnimationTree Setup (If Not Done)

The AnimationTree needs to be built in Godot's editor. Follow section **8. AnimationTree Editor Setup Guide** in CONTEXT.md for full instructions.

**Quick checklist:**
- [ ] PlayerAnimator has script attached
- [ ] Root StateMachine with: Locomotion, Cipher Casting, Death
- [ ] Locomotion has Stance transition (Basic/Cipher BlendSpace2D)
- [ ] Each BlendSpace2D has nested BlendSpace1D at (0,0) for idle turning
- [ ] Cipher Casting has AbilitySelector with 8 inputs
- [ ] Jump/Dash are sub-StateMachines: Action → Fall → Land
- [ ] Call Method Tracks added to animations for events

---

## File Locations Reference

| System | Script | Scene |
|--------|--------|-------|
| Game Manager | `scripts/managers/game_manager.gd` | (autoload) |
| Audio Manager | `scripts/managers/audio_manager.gd` | (autoload) |
| Scene Manager | `scripts/managers/scene_manager.gd` | (autoload) |
| Spell Manager | `scripts/spells/spell_manager.gd` | (autoload) |
| Game HUD | `scripts/ui/game_hud.gd` | `scenes/ui/game_hud.tscn` |
| Base Enemy | `scripts/enemies/base_enemy.gd` | - |
| Slime Enemy | (uses base_enemy.gd) | `scenes/enemies/slime.tscn` |
| Enemy Spawner | `scripts/enemies/enemy_spawner.gd` | `scenes/enemies/enemy_spawner.tscn` |

**Note:** GameHUD is the consolidated UI that includes:
- Health/mana bars
- Wave and score display
- Cipher stroke drawing (formerly in cipher_hud.gd)
- Status messages for hand tracking
- Spell cast feedback

---

## Particle Effects

Particle scenes are in `scenes/particles/`:
- `air_burst.tscn` - Jump effect
- `dash_trail.tscn` - Dash movement
- `ground_slam.tscn` - Smash ground impact
- `ground_wave.tscn` - Expanding ring
- `shield_burst.tscn` - Shield activation
- `shield_sustain.tscn` - Shield loop
- `projectile_core.tscn` - Lightning/throw center
- `projectile_trail.tscn` - Projectile trail
- `slash.tscn` - Swipe effects

These are automatically spawned by SpellManager when casting spells.

---

## Troubleshooting

### HUD not updating
- Ensure GameManager autoload is enabled
- Check that GameHUD is instanced in the scene

### Enemies not chasing
- Add player to `player` group
- Check enemy's `detection_range` in Inspector

### No sound playing
- Verify audio files are imported
- Check `sfx_library` has entries
- Ensure AudioManager autoload is enabled

### Vision server not connecting
- Confirm server is running (`py main.py`)
- Check port 5005 is not blocked
- Both must be on localhost
