# Current Setup Instructions

## Quick Start

### 1. Run the Vision Server
```powershell
cd vision/src
py main.py
```
Keep this terminal running — it sends tracking data to Godot via UDP.

### 2. Open Godot Project
Open `cipherbound-game/project.godot` in Godot 4.5.

### 3. Run the Game
Press F5 or the Play button. The **Main Menu** will appear. Click **Start Game** to begin.

---

## How It Works

1. **Vision Server** tracks your hands via webcam
2. **Draw ciphers** by opening your left hand (activate), then pointing with your right hand (draw)
3. Each recognized cipher casts a **spell** that spawns glowing particles and damages enemies
4. Enemies spawn in waves and chase you — survive as long as you can!

---

## Spell List

| Cipher | Spell | Effect | Damage |
|--------|-------|--------|--------|
| Air Jump | ^ (Up Arrow) | AOE at feet | Jump & 15 dmg |
| Dash Right | > (Right Arrow) | AOE at feet | Dash & 10 dmg |
| Dash Left | < (Left Arrow) | AOE at feet | Dash & 10 dmg |
| Ground Smash | v (Down Arrow) | AOE in front | 25 |
| AOE Attack | ○ or □ (Circle/Square) | Continuous AOE | 5/tick |
| Fireball | Z (Zigzag Bolt) | Forward-moving | 20 |
| Horizontal Strike | ― (Horizontal line) | AOE in front | 12 |
| Vertical Strike | \| (Vertical line) | AOE in front | 12 |

---

## Game Flow

- **Main Menu** → Click "Start Game"
- **Waves** spawn enemies (slimes) that chase and damage you
- **Cast spells** to kill enemies and earn points
- **Game Over** → Shows score + restart button
- Health bar (top-left), wave/score (top-right), cipher drawing (full screen)

---

## Things You May Need to Do in Godot

### EnemySpawner
If enemies aren't spawning automatically:
1. Select `EnemySpawner` in `scenes/game.tscn`
2. In Inspector, set `Auto Start = true`

### AnimationTree (Optional)
The animation system scripts are in place but the AnimationTree needs to be built in Godot's editor.
See section **8. AnimationTree Editor Setup Guide** in CONTEXT.md for full instructions.
Without it, character will use default poses but all gameplay works.

### Audio (Optional)
No audio files are included yet. Add .wav/.ogg files to `assets/audio/` and register them in `audio_manager.gd`.

---

## Autoloads (Already Configured)
- ✅ **GameManager** — Health, waves, score, game state
- ✅ **AudioManager** — Sound effects and music
- ✅ **SceneManager** — Scene transitions
- ✅ **SpellManager** — Spell effects dispatch

---

## Troubleshooting

### Enemies not chasing
- Verify `player_controller.gd` has `add_to_group("player")` in `_ready()`
- Check enemy `detection_range` in Inspector (default: 10m)

### No particles visible
- Ensure all particle .tscn files have `draw_pass_1` assigned
- Check that `SpellManager` autoload is enabled

### Vision server not connecting
- Confirm server is running (`py main.py`)
- Check port 5005 is not blocked
- Both must be on localhost
