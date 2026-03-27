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
@export_range(5.0, 50.0, 0.5) var dash_speed := 15.0 ## Horizontal dash speed
@export_range(0.0, 30.0, 0.5) var dash_jump_force := 10.0 ## Vertical force for dash
@export_range(0.0, 1.0, 0.05) var dash_air_control := 0.0 ## How much player can steer during dash (0 = none, 1 = full)

@export_group("Character Rotation")
@export_range(1.0, 20.0, 0.5) var rotation_speed := 10.0 ## How fast character turns
@export var face_camera_forward := true ## Character always faces camera direction (third-person)
@export_group("Wind Jump")
@export_range(5.0, 30.0, 0.5) var wind_jump_force := 15.0 ## Initial upward velocity for wind jump
@export_range(0.5, 3.0, 0.1) var wind_jump_duration := 1.0 ## How long the wind boost lasts
@export var wind_jump_cipher := "air_blast" ## Which cipher triggers wind jump (upward chevron)
@export_range(0.5, 5.0, 0.1) var landing_detection_height := 1.5 ## Height at which to start landing animation (match animation duration)

# --- COMPONENT REFERENCES ---
var camera_rig: CameraRig
var player_animator: PlayerAnimator
var cipher_hud: GameHUD  ## Consolidated game HUD (health, mana, cipher drawing)
var spell_origin: Marker3D  ## Where spells spawn from (hand level)
var ground_raycast: RayCast3D  ## Detects ground for landing anticipation

# --- SPELL SPAWN POINTS ---
var feet_origin: Marker3D  ## Ground level at feet
var ground_target: Marker3D  ## Ground in front of player
var body_origin: Marker3D  ## Body center for expanding effects

# --- STATE ---
var move_input := Vector2.ZERO ## Movement input (lean_x, lean_y)
var look_input := Vector2.ZERO ## Look input for idle turning
var last_recognized_gesture := "" ## Prevent duplicate spell casts
var is_in_physics_ability := false ## Currently in a physics-dependent ability (jump/dash)
var was_on_floor := true ## Track floor state for landing detection
var ability_has_launched := false ## True once ability velocity is applied

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
	
	# Player animator (AnimationTree with PlayerAnimator script, under PlayerModel)
	var player_model: Node3D = get_node_or_null("PlayerModel")
	if player_model:
		player_animator = player_model.get_node_or_null("PlayerAnimator") as PlayerAnimator
		if not player_animator:
			push_warning("PlayerController: PlayerAnimator (AnimationTree) not found in PlayerModel")
	
	# Spell origin marker (hand level) - parent to PlayerModel so it rotates with character
	var marker_parent: Node3D = player_model if player_model else self
	
	spell_origin = get_node_or_null("SpellOrigin") as Marker3D
	if not spell_origin and marker_parent:
		spell_origin = marker_parent.get_node_or_null("SpellOrigin") as Marker3D
	if not spell_origin:
		spell_origin = Marker3D.new()
		spell_origin.name = "SpellOrigin"
		spell_origin.position = Vector3(0, 1.2, -0.5)  # Chest height, slightly forward (-Z is forward)
		marker_parent.add_child(spell_origin)
	
	# Feet origin (ground level)
	feet_origin = get_node_or_null("FeetOrigin") as Marker3D
	if not feet_origin and marker_parent:
		feet_origin = marker_parent.get_node_or_null("FeetOrigin") as Marker3D
	if not feet_origin:
		feet_origin = Marker3D.new()
		feet_origin.name = "FeetOrigin"
		feet_origin.position = Vector3(0, 0.05, 0)  # Just above ground
		marker_parent.add_child(feet_origin)
	
	# Ground target (in front of player)
	ground_target = get_node_or_null("GroundTarget") as Marker3D
	if not ground_target and marker_parent:
		ground_target = marker_parent.get_node_or_null("GroundTarget") as Marker3D
	if not ground_target:
		ground_target = Marker3D.new()
		ground_target.name = "GroundTarget"
		ground_target.position = Vector3(0, 0.05, -1.5)  # 1.5m in front at ground (-Z is forward)
		marker_parent.add_child(ground_target)
	
	# Body origin (center mass)
	body_origin = get_node_or_null("BodyOrigin") as Marker3D
	if not body_origin and marker_parent:
		body_origin = marker_parent.get_node_or_null("BodyOrigin") as Marker3D
	if not body_origin:
		body_origin = Marker3D.new()
		body_origin.name = "BodyOrigin"
		body_origin.position = Vector3(0, 1.0, 0)  # Chest height
		marker_parent.add_child(body_origin)
	
	# Ground detection raycast for landing anticipation
	ground_raycast = RayCast3D.new()
	ground_raycast.name = "GroundRaycast"
	ground_raycast.target_position = Vector3(0, -landing_detection_height - 1.0, 0)  # Cast down
	ground_raycast.collision_mask = 1  # Adjust if ground is on different layer
	ground_raycast.enabled = true
	add_child(ground_raycast)
	
	# Create HUD for cipher feedback (using consolidated GameHUD)
	var hud_scene := preload("res://scenes/ui/game_hud.tscn")
	cipher_hud = hud_scene.instantiate()
	add_child(cipher_hud)
	
	# Connect animator signals
	if player_animator:
		player_animator.jump_launch.connect(_on_jump_launch)
		player_animator.dash_impulse.connect(_on_dash_impulse)
		player_animator.landing_finished.connect(_on_landing_finished)
		player_animator.spell_effect.connect(_on_spell_effect)
	
	# Register spawn points with SpellManager
	_register_with_spell_manager()
	
	print("PlayerController initialized")

func _register_with_spell_manager() -> void:
	"""Register this player and spawn points with the SpellManager singleton."""
	if not has_node("/root/SpellManager"):
		push_warning("PlayerController: SpellManager autoload not found")
		return
	
	var spell_mgr := get_node("/root/SpellManager")
	if not spell_mgr.has_method("register_player"):
		return
	
	# SpellManager.SpawnLocation enum values
	# FEET = 0, GROUND_FRONT = 1, BODY_CENTER = 2, HAND = 3
	var spawn_points := {
		0: feet_origin,      # FEET
		1: ground_target,    # GROUND_FRONT
		2: body_origin,      # BODY_CENTER
		3: spell_origin      # HAND
	}
	
	spell_mgr.register_player(self, spawn_points)
	print("PlayerController: Registered with SpellManager")

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
		look_input.x = data.get("look_x", 0.0)
		look_input.y = data.get("look_y", 0.0)
		if camera_rig:
			camera_rig.set_look_input(look_input)
	else:
		look_input = Vector2.ZERO
		if camera_rig:
			camera_rig.set_look_input(Vector2.ZERO)
	
	# --- MOVEMENT (Body lean) ---
	if data.get("has_body", false) and is_calibrated:
		move_input.x = data.get("lean_x", 0.0)
		move_input.y = data.get("lean_y", 0.0)
	else:
		move_input = Vector2.ZERO
	
	# Update animator with movement and idle turn
	if player_animator:
		player_animator.set_movement_input(move_input)
		# Drive idle turn animation when stationary (using look_x for angular velocity)
		if move_input.length() < 0.1:
			player_animator.set_idle_turn(look_input.x)
		else:
			player_animator.set_idle_turn(0.0)
	
	movement_changed.emit(move_input)
	
	# --- GESTURE RECOGNITION (From Python) ---
	_process_gesture_data(data)

func _process_gesture_data(data: Dictionary) -> void:
	"""Handle gesture state and recognition from vision system."""
	var gesture_state: String = data.get("gesture_state", "idle")
	var gesture_recognized = data.get("gesture_recognized")  # Can be null
	var gesture_score: float = data.get("gesture_score", 0.0)
	var stroke_points: Array = data.get("stroke_points", [])
	
	# Update HUD and stance
	var is_casting_mode := gesture_state in ["ready_to_draw", "drawing"]
	if player_animator:
		player_animator.set_stance(is_casting_mode)
	
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
	
	# Trigger ability animation via the new system
	if player_animator:
		if player_animator.play_ability_by_gesture(cipher_name):
			# Track if this is a physics-dependent ability
			var ability := player_animator.get_current_ability()
			if ability in [PlayerAnimator.Ability.JUMP, PlayerAnimator.Ability.DASH_LEFT, PlayerAnimator.Ability.DASH_RIGHT]:
				is_in_physics_ability = true
				ability_has_launched = false
				was_on_floor = is_on_floor()
			return
	
	# Fallback: Dispatch spell effect via autoload for unrecognized gestures
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

func _on_jump_launch() -> void:
	"""Called by animator when it's time to apply jump velocity."""
	if ability_has_launched:
		return  # Guard against multiple calls
	print("Jump launched! Applying force: ", wind_jump_force)
	velocity.y = wind_jump_force
	ability_has_launched = true


func _on_dash_impulse(direction: Vector3) -> void:
	"""Called by animator when it's time to apply dash velocity.
	Works like jump but with horizontal movement added."""
	if ability_has_launched:
		return  # Guard against multiple calls
	if not camera_rig:
		return
	
	# Transform direction from local to world space based on camera
	var right := camera_rig.get_right_direction()
	var world_direction := right * direction.x
	
	print("Dash launched! Direction: ", world_direction, " Horizontal: ", dash_speed, " Vertical: ", dash_jump_force)
	
	# Apply vertical force (like jump)
	velocity.y = dash_jump_force
	
	# Apply horizontal force
	velocity.x = world_direction.x * dash_speed
	velocity.z = world_direction.z * dash_speed
	
	ability_has_launched = true


func _on_landing_finished() -> void:
	"""Called by animator when landing animation completes."""
	print("Landing finished, resetting physics ability state")
	is_in_physics_ability = false
	ability_has_launched = false


func _on_spell_effect(ability: int) -> void:
	"""Called by animator when spell effect should trigger."""
	if not has_node("/root/SpellManager"):
		return
	
	var spell_mgr := get_node("/root/SpellManager")
	if not spell_mgr.has_method("cast_spell"):
		return
	
	# Map ability index back to cipher name for SpellManager
	var cipher_name := ""
	for gesture in player_animator.gesture_ability_map:
		if player_animator.gesture_ability_map[gesture] == ability:
			cipher_name = gesture
			break
	
	if cipher_name != "":
		spell_mgr.cast_spell(cipher_name, _get_spell_origin(), _get_spell_direction())

func _update_air_state() -> void:
	"""Update animator based on air state (for physics-dependent abilities)."""
	var on_floor := is_on_floor()
	
	# Update the animator's sub-state machine if in a physics ability
	if is_in_physics_ability and player_animator and player_animator.is_in_physics_ability():
		player_animator.update_floor_status(on_floor, velocity.y)
		
		# Early landing via raycast anticipation
		if not on_floor and ability_has_launched and velocity.y < 0:
			if ground_raycast and ground_raycast.is_colliding():
				var collision_point := ground_raycast.get_collision_point()
				var distance_to_ground := global_position.y - collision_point.y
				
				if distance_to_ground <= landing_detection_height:
					player_animator.trigger_early_landing()
					print("Landing anticipation at height: ", distance_to_ground)
	
	was_on_floor = on_floor

func _apply_movement(_delta: float) -> void:
	"""Apply movement based on camera direction and lean input.
	During physics abilities, momentum is preserved based on dash_air_control."""
	if not camera_rig:
		return
	
	var right := camera_rig.get_right_direction()
	var forward := camera_rig.get_forward_direction()
	
	# Combine strafe (x) and walk (y) into target velocity
	var target_vel := right * move_input.x * strafe_speed + forward * move_input.y * walk_speed
	
	# During physics abilities, use air_control to blend between momentum and input
	var smoothing := move_smoothing
	if is_in_physics_ability:
		smoothing = move_smoothing * dash_air_control  # 0 = full momentum, 1 = full control
	
	velocity.x = lerp(velocity.x, target_vel.x, smoothing)
	velocity.z = lerp(velocity.z, target_vel.z, smoothing)

func _update_character_rotation(delta: float) -> void:
	"""Smoothly rotate the player model to face camera forward direction."""
	if not face_camera_forward or not camera_rig:
		return
	
	var player_model: Node3D = get_node_or_null("PlayerModel") as Node3D
	if not player_model:
		return
	
	var cam_forward := camera_rig.get_forward_direction()
	if cam_forward.length_squared() < 0.01:
		return
	
	var target_yaw := atan2(cam_forward.x, cam_forward.z)
	var model_rot: Vector3 = player_model.rotation
	var current_yaw := model_rot.y
	
	# Smoothly lerp rotation toward camera forward
	player_model.rotation.y = lerp_angle(current_yaw, target_yaw, clampf(rotation_speed * delta, 0.0, 1.0))

func _update_stroke_visualization(stroke_points: Array) -> void:
	"""Update the cipher stroke visualization on HUD."""
	if not cipher_hud:
		return
	
	# Use the consolidated GameHUD method that handles coordinate conversion
	cipher_hud.update_stroke_from_vision(stroke_points)

func _clear_stroke_visualization() -> void:
	"""Clear the cipher stroke from HUD."""
	if not cipher_hud:
		return
	
	cipher_hud.clear_stroke()
