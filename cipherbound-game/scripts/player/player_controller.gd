extends CharacterBody3D
class_name PlayerController
## Main player controller for third-person gameplay.
## Handles UDP vision data, movement, and spell dispatch.
## Camera and animations are handled by child components.

# --- NETWORK ---
var server := UDPServer.new()
@export_group("Network")
@export var port := 5005 ## UDP port to listen on

# --- MOVEMENT SETTINGS ---
@export_group("Movement")
@export_range(1.0, 15.0, 0.5) var strafe_speed := 5.0 ## Left/right movement speed
@export_range(1.0, 15.0, 0.5) var walk_speed := 5.0 ## Forward/back movement speed
@export_range(0.05, 0.5, 0.05) var move_smoothing := 0.15 ## Movement smoothing

@export_group("Character Rotation")
@export_range(1.0, 20.0, 0.5) var rotation_speed := 10.0 ## How fast character turns
@export var face_camera_forward := true ## Character always faces camera direction (third-person)

@export_group("Wind Jump")
@export_range(5.0, 30.0, 0.5) var wind_jump_force := 15.0 ## Initial upward velocity for wind jump
@export_range(0.5, 3.0, 0.1) var wind_jump_duration := 1.0 ## How long the wind boost lasts
@export var wind_jump_cipher := "fire" ## Which cipher triggers wind jump (upward chevron)
@export_range(0.5, 5.0, 0.1) var landing_detection_height := 1.5 ## Height at which to start landing animation (match animation duration)

# --- COMPONENT REFERENCES ---
var camera_rig: CameraRig
var player_animator: PlayerAnimator
var cipher_hud: CanvasLayer
var spell_origin: Marker3D  ## Where spells spawn from
var ground_raycast: RayCast3D  ## Detects ground for landing anticipation

# --- STATE ---
var move_input := Vector2.ZERO ## Movement input (lean_x, lean_y)
var last_recognized_gesture := "" ## Prevent duplicate spell casts
var is_wind_jumping := false ## Currently performing wind jump
var was_on_floor := true ## Track floor state for landing detection
var is_landing_triggered := false ## Prevents multiple landing triggers
var jump_has_peaked := false ## True once velocity.y goes negative (reached apex)
var jump_has_launched := false ## True once jump velocity is actually applied

# --- GRAVITY ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- SIGNALS ---
signal cipher_cast(cipher_name: String, confidence: float)
signal movement_changed(input: Vector2)

func _ready() -> void:
	_setup_components()
	_start_network()

func _setup_components() -> void:
	"""Find and setup all required components."""
	# Camera rig
	camera_rig = get_node_or_null("CameraRig") as CameraRig
	if not camera_rig:
		push_warning("PlayerController: No CameraRig found - creating default")
		camera_rig = CameraRig.new()
		camera_rig.name = "CameraRig"
		add_child(camera_rig)
		# Position at shoulder height
		camera_rig.position = Vector3(0, 1.6, 0)
	
	# Player animator (look in PlayerModel)
	var player_model := get_node_or_null("PlayerModel")
	if player_model:
		player_animator = player_model.get_node_or_null("PlayerAnimator") as PlayerAnimator
		if not player_animator:
			# Try to create it
			player_animator = PlayerAnimator.new()
			player_animator.name = "PlayerAnimator"
			player_model.add_child(player_animator)
	
	# Spell origin marker
	spell_origin = get_node_or_null("SpellOrigin") as Marker3D
	if not spell_origin:
		spell_origin = Marker3D.new()
		spell_origin.name = "SpellOrigin"
		spell_origin.position = Vector3(0, 1.2, 0.5)  # Chest height, slightly forward
		add_child(spell_origin)
	
	# Ground detection raycast for landing anticipation
	ground_raycast = RayCast3D.new()
	ground_raycast.name = "GroundRaycast"
	ground_raycast.target_position = Vector3(0, -landing_detection_height - 1.0, 0)  # Cast down
	ground_raycast.collision_mask = 1  # Adjust if ground is on different layer
	ground_raycast.enabled = true
	add_child(ground_raycast)
	
	# Create HUD for cipher feedback
	cipher_hud = load("res://scripts/vision/cipher_hud.gd").new()
	add_child(cipher_hud)
	
	print("PlayerController initialized")

func _start_network() -> void:
	"""Start the UDP server for vision data."""
	var err := server.listen(port)
	if err != OK:
		printerr("Failed to listen on port ", port)
	else:
		print("Cipherbound listening on port ", port)

func _physics_process(delta: float) -> void:
	_process_network_data()
	_apply_gravity(delta)
	_apply_movement(delta)
	_update_character_rotation(delta)
	_update_air_state()
	move_and_slide()

func _process_network_data() -> void:
	"""Receive and process vision tracking data from Python."""
	server.poll()
	if not server.is_connection_available():
		return
	
	var peer := server.take_connection()
	var packet := peer.get_packet()
	var data_str := packet.get_string_from_utf8()
	
	var json := JSON.new()
	var error := json.parse(data_str)
	if error != OK:
		return
	
	var data: Dictionary = json.data
	var is_calibrated: bool = data.get("calibrated", false)
	
	# --- CAMERA LOOK (Head tracking) ---
	if data.get("has_face", false) and is_calibrated:
		var look_x: float = data.get("look_x", 0.0)
		var look_y: float = data.get("look_y", 0.0)
		if camera_rig:
			camera_rig.set_look_input(Vector2(look_x, look_y))
	else:
		if camera_rig:
			camera_rig.set_look_input(Vector2.ZERO)
	
	# --- MOVEMENT (Body lean) ---
	if data.get("has_body", false) and is_calibrated:
		move_input.x = data.get("lean_x", 0.0)
		move_input.y = data.get("lean_y", 0.0)
	else:
		move_input = Vector2.ZERO
	
	# Update animator with movement
	if player_animator:
		player_animator.set_movement_input(move_input)
	
	movement_changed.emit(move_input)
	
	# --- GESTURE RECOGNITION (From Python) ---
	_process_gesture_data(data)

func _process_gesture_data(data: Dictionary) -> void:
	"""Handle gesture state and recognition from vision system."""
	var gesture_state: String = data.get("gesture_state", "idle")
	var gesture_recognized = data.get("gesture_recognized")  # Can be null
	var gesture_score: float = data.get("gesture_score", 0.0)
	var stroke_points: Array = data.get("stroke_points", [])
	
	# Update HUD
	if cipher_hud:
		match gesture_state:
			"idle":
				cipher_hud.update_tracking_status(true, false)
				_clear_stroke_visualization()
			"ready_to_draw":
				cipher_hud.update_tracking_status(true, false)
				_clear_stroke_visualization()
			"drawing":
				cipher_hud.update_tracking_status(true, true)
				_update_stroke_visualization(stroke_points)
	
	# Handle recognized gesture
	if gesture_recognized != null and gesture_recognized != "":
		if gesture_recognized != last_recognized_gesture:
			print("CIPHER RECOGNIZED: ", gesture_recognized, " (", gesture_score, ")")
			_on_cipher_recognized(gesture_recognized, gesture_score)
			last_recognized_gesture = gesture_recognized
			
			if cipher_hud:
				cipher_hud.on_cipher_recognized(gesture_recognized, gesture_score)
	else:
		last_recognized_gesture = ""

func _on_cipher_recognized(cipher_name: String, confidence: float) -> void:
	"""Handle successful cipher recognition - trigger animation and spell."""
	cipher_cast.emit(cipher_name, confidence)
	
	# Check if this is a wind jump cipher
	if cipher_name == wind_jump_cipher:
		_perform_wind_jump()
		return
	
	# Trigger animation for other spells
	if player_animator:
		player_animator.play_spell_animation(cipher_name)
	
	# Dispatch spell effect via autoload (if registered in Project Settings)
	if has_node("/root/SpellManager"):
		var spell_mgr := get_node("/root/SpellManager")
		if spell_mgr.has_method("cast_spell"):
			spell_mgr.cast_spell(cipher_name, _get_spell_origin(), _get_spell_direction())

func _get_spell_origin() -> Vector3:
	"""Get the world position where spells should spawn."""
	if spell_origin:
		return spell_origin.global_position
	return global_position + Vector3(0, 1.2, 0)

func _get_spell_direction() -> Vector3:
	"""Get the direction spells should travel (camera look direction)."""
	if camera_rig:
		return camera_rig.get_look_direction()
	return -global_transform.basis.z

func _apply_gravity(delta: float) -> void:
	"""Apply gravity when not on floor."""
	if not is_on_floor():
		velocity.y -= gravity * delta

func _perform_wind_jump() -> void:
	"""Perform a wind-boosted jump."""
	if is_wind_jumping:
		return  # Already jumping
	
	print("Wind Jump activated!")
	is_wind_jumping = true
	is_landing_triggered = false  # Reset landing state
	jump_has_peaked = false  # Reset peak tracking
	jump_has_launched = false  # Will be set true when velocity is applied
	was_on_floor = false
	
	# Trigger jump animation - velocity applied when animation reaches launch point
	if player_animator:
		# Connect to launch signal (one-shot)
		if not player_animator.jump_launch.is_connected(_on_jump_launch):
			player_animator.jump_launch.connect(_on_jump_launch, CONNECT_ONE_SHOT)
		player_animator.play_jump()
	else:
		# No animator, apply force immediately
		velocity.y = wind_jump_force
	
	# TODO: Add wind particle effects here

func _on_jump_launch() -> void:
	"""Called by animator when it's time to apply jump velocity."""
	print("Jump launched! Applying force: ", wind_jump_force)
	velocity.y = wind_jump_force
	jump_has_launched = true

func _update_air_state() -> void:
	"""Update animator based on air state (for jump/fall/land transitions)."""
	var on_floor := is_on_floor()
	
	# Track when we've reached the peak of the jump (velocity goes from positive to negative)
	# Only check after we've actually launched (velocity applied)
	if is_wind_jumping and jump_has_launched and velocity.y <= 0 and not jump_has_peaked:
		jump_has_peaked = true
		print("Jump peaked, now falling")
		if player_animator:
			player_animator.set_falling()
	
	# Fully landed - reset state
	if on_floor and not was_on_floor and jump_has_peaked:
		if is_wind_jumping:
			# Only trigger landing if we haven't already (raycast anticipation)
			if not is_landing_triggered and player_animator:
				player_animator.play_landing()
			# Wind jump ends after landing animation
			if player_animator:
				await player_animator.landing_finished
			is_wind_jumping = false
			is_landing_triggered = false
			jump_has_peaked = false
			jump_has_launched = false
	
	# Only check for landing anticipation AFTER we've peaked (going down)
	if not on_floor and is_wind_jumping and jump_has_peaked:
		# Check for approaching ground (landing anticipation)
		if ground_raycast and ground_raycast.is_colliding():
			var collision_point := ground_raycast.get_collision_point()
			var distance_to_ground := global_position.y - collision_point.y
			
			# Trigger landing animation early when approaching ground
			if distance_to_ground <= landing_detection_height and not is_landing_triggered:
				is_landing_triggered = true
				if player_animator:
					player_animator.play_landing()
					print("Landing anticipation triggered at height: ", distance_to_ground)
	
	was_on_floor = on_floor

func _apply_movement(_delta: float) -> void:
	"""Apply movement based on camera direction and lean input."""
	if not camera_rig:
		return
	
	var right := camera_rig.get_right_direction()
	var forward := camera_rig.get_forward_direction()
	
	# Combine strafe (x) and walk (y) into target velocity
	var target_vel := right * move_input.x * strafe_speed + forward * move_input.y * walk_speed
	
	velocity.x = lerp(velocity.x, target_vel.x, move_smoothing)
	velocity.z = lerp(velocity.z, target_vel.z, move_smoothing)

func _update_character_rotation(delta: float) -> void:
	"""Smoothly rotate the player model to always face camera forward direction."""
	if not face_camera_forward or not camera_rig:
		return
	
	var player_model := get_node_or_null("PlayerModel")
	if not player_model:
		return
	
	# Get camera's forward direction on XZ plane
	var cam_forward := camera_rig.get_forward_direction()
	if cam_forward.length_squared() < 0.01:
		return
	
	# Calculate target rotation - use positive values since PlayerModel has 180° baked in
	var target_rotation: float = atan2(cam_forward.x, cam_forward.z)
	
	# Smoothly interpolate toward target
	var current: float = player_model.rotation.y
	var diff: float = wrapf(target_rotation - current, -PI, PI)
	player_model.rotation.y += diff * rotation_speed * delta

func _update_stroke_visualization(stroke_points: Array) -> void:
	"""Update the cipher stroke visualization on HUD."""
	if not cipher_hud:
		return
	
	cipher_hud.draw_points.clear()
	for point in stroke_points:
		if point is Array and point.size() >= 2:
			# Convert from centered (-1,1) to normalized (0,1)
			var x := (float(point[0]) + 1.0) / 2.0
			var y := (float(point[1]) + 1.0) / 2.0
			cipher_hud.draw_points.append(Vector2(x, y))
	
	if cipher_hud.draw_canvas:
		cipher_hud.draw_canvas.queue_redraw()

func _clear_stroke_visualization() -> void:
	"""Clear the cipher stroke from HUD."""
	if not cipher_hud:
		return
	
	cipher_hud.draw_points.clear()
	if cipher_hud.draw_canvas:
		cipher_hud.draw_canvas.queue_redraw()
