extends Node
class_name PlayerAnimator
## Professional animation controller using AnimationPlayer directly.
## Handles locomotion and jump sequences with proper state management.
##
## Attach as child of PlayerModel (sibling to AnimationPlayer).

enum State { LOCOMOTION, JUMPING, FALLING, LANDING, CASTING, DEATH }

# --- CONFIGURATION ---
@export_group("Animation Names")
@export var anim_idle := "player_library/idle"
@export var anim_walk := "player_library/walking"
@export var anim_walk_back := "player_library/walking back" ## Walking backward
@export var anim_run := "player_library/running"
@export var anim_run_back := "player_library/running back" ## Running backward
@export var anim_strafe_left := "player_library/walking left"
@export var anim_strafe_right := "player_library/walking right"
@export var anim_jumping := "player_library/jumping"
@export var anim_falling := "player_library/falling"
@export var anim_landing := "player_library/landing"
@export var anim_casting := "player_library/casting" ## Spell casting animation
@export var anim_death := "player_library/death" ## Death animation

@export_group("Thresholds")
@export_range(0.0, 1.0) var walk_threshold := 0.1
@export_range(0.0, 1.0) var run_threshold := 0.7
@export_range(0.0, 1.0) var blend_time := 0.15

@export_group("Jump Timing")
@export_range(0.0, 1.0) var jump_launch_point := 0.7 ## When to apply velocity (0.7 = 70% through jump animation)

# --- REFERENCES ---
var anim_player: AnimationPlayer

# --- STATE ---
var _state := State.LOCOMOTION
var _movement_input := Vector2.ZERO
var _current_locomotion := ""

# --- SIGNALS ---
signal state_changed(new_state: State)
signal jump_launch() ## Emitted when velocity should be applied (at launch_point in animation)
signal landing_finished()
signal death_finished() ## Emitted when death animation completes

func _ready() -> void:
	# Find AnimationPlayer in parent
	var parent := get_parent()
	if parent:
		anim_player = parent.get_node_or_null("AnimationPlayer") as AnimationPlayer
	
	if not anim_player:
		push_error("PlayerAnimator: AnimationPlayer not found in parent node!")
		return
	
	# Start idle
	_play(anim_idle)
	_current_locomotion = anim_idle
	print("PlayerAnimator: Initialized with AnimationPlayer")

func _process(_delta: float) -> void:
	if _state == State.LOCOMOTION:
		_update_locomotion()

# ============================================================================
# LOCOMOTION
# ============================================================================

func _update_locomotion() -> void:
	var target_anim := _get_locomotion_animation()
	if target_anim != _current_locomotion:
		_current_locomotion = target_anim
		_play(target_anim)

func _get_locomotion_animation() -> String:
	var mag := _movement_input.length()
	
	if mag < walk_threshold:
		return anim_idle
	
	# Check strafe vs forward/back
	if abs(_movement_input.x) > abs(_movement_input.y):
		return anim_strafe_left if _movement_input.x < 0 else anim_strafe_right
	else:
		if _movement_input.y > 0:
			return anim_run if mag >= run_threshold else anim_walk
		else:
			# Moving backward
			return anim_run_back if mag >= run_threshold else anim_walk_back

# ============================================================================
# JUMP SEQUENCE
# ============================================================================

func play_jump() -> void:
	"""Start the jump animation. Emits jump_launch when velocity should be applied."""
	if _state != State.LOCOMOTION:
		return
	
	_set_state(State.JUMPING)
	_play(anim_jumping, 0.1)
	print("PlayerAnimator: JUMPING (wind-up)")
	
	# Wait until launch point in animation, then emit signal
	_wait_for_launch_point()

func _wait_for_launch_point() -> void:
	"""Wait until launch point in jump animation, then emit jump_launch signal."""
	if not anim_player or not anim_player.has_animation(anim_jumping):
		jump_launch.emit()  # Fallback: emit immediately
		return
	
	var anim_length := anim_player.get_animation(anim_jumping).length
	var launch_time := anim_length * jump_launch_point
	
	# Wait until we reach the launch point
	while _state == State.JUMPING and anim_player:
		var current_pos := anim_player.current_animation_position
		if current_pos >= launch_time:
			break
		await get_tree().process_frame
	
	# Emit launch signal if still jumping
	if _state == State.JUMPING:
		print("PlayerAnimator: LAUNCH! (at ", jump_launch_point * 100, "% of animation)")
		jump_launch.emit()

func set_falling() -> void:
	"""Transition to falling loop. Called by controller when velocity.y < 0."""
	if _state == State.FALLING:
		return  # Already falling
	if _state != State.JUMPING:
		return  # Only transition from jumping
	
	_set_state(State.FALLING)
	_play(anim_falling, 0.1)
	print("PlayerAnimator: FALLING")
	
	# Start the falling loop
	_loop_falling()

func _loop_falling() -> void:
	"""Keep playing falling animation until landing is triggered."""
	while _state == State.FALLING and anim_player:
		# Wait for current falling animation to finish
		if anim_player.is_playing() and anim_player.current_animation == anim_falling:
			await anim_player.animation_finished
		
		# If still falling, replay
		if _state == State.FALLING and anim_player:
			anim_player.play(anim_falling, 0.0)  # Seamless loop

func play_landing() -> void:
	"""Play landing animation. Emits landing_finished when done."""
	if _state == State.LANDING:
		return  # Already landing
	if _state != State.FALLING and _state != State.JUMPING:
		return  # Only land from air states
	
	_set_state(State.LANDING)
	_play(anim_landing, 0.1)
	print("PlayerAnimator: LANDING")
	
	# Wait for landing to finish, then return to locomotion
	await anim_player.animation_finished
	
	_set_state(State.LOCOMOTION)
	_current_locomotion = ""  # Force locomotion update
	landing_finished.emit()
	print("PlayerAnimator: Landing complete → LOCOMOTION")

# ============================================================================
# SPELL CASTING
# ============================================================================

func play_spell_animation(cipher_name: String) -> void:
	"""Play a spell casting animation for the given cipher."""
	if _state == State.CASTING:
		return  # Already casting
	if _state != State.LOCOMOTION:
		return  # Only cast from locomotion
	
	_set_state(State.CASTING)
	
	# Try cipher-specific animation first, fallback to generic casting
	var specific_anim := "player_library/" + cipher_name
	if anim_player and anim_player.has_animation(specific_anim):
		_play(specific_anim, 0.1)
	elif anim_player and anim_player.has_animation(anim_casting):
		_play(anim_casting, 0.1)
	else:
		# No casting animation available, return to locomotion immediately
		_set_state(State.LOCOMOTION)
		return
	
	print("PlayerAnimator: CASTING (", cipher_name, ")")
	
	# Return to locomotion after cast animation
	await anim_player.animation_finished
	_set_state(State.LOCOMOTION)
	_current_locomotion = ""  # Force locomotion update
	print("PlayerAnimator: Cast complete → LOCOMOTION")

# ============================================================================
# DEATH
# ============================================================================

func play_death() -> void:
	"""Play death animation. Does not return to locomotion."""
	if _state == State.DEATH:
		return  # Already dead
	
	_set_state(State.DEATH)
	_play(anim_death, 0.1)
	print("PlayerAnimator: DEATH")
	
	# Wait for animation to finish, then emit signal
	if anim_player and anim_player.has_animation(anim_death):
		await anim_player.animation_finished
	death_finished.emit()

func is_dead() -> bool:
	"""Check if currently in death state."""
	return _state == State.DEATH

func reset_from_death() -> void:
	"""Reset from death state (for respawn). Call this to revive the player."""
	if _state != State.DEATH:
		return
	
	_set_state(State.LOCOMOTION)
	_current_locomotion = anim_idle
	_play(anim_idle)
	print("PlayerAnimator: Respawned → LOCOMOTION")

# ============================================================================
# PUBLIC API
# ============================================================================

func set_movement_input(input: Vector2) -> void:
	"""Update movement input vector (x=strafe, y=forward/back)."""
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
	_current_locomotion = anim_idle
	_play(anim_idle)

# ============================================================================
# INTERNAL
# ============================================================================

func _play(anim_name: String, custom_blend := -1.0) -> void:
	"""Play animation with validation."""
	if not anim_player:
		return
	
	if not anim_player.has_animation(anim_name):
		push_warning("PlayerAnimator: Animation not found: ", anim_name)
		return
	
	var blend := custom_blend if custom_blend >= 0 else blend_time
	anim_player.play(anim_name, blend)

func _set_state(new_state: State) -> void:
	"""Update state and emit signal."""
	if _state != new_state:
		_state = new_state
		state_changed.emit(new_state)
