extends CharacterBody3D

# --- NETWORK ---
var server := UDPServer.new()
@export_group("Network")
@export var port := 5005  ## UDP port to listen on

# --- LOOK SETTINGS (Camera rotation from face tracking) ---
@export_group("Look Sensitivity")
@export_range(0.5, 8.0, 0.1) var sensitivity_x := 2.5  ## Horizontal rotation speed (rad/sec at full input)
@export_range(0.5, 8.0, 0.1) var sensitivity_y := 1.5  ## Vertical rotation speed (rad/sec at full input)

@export_group("Look Limits")
@export_range(-1.57, 0.0, 0.05) var pitch_min := -1.2  ## Max look up angle (radians, -1.57 = straight up)
@export_range(0.0, 1.57, 0.05) var pitch_max := 1.2  ## Max look down angle (radians, 1.57 = straight down)

@export_group("Look Feel")
@export_range(1.0, 3.0, 0.1) var input_curve := 1.5  ## Input curve (1.0 = linear, >1 = more precision near center)
@export_range(0.0, 1.0, 0.05) var input_smoothing := 0.0  ## Smoothing (0 = instant, 1 = very smooth/laggy)
@export var invert_x := false  ## Invert horizontal look
@export var invert_y := false  ## Invert vertical look

# --- MOVEMENT SETTINGS ---
@export_group("Movement")
@export_range(1.0, 15.0, 0.5) var strafe_speed := 5.0  ## Left/right movement speed
@export_range(1.0, 15.0, 0.5) var walk_speed := 5.0  ## Forward/back movement speed
@export_range(0.05, 0.5, 0.05) var move_smoothing := 0.15  ## Movement smoothing

# --- STATE ---
var look_input := Vector2.ZERO  # Current joystick input (-1 to +1)
var smoothed_input := Vector2.ZERO  # Smoothed input
var move_input := Vector2.ZERO  # Movement input (lean_x, lean_y)
var camera: Camera3D
var arms: Node3D  # Arms controller (optional)
var cipher_hud: CanvasLayer  # HUD for drawing feedback

# --- GRAVITY ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# Get camera reference
	camera = $Camera3D
	if not camera:
		push_error("Player needs a Camera3D child node!")
		return
	
	# Get arms reference (optional - will be created if Arms node exists under Camera)
	arms = camera.get_node_or_null("Arms")
	if arms:
		print("Arms controller found")
	
	# Create HUD for cipher feedback
	cipher_hud = load("res://scripts/CipherHUD.gd").new()
	add_child(cipher_hud)
	
	# Start UDP server
	var err = server.listen(port)
	if err != OK:
		printerr("Failed to listen on port " + str(port))
	else:
		print("Cipherbound Player listening on port " + str(port))

func _physics_process(delta):
	# 1. Receive vision data
	process_network_data()
	
	# 2. Apply input smoothing if enabled
	if input_smoothing > 0:
		smoothed_input = smoothed_input.lerp(look_input, 1.0 - input_smoothing)
	else:
		smoothed_input = look_input
	
	# 3. Apply continuous rotation based on joystick input
	if camera:
		# Apply input curve for better precision near center
		var curved_x = sign(smoothed_input.x) * pow(abs(smoothed_input.x), input_curve)
		var curved_y = sign(smoothed_input.y) * pow(abs(smoothed_input.y), input_curve)
		
		# Apply inversion if enabled
		if invert_x:
			curved_x = -curved_x
		if invert_y:
			curved_y = -curved_y
		
		# Rotate continuously based on input (like a real joystick)
		camera.rotation.y -= curved_x * sensitivity_x * delta  # Yaw (left/right)
		camera.rotation.x -= curved_y * sensitivity_y * delta  # Pitch (up/down)
		
		# Clamp pitch to prevent flipping
		camera.rotation.x = clamp(camera.rotation.x, pitch_min, pitch_max)
	
	# 4. Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# 5. Apply movement (strafe + forward/back based on camera direction)
	if camera:
		var right = camera.global_transform.basis.x
		right.y = 0
		right = right.normalized()
		
		var forward = camera.global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		
		# Combine strafe (lean_x) and walk (lean_y) into target velocity
		var target_vel = right * move_input.x * strafe_speed - forward * move_input.y * walk_speed
		velocity.x = lerp(velocity.x, target_vel.x, move_smoothing)
		velocity.z = lerp(velocity.z, target_vel.z, move_smoothing)
	
	# 6. Move the player
	move_and_slide()

func process_network_data():
	server.poll()
	if server.is_connection_available():
		var peer = server.take_connection()
		var packet = peer.get_packet()
		var data_str = packet.get_string_from_utf8()
		
		var json = JSON.new()
		var error = json.parse(data_str)
		
		if error == OK:
			var data = json.data
			var is_calibrated = data.get("calibrated", false)
			
			# Face tracking -> Camera rotation (only if calibrated)
			if data.get("has_face", false) and is_calibrated:
				# Store the joystick input for continuous rotation
				look_input.x = data.get("look_x", 0.0)
				look_input.y = data.get("look_y", 0.0)
			else:
				# No face or not calibrated, stop rotating
				look_input = Vector2.ZERO
			
			# Body tracking -> Movement (only if calibrated)
			if data.get("has_body", false) and is_calibrated:
				move_input.x = data.get("lean_x", 0.0)
				move_input.y = data.get("lean_y", 0.0)
			else:
				move_input = Vector2.ZERO
			
			# Hand tracking -> Arms (always update, no calibration needed)
			if arms and arms.has_method("update_from_vision_data"):
				arms.update_from_vision_data(data)
			
			# --- PYTHON-SIDE GESTURE RECOGNITION ---
			# All gesture recognition is now done in the Python vision server
			# We just receive the recognized gesture and cast spells
			
			var gesture_state: String = data.get("gesture_state", "idle")
			var gesture_recognized = data.get("gesture_recognized")  # Can be null/string
			var gesture_score: float = data.get("gesture_score", 0.0)
			
			# Update HUD with gesture state
			if cipher_hud:
				match gesture_state:
					"idle":
						cipher_hud.update_tracking_status(false, false)
					"ready_to_draw":
						cipher_hud.update_tracking_status(true, false)
					"drawing":
						cipher_hud.update_tracking_status(true, true)
			
			# Handle recognized gesture
			if gesture_recognized != null and gesture_recognized != "":
				print("PYTHON RECOGNIZED: ", gesture_recognized, " (", gesture_score, ")")
				_on_cipher_cast(gesture_recognized, gesture_score)
				# Notify HUD of recognition
				if cipher_hud:
					cipher_hud.on_cipher_recognized(gesture_recognized, gesture_score)

func _on_cipher_cast(cipher_name: String, _confidence: float):
	"""Handle successful cipher cast - trigger spell effects!"""
	print("SPELL CAST: ", cipher_name)
	match cipher_name:
		"fire":
			_cast_fire_spell()
		"water":
			_cast_water_spell()
		"shield":
			_cast_shield_spell()
		"lightning":
			_cast_lightning_spell()

func _cast_fire_spell():
	"""Placeholder for fire spell effect."""
	print("🔥 Fire erupts from your hands!")
	# TODO: Add particle effects, damage, etc.

func _cast_water_spell():
	"""Placeholder for water spell effect."""
	print("💧 Water flows around you!")

func _cast_shield_spell():
	"""Placeholder for shield spell effect."""
	print("🛡️ A magical barrier surrounds you!")

func _cast_lightning_spell():
	"""Placeholder for lightning spell effect."""
	print("⚡ Lightning crackles through the air!")
