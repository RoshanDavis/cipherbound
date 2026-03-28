extends AnimationTree
class_name PlayerAnimator
## Animation controller for the new AnimationTree structure.
## Drives a StateMachine with Locomotion (stance-switching BlendTree) and Cipher Casting (ability selector).
##
## ============================================================================
## ANIMATION TREE STRUCTURE OVERVIEW
## ============================================================================
##
## Root: AnimationNodeStateMachine
## ├── Locomotion (BlendTree) ─ Start Node
## │   └── Stance (Transition)
## │       ├── [0] Basic Movement (BlendSpace2D)
## │       │   └── At (0,0): Idle Turn (BlendSpace1D) → TurnLeft/Idle/TurnRight
## │       └── [1] Cipher Movement (BlendSpace2D)
## │           └── At (0,0): Idle Turn (BlendSpace1D) → TurnLeft/Idle/TurnRight
## ├── Cipher Casting (BlendTree)
## │   └── AbilitySelector (Transition)
## │       ├── [0] Jump (StateMachine: Start→Jump→Fall→Land→End)
## │       ├── [1] SmashGround (Animation: smashing ground)
## │       ├── [2] DashLeft (StateMachine: Start→Dash→Fall→Land→End)
## │       ├── [3] DashRight (StateMachine: Start→Dash→Fall→Land→End)
## │       ├── [4] ThrowForward (Animation: throwing forward)
## │       ├── [5] Shield (Animation: shielding)
## │       ├── [6] SwipeHorizontal (Animation: swiping horizontal)
## │       └── [7] SwipeUp (Animation: swiping up)
## └── Death (Animation)
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
## STEP 2: Build the Root StateMachine
## ------------------------------------
## 1. Double-click the PlayerAnimator node to open the AnimationTree editor.
## 2. The root is already an AnimationNodeStateMachine. Inside it, add:
##
##    a) Right-click → "Add BlendTree" → rename to "Locomotion".
##    b) Right-click → "Add BlendTree" → rename to "Cipher Casting".
##    c) Right-click → "Add Animation" → rename to "Death",
##       set animation = "basic_movement_library/death" (or Pro Magic Pack death).
##
## 3. Right-click "Locomotion" → "Set as Start Node" (green arrow).
## 4. Draw transitions:
##    - Locomotion → Cipher Casting (Immediate, Advance Mode = Enabled)
##    - Cipher Casting → Locomotion (AtEnd, Advance Mode = Auto)
##    - Locomotion → Death (Immediate, Advance Mode = Enabled)
##
## STEP 3: Build the Locomotion BlendTree
## ---------------------------------------
## 1. Double-click "Locomotion" to open it.
## 2. Add a "Transition" node → rename to "Stance".
## 3. In the Transition's Inspector:
##    - Set "Input Count" = 2
##    - Rename inputs: [0] = "Basic Movement", [1] = "Cipher Movement"
##    - Set "Xfade Time" = 0.2
## 4. Connect Output → Stance.
##
## 5. For EACH stance (Basic Movement, Cipher Movement):
##    a) Add a "BlendSpace2D" → rename appropriately.
##    b) Connect Stance → BlendSpace2D.
##    c) Configure BlendSpace2D:
##       - X Min = -1, X Max = 1, Y Min = -1, Y Max = 1
##       - X Label = "Strafe", Y Label = "Forward"
##       - Blend Mode = "Interpolated"
##    d) Add animation points:
##
##       Position (X, Y)  │  Animation (Basic Movement)
##      ──────────────────┼──────────────────────────────
##       ( 0.0,  0.0)     │  (See Step 3f for nested BlendSpace1D)
##       ( 0.0,  0.5)     │  basic_movement_library/walking
##       ( 0.0, -0.5)     │  basic_movement_library/walking back
##       ( 0.0,  1.0)     │  basic_movement_library/running
##       ( 0.0, -1.0)     │  basic_movement_library/running back
##       (-1.0,  0.0)     │  basic_movement_library/walking left
##       ( 1.0,  0.0)     │  basic_movement_library/walking right
##
##    e) For Cipher Movement, use cipher_movement_library/* equivalents.
##
##    f) NESTED IDLE TURN (at position 0,0):
##       - Instead of adding an animation at (0,0), add a "BlendSpace1D".
##       - Configure BlendSpace1D:
##         - Min = -1, Max = 1, Label = "Turn"
##       - Add 3 points:
##         - (-1.0) = basic_movement_library/turning left
##         - ( 0.0) = basic_movement_library/idle
##         - ( 1.0) = basic_movement_library/turning right
##
## STEP 4: Build the Cipher Casting BlendTree
## -------------------------------------------
## 1. Double-click "Cipher Casting" to open it.
## 2. Add a "Transition" node → rename to "AbilitySelector".
## 3. In the Transition's Inspector:
##    - Set "Input Count" = 8
##    - Rename inputs: [0]=Jump, [1]=SmashGround, [2]=DashLeft, [3]=DashRight,
##                     [4]=ThrowForward, [5]=Shield, [6]=SwipeHorizontal, [7]=SwipeUp
##    - Set "Xfade Time" = 0.1
## 4. Connect Output → AbilitySelector.
##
## 5. For simple animations (indices 1, 4, 5, 6, 7):
##    - Add "Animation" nodes with appropriate animations from cipher_casting_library.
##    - Connect AbilitySelector → Animation node.
##
## 6. For physics-dependent abilities (Jump, DashLeft, DashRight):
##    - Add "StateMachine" nodes.
##    - Connect AbilitySelector → StateMachine.
##    - Configure each StateMachine (see Step 5).
##
## STEP 5: Build Sub-State Machines (Jump, DashLeft, DashRight)
## -------------------------------------------------------------
## For each physics-dependent ability StateMachine:
##
## 1. Double-click to enter the StateMachine.
## 2. Add Animation nodes (all from basic_movement_library):
##    - "Action":
##        Jump      → basic_movement_library/jumping
##        DashLeft  → basic_movement_library/dashing left
##        DashRight → basic_movement_library/dashing right
##    - "Fall" → basic_movement_library/falling (set to LOOP)
##    - "Land" → basic_movement_library/landing
## 3. Set "Action" as Start Node.
## 4. Draw transitions:
##    - Action → Fall (Immediate, script-driven when velocity.y < 0)
##    - Fall → Land (Immediate, script-driven when approaching ground)
##    - Land → End (AtEnd, auto-advances)
##
## STEP 6: Set Fall Animation to Loop
## -----------------------------------
## 1. In AnimationPlayer, find the falling animation.
## 2. Click the loop icon (🔁) to set Wrap Mode = Loop.
##
## STEP 7: Add Call Method Tracks
## -------------------------------
## In AnimationPlayer, add Call Method Tracks to these animations:
##
## A) Jump animation (basic_movement_library/jumping) @ 70%:
##    - Target: "../PlayerAnimator"
##    - Method: _on_anim_event_jump_launch
##
## B) DashLeft/DashRight animations @ 20%:
##    - Target: "../PlayerAnimator"
##    - Method: _on_anim_event_dash_impulse
##
## C) Landing animation @ last frame:
##    - Target: "../PlayerAnimator"
##    - Method: _on_anim_event_landing_done
##
## D) Spell animations @ cast point (40-60%):
##    - Target: "../PlayerAnimator"
##    - Method: _on_anim_event_spell_effect
##
## E) Death animation @ last frame:
##    - Target: "../PlayerAnimator"
##    - Method: _on_anim_event_death_done
##
## ============================================================================
## END OF SETUP GUIDE
## ============================================================================

# --- ENUMS ---
enum State { LOCOMOTION, CIPHER_CASTING, DEATH }
enum Stance { BASIC, CIPHER }
enum Ability { JUMP = 0, SMASH_GROUND = 1, DASH_LEFT = 2, DASH_RIGHT = 3, 
			   THROW_FORWARD = 4, SHIELD = 5, SWIPE_HORIZONTAL = 6, SWIPE_UP = 7 }

# --- CONFIGURATION ---
@export_group("Blend Parameters")
@export_range(1.0, 30.0, 0.5) var blend_smoothing := 8.0 ## How fast blend position catches up
@export_range(1.0, 20.0, 0.5) var turn_smoothing := 12.0 ## How fast idle turn responds
@export_range(0.05, 0.5, 0.01) var idle_threshold := 0.1 ## Movement below this triggers idle turn

@export_group("Gesture to Ability Mapping")
@export var gesture_ability_map: Dictionary = {
	"air_jump": Ability.JUMP,
	"ground_smash": Ability.SMASH_GROUND,
	"dash_left": Ability.DASH_LEFT,
	"dash_right": Ability.DASH_RIGHT,
	"fireball": Ability.THROW_FORWARD,
	"aoe_attack_sq": Ability.SHIELD,
	"aoe_attack": Ability.SHIELD,
	"horizontal_strike": Ability.SWIPE_HORIZONTAL,
	"vertical_strike": Ability.SWIPE_UP
}

# --- PARAMETER PATHS ---
## Root StateMachine
const PARAM_ROOT_PLAYBACK := "parameters/playback"

## Locomotion BlendTree
const PARAM_STANCE_TRANSITION := "parameters/Locomotion/Stance/transition_request"
const PARAM_BASIC_BLEND := "parameters/Locomotion/Basic Movement/blend_position"
const PARAM_CIPHER_BLEND := "parameters/Locomotion/Cipher Movement/blend_position"
const PARAM_BASIC_IDLE_TURN := "parameters/Locomotion/Basic Movement/0/blend_position"
const PARAM_CIPHER_IDLE_TURN := "parameters/Locomotion/Cipher Movement/1/blend_position"

## Cipher Casting BlendTree
const PARAM_ABILITY_TRANSITION := "parameters/Cipher Casting/Ability Selector/transition_request"

## Sub-StateMachine playbacks for physics abilities
const PARAM_JUMP_PLAYBACK := "parameters/Cipher Casting/Jump/playback"
const PARAM_DASH_LEFT_PLAYBACK := "parameters/Cipher Casting/DashLeft/playback"
const PARAM_DASH_RIGHT_PLAYBACK := "parameters/Cipher Casting/DashRight/playback"

# Ability names matching Transition input names in your tree
const ABILITY_NAMES: Array[String] = [
	"Jump", "SmashGround", "DashLeft", "DashRight",
	"ThrowForward", "Shield", "SwipeHorizontal", "SwipeUp"
]

# --- REFERENCES ---
var _root_playback: AnimationNodeStateMachinePlayback

# --- STATE ---
var _state := State.LOCOMOTION
var _stance := Stance.BASIC
var _current_ability := -1 ## Currently active ability index (-1 = none)

var _movement_input := Vector2.ZERO
var _blend_position := Vector2.ZERO ## Smoothed blend position
var _turn_input := 0.0 ## Raw turn input (-1 to 1)
var _turn_blend := 0.0 ## Smoothed turn blend

var _travel_pending := false
var _travel_pending_since := 0
const TRAVEL_TIMEOUT_MS := 500

var _is_in_sub_state_machine := false ## True when in Jump/Dash sub-SM
var _sub_state := "" ## Current state within sub-SM (Jump/Dash, Fall, Land)
var _active_sub_playback: AnimationNodeStateMachinePlayback = null ## Playback for current sub-SM
var _sub_state_entered_time := 0.0 ## Time when current sub-state was entered
var _tree_valid := false ## True when AnimationTree structure is properly configured

# --- SIGNALS ---
signal state_changed(new_state: State)
signal stance_changed(new_stance: Stance)
signal ability_started(ability: int)
signal ability_ended(ability: int)

signal jump_launch() ## Emitted when jump velocity should be applied
signal dash_impulse(direction: Vector3) ## Emitted when dash velocity should be applied
signal landing_finished() ## Emitted when landing animation completes
signal spell_effect(ability: int) ## Emitted when spell effect should spawn
signal death_finished() ## Emitted when death animation completes

func _ready() -> void:
	active = true
	
	_root_playback = self[PARAM_ROOT_PLAYBACK] as AnimationNodeStateMachinePlayback
	if not _root_playback:
		push_error("PlayerAnimator: Could not get root StateMachine playback.")
		return
	
	# Connect to animation_finished to detect when abilities complete
	animation_finished.connect(_on_animation_finished)
	
	# Validate tree structure
	_tree_valid = _validate_tree_structure()
	if not _tree_valid:
		push_warning("PlayerAnimator: AnimationTree structure incomplete. See setup guide in script comments.")
	
	print("PlayerAnimator: Initialized (tree_valid=", _tree_valid, ")")

func _validate_tree_structure() -> bool:
	"""Check if the AnimationTree has the expected structure."""
	# Check if key parameters exist by attempting to access them
	var required_params := [
		PARAM_STANCE_TRANSITION,
		PARAM_BASIC_BLEND,
		PARAM_CIPHER_BLEND,
	]
	
	for param in required_params:
		if not _has_parameter(param):
			push_warning("PlayerAnimator: Missing parameter '", param, "'")
			return false
	return true

func _has_parameter(param_path: String) -> bool:
	"""Check if a parameter path exists in the tree."""
	# AnimationTree uses _get override for parameter access
	var value = self[param_path]
	# blend_position returns Vector2, transition_request returns String
	# Both are non-null when the parameter exists
	return value != null

func _process(delta: float) -> void:
	if not _root_playback or not _tree_valid:
		return
	
	# Smooth blend position for locomotion
	if _state == State.LOCOMOTION:
		_blend_position = _blend_position.lerp(_movement_input, clampf(blend_smoothing * delta, 0.0, 1.0))
		if _blend_position.length() < 0.01:
			_blend_position = Vector2.ZERO
		
		# Smooth turn blend
		_turn_blend = lerpf(_turn_blend, _turn_input, clampf(turn_smoothing * delta, 0.0, 1.0))
		if absf(_turn_blend) < 0.01:
			_turn_blend = 0.0
		
		# Apply to current stance's blend parameters
		_apply_locomotion_blend()
	
	_sync_state_from_playback()

func _apply_locomotion_blend() -> void:
	"""Apply blend position and idle turn to the current stance's parameters."""
	match _stance:
		Stance.BASIC:
			self[PARAM_BASIC_BLEND] = _blend_position
			# Only apply turn when nearly stationary
			if _blend_position.length() < idle_threshold:
				self[PARAM_BASIC_IDLE_TURN] = _turn_blend
			else:
				self[PARAM_BASIC_IDLE_TURN] = 0.0
		Stance.CIPHER:
			self[PARAM_CIPHER_BLEND] = _blend_position
			if _blend_position.length() < idle_threshold:
				self[PARAM_CIPHER_IDLE_TURN] = _turn_blend
			else:
				self[PARAM_CIPHER_IDLE_TURN] = 0.0

# ============================================================================
# STATE SYNC
# ============================================================================

func _sync_state_from_playback() -> void:
	"""Sync internal state when the StateMachine auto-advances."""
	if not _root_playback:
		return
	
	var current_node := _root_playback.get_current_node()
	
	# Handle travel pending guard
	if _travel_pending:
		var expected_node := _get_expected_node_for_state(_state)
		if current_node == expected_node or current_node != "Locomotion":
			_travel_pending = false
		elif Time.get_ticks_msec() - _travel_pending_since >= TRAVEL_TIMEOUT_MS:
			push_warning("PlayerAnimator: travel() timed out")
			_travel_pending = false
			_set_state(State.LOCOMOTION)
			return
		else:
			return
	
	# Sync state from playback
	match current_node:
		"Locomotion":
			if _state != State.LOCOMOTION:
				_on_returned_to_locomotion()
		"Cipher Casting":
			if _state != State.CIPHER_CASTING:
				_set_state(State.CIPHER_CASTING)
		"Death":
			if _state != State.DEATH:
				_set_state(State.DEATH)

func _get_expected_node_for_state(state: State) -> String:
	match state:
		State.LOCOMOTION:
			return "Locomotion"
		State.CIPHER_CASTING:
			return "Cipher Casting"
		State.DEATH:
			return "Death"
	return "Locomotion"

func _on_returned_to_locomotion() -> void:
	"""Called when returning to Locomotion from another state."""
	if _current_ability >= 0:
		ability_ended.emit(_current_ability)
	_current_ability = -1
	_is_in_sub_state_machine = false
	_sub_state = ""
	_active_sub_playback = null
	_set_state(State.LOCOMOTION)

# ============================================================================
# HELPERS
# ============================================================================

func _begin_travel(node_name: StringName) -> void:
	"""Travel to a root StateMachine node with pending-travel guard."""
	_travel_pending = true
	_travel_pending_since = Time.get_ticks_msec()
	_root_playback.travel(node_name)

func _set_state(new_state: State) -> void:
	if _state != new_state:
		_state = new_state
		state_changed.emit(new_state)

# ============================================================================
# STANCE CONTROL
# ============================================================================

func set_stance(is_cipher: bool) -> void:
	"""Switch between Basic and Cipher movement stances."""
	if not _tree_valid:
		return
	
	var new_stance := Stance.CIPHER if is_cipher else Stance.BASIC
	if new_stance == _stance:
		return
	
	_stance = new_stance
	
	# Request transition to new stance
	var stance_name := "Cipher Movement" if is_cipher else "Basic Movement"
	self[PARAM_STANCE_TRANSITION] = stance_name
	
	stance_changed.emit(_stance)
	print("PlayerAnimator: Stance → ", stance_name)

func get_stance() -> Stance:
	return _stance

func is_cipher_stance() -> bool:
	return _stance == Stance.CIPHER

# ============================================================================
# MOVEMENT INPUT
# ============================================================================

func set_movement_input(input: Vector2) -> void:
	"""Update movement input vector (x=strafe, y=forward/back)."""
	_movement_input = input

func set_idle_turn(angular_velocity: float) -> void:
	"""Set the idle turn input (-1 = left, 0 = none, +1 = right).
	Only effective when movement input is near zero."""
	_turn_input = clampf(angular_velocity, -1.0, 1.0)

# ============================================================================
# ABILITY SYSTEM (Cipher Casting)
# ============================================================================

func play_ability(ability: int) -> void:
	"""Trigger an ability from the Cipher Casting state."""
	if not _tree_valid:
		return
	
	if ability < 0 or ability >= ABILITY_NAMES.size():
		push_warning("PlayerAnimator: Invalid ability index: ", ability)
		return
	
	if _state == State.DEATH:
		return
	
	_current_ability = ability
	_set_state(State.CIPHER_CASTING)
	
	# Travel to Cipher Casting state
	_begin_travel("Cipher Casting")
	
	# Request the specific ability
	var ability_name := ABILITY_NAMES[ability]
	self[PARAM_ABILITY_TRANSITION] = ability_name
	
	# Mark physics abilities and get sub-SM playback
	match ability:
		Ability.JUMP:
			_is_in_sub_state_machine = true
			_sub_state = "Jump"
			_sub_state_entered_time = Time.get_ticks_msec() / 1000.0
			# Defer getting playback until next frame (after transition completes)
			call_deferred("_get_sub_playback", PARAM_JUMP_PLAYBACK)
		Ability.DASH_LEFT:
			_is_in_sub_state_machine = true
			_sub_state = "Dash"
			_sub_state_entered_time = Time.get_ticks_msec() / 1000.0
			call_deferred("_get_sub_playback", PARAM_DASH_LEFT_PLAYBACK)
		Ability.DASH_RIGHT:
			_is_in_sub_state_machine = true
			_sub_state = "Dash"
			_sub_state_entered_time = Time.get_ticks_msec() / 1000.0
			call_deferred("_get_sub_playback", PARAM_DASH_RIGHT_PLAYBACK)
		_:
			_is_in_sub_state_machine = false
			_active_sub_playback = null
	
	ability_started.emit(ability)
	print("PlayerAnimator: Ability → ", ability_name)

func end_ability() -> void:
	"""End current ability and return to Locomotion.
	Call this from animation events or manually when ability should end."""
	if _state != State.CIPHER_CASTING:
		return
	
	print("PlayerAnimator: Ability ended → returning to Locomotion")
	_begin_travel("Locomotion")

func _on_animation_finished(anim_name: StringName) -> void:
	"""Called when any animation finishes. Used to detect ability completion."""
	if _state != State.CIPHER_CASTING:
		return
	
	# Check if the finished animation is one of our abilities
	var anim_str := str(anim_name)
	for ability_name in ABILITY_NAMES:
		if anim_str.contains(ability_name) or ability_name in anim_str:
			print("PlayerAnimator: Ability animation finished (", anim_name, ") → returning to Locomotion")
			_begin_travel("Locomotion")
			return

func play_ability_by_gesture(gesture_name: String) -> bool:
	"""Trigger an ability by gesture name. Returns true if gesture was mapped."""
	if not gesture_ability_map.has(gesture_name):
		return false
	
	var ability: int = gesture_ability_map[gesture_name]
	play_ability(ability)
	return true

# ============================================================================
# PHYSICS-DEPENDENT ABILITY CONTROL
# ============================================================================

func update_floor_status(on_floor: bool, velocity_y: float) -> void:
	"""Update sub-SM state based on physics. Call from player_controller every frame.
	- When velocity_y < 0 (falling): transition Jump/Dash → Fall
	- When on_floor: transition Fall → Land"""
	if not _is_in_sub_state_machine or not _active_sub_playback:
		return
	
	var current := _active_sub_playback.get_current_node()
	var is_dash_state := current in ["Dash", "DashLeft", "DashRight"]
	var is_jump_state := current == "Jump"
	var is_action_state := is_jump_state or is_dash_state
	
	# Jump/Dash → Fall when starting to fall (same threshold for both)
	if is_action_state and velocity_y < -0.1:
		_active_sub_playback.travel("Fall")
		_sub_state = "Fall"
		print("PlayerAnimator: Sub-SM ", current, " → Fall")
	
	# Fall → Land when touching ground
	elif current == "Fall" and on_floor:
		_active_sub_playback.travel("Land")
		_sub_state = "Land"
		landing_finished.emit()
		print("PlayerAnimator: Sub-SM Fall → Land")

func trigger_early_landing() -> void:
	"""Force transition to Land state (e.g., for predictive landing)."""
	if not _is_in_sub_state_machine or not _active_sub_playback:
		return
	
	var current := _active_sub_playback.get_current_node()
	if current == "Fall":
		_active_sub_playback.travel("Land")
		_sub_state = "Land"
		_sub_state_entered_time = Time.get_ticks_msec() / 1000.0
		landing_finished.emit()
		print("PlayerAnimator: Early landing triggered")

func _get_sub_playback(param_path: String) -> void:
	"""Deferred helper to get sub-SM playback after transition completes."""
	await get_tree().process_frame
	await get_tree().process_frame  # Wait an extra frame for transition
	
	_active_sub_playback = self.get(param_path) as AnimationNodeStateMachinePlayback
	if _active_sub_playback:
		print("PlayerAnimator: Got sub-playback for ", param_path)
	else:
		push_warning("PlayerAnimator: Could not get sub-playback: ", param_path)

func is_in_physics_ability() -> bool:
	"""Check if currently in a physics-dependent ability (Jump/Dash)."""
	return _is_in_sub_state_machine

func get_current_ability() -> int:
	return _current_ability

# ============================================================================
# DEATH
# ============================================================================

func play_death() -> void:
	"""Play death animation."""
	if not _tree_valid or _state == State.DEATH:
		return
	
	_set_state(State.DEATH)
	_begin_travel("Death")
	print("PlayerAnimator: DEATH")

func is_dead() -> bool:
	return _state == State.DEATH

func reset_from_death() -> void:
	"""Reset from death state (for respawn)."""
	if _state != State.DEATH:
		return
	
	_set_state(State.LOCOMOTION)
	_travel_pending = false
	_root_playback.travel("Locomotion")
	_blend_position = Vector2.ZERO
	_turn_blend = 0.0
	print("PlayerAnimator: Respawned → LOCOMOTION")

# ============================================================================
# CALL METHOD TRACK CALLBACKS
# ============================================================================

func _on_anim_event_jump_launch() -> void:
	"""Called by Call Method Track on jump animation."""
	print("PlayerAnimator: JUMP LAUNCH!")
	jump_launch.emit()

func _on_anim_event_dash_impulse() -> void:
	"""Called by Call Method Track on dash animations."""
	var direction := Vector3.ZERO
	match _current_ability:
		Ability.DASH_LEFT:
			direction = Vector3.LEFT
		Ability.DASH_RIGHT:
			direction = Vector3.RIGHT
	print("PlayerAnimator: DASH IMPULSE! Direction: ", direction)
	dash_impulse.emit(direction)

func _on_anim_event_landing_done() -> void:
	"""Called by Call Method Track on landing animation."""
	print("PlayerAnimator: Landing complete")
	landing_finished.emit()

func _on_anim_event_spell_effect() -> void:
	"""Called by Call Method Track on spell animations at cast point."""
	print("PlayerAnimator: Spell effect! Ability: ", _current_ability)
	spell_effect.emit(_current_ability)

func _on_anim_event_death_done() -> void:
	"""Called by Call Method Track on death animation."""
	print("PlayerAnimator: Death animation complete")
	death_finished.emit()

func _on_anim_event_turn_done() -> void:
	"""Called by Call Method Track on turn animations (optional)."""
	print("PlayerAnimator: Turn animation complete")

# ============================================================================
# PUBLIC API
# ============================================================================

func get_state() -> State:
	return _state

func is_in_air() -> bool:
	"""Check if currently in an airborne state."""
	if not _is_in_sub_state_machine:
		return false
	return _sub_state in ["Jump", "Dash", "Fall"]

func force_idle() -> void:
	"""Force return to idle (use for recovery from bad states)."""
	_set_state(State.LOCOMOTION)
	_travel_pending = false
	_is_in_sub_state_machine = false
	_sub_state = ""
	_active_sub_playback = null
	_current_ability = -1
	if _root_playback:
		_root_playback.travel("Locomotion")
	_blend_position = Vector2.ZERO
	_turn_blend = 0.0
