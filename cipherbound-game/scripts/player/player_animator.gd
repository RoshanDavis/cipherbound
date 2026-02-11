extends AnimationTree
class_name PlayerAnimator
## Animation controller that extends AnimationTree directly.
## Drives a StateMachine + BlendSpace2D for locomotion blending and action states.
##
## Attach this script directly to the AnimationTree node under PlayerModel,
## then rename that node to "PlayerAnimator".
## Delete the old empty PlayerAnimator Node if it still exists.
##
## ============================================================================
## MANUAL SETUP GUIDE — Godot Editor Configuration
## ============================================================================
##
## STEP 0: Attach This Script & Rename the Node
## ---------------------------------------------
## 1. Select the "AnimationTree" node under PlayerModel.
## 2. Drag this script onto it (or Inspector → Script → Load).
## 3. Rename the node from "AnimationTree" to "PlayerAnimator".
## 4. Delete the old empty "PlayerAnimator" Node if it still exists.
## 5. Your tree should now look like:
##      PlayerModel (Node3D)
##      ├── AnimationPlayer       (active = OFF)
##      └── PlayerAnimator (AnimationTree) — this script
##
## STEP 1: Configure the AnimationTree Properties
## -----------------------------------------------
## 1. In the Inspector on "PlayerAnimator" (this node):
##    • Set "Anim Player" → "../AnimationPlayer".
##    • Set "Active" → ON.
##    • Set Process Mode → "Inherit".
## 2. On the "AnimationPlayer" node, set "Active" → OFF
##    (the tree drives it now — avoids conflicts).
##
## STEP 2: Build the StateMachine
## ------------------------------
## 1. Double-click the PlayerAnimator node to open the AnimationTree editor.
## 2. The root is already an AnimationNodeStateMachine. Inside it, add:
##
##    a) Right-click → "Add BlendSpace2D" → rename to "Locomotion".
##    b) Right-click → "Add Animation" → rename to "Jump",
##       set animation = "basic_movement_library/jumping".
##    c) Right-click → "Add Animation" → rename to "Fall",
##       set animation = "basic_movement_library/falling".
##    d) Right-click → "Add Animation" → rename to "Land",
##       set animation = "basic_movement_library/landing".
##    e) Right-click → "Add Animation" → rename to "Cast",
##       set animation = "basic_movement_library/casting".
##    f) Right-click → "Add Animation" → rename to "Death",
##       set animation = "basic_movement_library/death".
## 3. Right-click "Locomotion" → "Set as Start Node" (green arrow).
##
## STEP 3: Configure BlendSpace2D ("Locomotion")
## ----------------------------------------------
## 1. Double-click the "Locomotion" BlendSpace2D to open it.
## 2. Set axis ranges:  X Min = -1, X Max = 1  |  Y Min = -1, Y Max = 1
## 3. Set X Label = "Strafe", Y Label = "Forward".
## 4. Set Blend Mode = "Interpolated" (default).
## 5. Add points (click in the grid, pick the animation, then type exact coords):
##
##      Position (X, Y)  │  Animation
##     ──────────────────┼──────────────────────────────
##      ( 0.0,  0.0)     │  basic_movement_library/idle
##      ( 0.0,  0.5)     │  basic_movement_library/walking
##      ( 0.0, -0.5)     │  basic_movement_library/walking back
##      ( 0.0,  1.0)     │  basic_movement_library/running
##      ( 0.0, -1.0)     │  basic_movement_library/running back
##      (-1.0,  0.0)     │  basic_movement_library/walking left
##      ( 1.0,  0.0)     │  basic_movement_library/walking right
##
## 6. Click "Back" (top-left) to return to the StateMachine view.
##
## STEP 4: Configure the "Fall" Animation to Loop
## ------------------------------------------------
## 1. In the AnimationPlayer, open "basic_movement_library/falling".
## 2. Click the loop icon (🔁) in the animation timeline toolbar
##    so it is set to "Loop" (wrap mode). This replaces the old
##    _loop_falling() coroutine.
##
## STEP 5: Add Transitions
## -----------------------
## In the StateMachine editor, draw connections:
##
##   From         →  To          │ Switch Mode │ Notes
##  ─────────────────────────────┼─────────────┼──────────────────────────
##   Locomotion   →  Jump        │ Immediate   │ (script calls travel)
##   Locomotion   →  Cast        │ Immediate   │ (script calls travel)
##   Locomotion   →  Death       │ Immediate   │ (script calls travel)
##   Jump         →  Fall        │ AtEnd       │ Auto-advances when jump anim ends
##   Jump         →  Land        │ Immediate   │ (early landing via travel)
##   Fall         →  Land        │ Immediate   │ (script calls travel)
##   Land         →  Locomotion  │ AtEnd       │ Auto-advances when land anim ends
##   Cast         →  Locomotion  │ AtEnd       │ Auto-advances when cast anim ends
## To set these: click a transition arrow → Inspector:
##   • "Switch Mode" = Immediate or AtEnd as listed above.
##   • "Advance Mode" = "Auto" for AtEnd transitions (they fire automatically).
##   • "Advance Mode" = "Enabled" for Immediate transitions (script drives them).
##   • "Xfade Time" = 0.15 (crossfade duration).
##
## STEP 6: Add Call Method Tracks (Event Callbacks)
## -------------------------------------------------
## These replace the old await/coroutine timing with editor-keyframed events.
##
## For each animation below, open it in the AnimationPlayer editor:
##
## A) "basic_movement_library/jumping":
##    1. Click "Add Track" → "Call Method Track".
##    2. Target node path: "../PlayerAnimator" (the node this script is on).
##    3. Add a keyframe at 70% of the animation length
##       (e.g., if anim is 1.0s, place key at 0.7s).
##    4. Set the method to: _on_anim_event_jump_launch
##       (no arguments needed).
##
## B) "basic_movement_library/landing":
##    1. Add a "Call Method Track" → target "../PlayerAnimator".
##    2. Add a keyframe at the LAST FRAME (animation length - 0.01).
##    3. Method: _on_anim_event_landing_done
##
## C) "basic_movement_library/casting":
##    1. Add a "Call Method Track" → target "../PlayerAnimator".
##    2. Keyframe at the LAST FRAME.
##    3. Method: _on_anim_event_cast_done
##
## D) "basic_movement_library/death":
##    1. Add a "Call Method Track" → target "../PlayerAnimator".
##    2. Keyframe at the LAST FRAME.
##    3. Method: _on_anim_event_death_done
##
## ============================================================================
## END OF SETUP GUIDE
## ============================================================================

enum State { LOCOMOTION, JUMPING, FALLING, LANDING, CASTING, DEATH }

# --- CONFIGURATION ---
@export_group("Blend Parameters")
@export var locomotion_param := "parameters/Locomotion/blend_position" ## BlendSpace2D parameter path
@export_range(1.0, 30.0, 0.5) var blend_smoothing := 8.0 ## How fast blend position catches up (higher = snappier)

# --- REFERENCES ---
var _playback: AnimationNodeStateMachinePlayback

# --- STATE ---
var _state := State.LOCOMOTION
var _movement_input := Vector2.ZERO
var _blend_position := Vector2.ZERO ## Smoothed blend position (lerped toward _movement_input)
var _travel_pending := false ## True after travel() called, prevents sync from overriding state
var _travel_pending_since := 0 ## Timestamp (msec) when _travel_pending was set
const TRAVEL_TIMEOUT_MS := 500 ## Max time to wait for travel() to take effect

# --- SIGNALS ---
signal state_changed(new_state: State)
signal jump_launch() ## Emitted when velocity should be applied (via Call Method Track)
signal landing_finished() ## Emitted when landing animation completes
signal death_finished() ## Emitted when death animation completes
func _ready() -> void:
	# Ensure the tree is active
	active = true
	
	# Get the StateMachine playback object
	_playback = self["parameters/playback"] as AnimationNodeStateMachinePlayback
	if not _playback:
		push_error("PlayerAnimator: Could not get StateMachine playback. Is tree_root an AnimationNodeStateMachine?")
		return
	
	print("PlayerAnimator: Initialized (AnimationTree script)")

func _process(delta: float) -> void:
	if not _playback:
		return
	
	# Smoothly interpolate blend position to avoid jitter from raw vision input
	if _state == State.LOCOMOTION:
		_blend_position = _blend_position.lerp(_movement_input, clampf(blend_smoothing * delta, 0.0, 1.0))
		# Snap to zero when very close (prevents micro-drift keeping walk alive)
		if _blend_position.length() < 0.01:
			_blend_position = Vector2.ZERO
		self[locomotion_param] = _blend_position
	
	# Track state based on what the StateMachine is actually playing
	_sync_state_from_playback()

# ============================================================================
# STATE SYNC — keep _state in sync with the StateMachine
# ============================================================================

func _sync_state_from_playback() -> void:
	"""Sync internal state when the StateMachine auto-advances (AtEnd transitions)."""
	if not _playback:
		return
	
	var current_node := _playback.get_current_node()
	
	# Guard against travel() race condition:
	# After calling travel(), the playback node doesn't switch instantly.
	# If we sync before it switches, we'd wrongly reset state to LOCOMOTION.
	# Wait until the node has actually changed before resuming sync.
	if _travel_pending:
		if current_node != "Locomotion":
			_travel_pending = false
		elif Time.get_ticks_msec() - _travel_pending_since < TRAVEL_TIMEOUT_MS:
			return  # Still waiting for travel() to take effect
		else:
			# Travel timed out — likely no transition exists; recover gracefully
			push_warning("PlayerAnimator: travel() timed out — check StateMachine transitions.")
			_travel_pending = false
			_set_state(State.LOCOMOTION)
			return
	
	match current_node:
		"Locomotion":
			if _state != State.LOCOMOTION:
				_set_state(State.LOCOMOTION)
		"Jump":
			if _state != State.JUMPING:
				_set_state(State.JUMPING)
		"Fall":
			if _state != State.FALLING:
				_set_state(State.FALLING)
		"Land":
			if _state != State.LANDING:
				_set_state(State.LANDING)
		"Cast":
			if _state != State.CASTING:
				_set_state(State.CASTING)
		"Death":
			if _state != State.DEATH:
				_set_state(State.DEATH)
# ============================================================================
# HELPERS
# ============================================================================

func _begin_travel(node_name: StringName) -> void:
	"""Travel to a StateMachine node with pending-travel guard."""
	_travel_pending = true
	_travel_pending_since = Time.get_ticks_msec()
	_playback.travel(node_name)

# ============================================================================
# JUMP SEQUENCE
# ============================================================================

func play_jump() -> void:
	"""Start the jump animation. jump_launch is emitted via Call Method Track."""
	if _state != State.LOCOMOTION:
		return
	
	_set_state(State.JUMPING)
	_begin_travel("Jump")
	print("PlayerAnimator: JUMPING (wind-up)")

func set_falling() -> void:
	"""Transition to falling. Called by controller when velocity.y < 0."""
	if _state == State.FALLING:
		return
	if _state != State.JUMPING:
		return
	
	_set_state(State.FALLING)
	_begin_travel("Fall")
	print("PlayerAnimator: FALLING")

func play_landing() -> void:
	"""Transition to landing. landing_finished is emitted via Call Method Track."""
	if _state == State.LANDING:
		return
	if _state != State.FALLING and _state != State.JUMPING:
		return
	
	_set_state(State.LANDING)
	_begin_travel("Land")
	print("PlayerAnimator: LANDING")

# ============================================================================
# SPELL CASTING
# ============================================================================

func play_spell_animation(_cipher_name: String) -> void:
	"""Play casting animation. Return to locomotion is handled by AtEnd transition."""
	if _state == State.CASTING:
		return
	if _state != State.LOCOMOTION:
		return
	
	_set_state(State.CASTING)
	_begin_travel("Cast")
	print("PlayerAnimator: CASTING (", _cipher_name, ")")

# ============================================================================
# DEATH
# ============================================================================

func play_death() -> void:
	"""Play death animation. death_finished is emitted via Call Method Track."""
	if _state == State.DEATH:
		return
	
	_set_state(State.DEATH)
	_begin_travel("Death")
	print("PlayerAnimator: DEATH")

func is_dead() -> bool:
	"""Check if currently in death state."""
	return _state == State.DEATH

func reset_from_death() -> void:
	"""Reset from death state (for respawn)."""
	if _state != State.DEATH:
		return
	
	_set_state(State.LOCOMOTION)
	_travel_pending = false
	_playback.travel("Locomotion")
	self[locomotion_param] = Vector2.ZERO
	print("PlayerAnimator: Respawned → LOCOMOTION")

# ============================================================================
# CALL METHOD TRACK CALLBACKS
# ============================================================================
# These functions are called by keyframes placed on Call Method Tracks
# in the AnimationPlayer. See the setup guide at the top of this file.

func _on_anim_event_jump_launch() -> void:
	"""Called by Call Method Track on jumping animation at ~70%.
	Emits jump_launch so the controller applies upward velocity."""
	print("PlayerAnimator: LAUNCH! (Call Method Track)")
	jump_launch.emit()

func _on_anim_event_landing_done() -> void:
	"""Called by Call Method Track on landing animation at final frame.
	Emits landing_finished, then StateMachine auto-transitions to Locomotion."""
	print("PlayerAnimator: Landing complete → LOCOMOTION")
	landing_finished.emit()

func _on_anim_event_cast_done() -> void:
	"""Called by Call Method Track on casting animation at final frame.
	StateMachine auto-transitions to Locomotion via AtEnd."""
	print("PlayerAnimator: Cast complete → LOCOMOTION")

func _on_anim_event_death_done() -> void:
	"""Called by Call Method Track on death animation at final frame."""
	print("PlayerAnimator: Death animation complete")
	death_finished.emit()

# ============================================================================
# PUBLIC API
# ============================================================================

func set_movement_input(input: Vector2) -> void:
	"""Update movement input vector (x=strafe, y=forward/back).
	Directly drives the BlendSpace2D blend position."""
	_movement_input = input

func is_in_air() -> bool:
	"""Check if currently in an airborne state."""
	return _state in [State.JUMPING, State.FALLING, State.LANDING]

func get_state() -> State:
	"""Get current animation state."""
	return _state

func force_idle() -> void:
	"""Force return to idle (use for recovery from bad states)."""
	_set_state(State.LOCOMOTION)
	_travel_pending = false
	if _playback:
		_playback.travel("Locomotion")
	self[locomotion_param] = Vector2.ZERO

# ============================================================================
# INTERNAL
# ============================================================================

func _set_state(new_state: State) -> void:
	"""Update state and emit signal."""
	if _state != new_state:
		_state = new_state
		state_changed.emit(new_state)
