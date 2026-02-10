extends Node3D
class_name CameraRig
## Third-person camera rig with spring arm collision avoidance.
## Head tracking rotates this rig (pivot), not the camera directly.
##
## Structure:
##   CameraRig (this script - pivot point at player shoulder height)
##     └── SpringArm3D (handles collision)
##           └── Camera3D (actual camera)

# --- REFERENCES ---
var spring_arm: SpringArm3D
var camera: Camera3D

# --- CAMERA SETTINGS ---
@export_group("Camera Distance")
@export_range(1.0, 10.0, 0.1) var camera_distance := 3.0 ## Distance from player
@export_range(0.0, 3.0, 0.1) var camera_height_offset := 0.5 ## Height offset on spring arm
@export_range(0.0, 1.0, 0.05) var shoulder_offset := 0.3 ## Horizontal offset for over-shoulder view

@export_group("Spring Arm")
@export_range(0.1, 1.0, 0.05) var collision_margin := 0.3 ## Collision margin
@export var collision_mask := 1 ## Collision layer for environment

@export_group("Look Sensitivity")
@export_range(0.5, 8.0, 0.1) var sensitivity_x := 2.5 ## Horizontal rotation speed
@export_range(0.5, 8.0, 0.1) var sensitivity_y := 1.5 ## Vertical rotation speed

@export_group("Look Limits")
@export_range(-1.57, 0.0, 0.05) var pitch_min := -1.2 ## Max look up (radians)
@export_range(0.0, 1.57, 0.05) var pitch_max := 1.2 ## Max look down (radians)

@export_group("Look Feel")
@export_range(1.0, 3.0, 0.1) var input_curve := 1.5 ## Precision curve (>1 = more precision near center)
@export_range(0.0, 1.0, 0.05) var input_smoothing := 0.1 ## Smoothing amount
@export var invert_x := false
@export var invert_y := false

# --- STATE ---
var look_input := Vector2.ZERO ## Raw input from vision system
var smoothed_input := Vector2.ZERO ## Smoothed for actual rotation
var current_pitch := 0.0 ## Current vertical angle

func _ready() -> void:
	_setup_camera_rig()

func _setup_camera_rig() -> void:
	"""Create SpringArm3D and Camera3D if they don't exist."""
	# Create or get SpringArm3D
	spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if not spring_arm:
		spring_arm = SpringArm3D.new()
		spring_arm.name = "SpringArm3D"
		add_child(spring_arm)
	
	# Configure spring arm
	spring_arm.spring_length = camera_distance
	spring_arm.margin = collision_margin
	spring_arm.collision_mask = collision_mask
	spring_arm.position = Vector3(shoulder_offset, camera_height_offset, 0)
	
	# Create or get Camera3D
	camera = spring_arm.get_node_or_null("Camera3D") as Camera3D
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		spring_arm.add_child(camera)
		camera.current = true
	
	# Camera looks back at the spring arm origin (player)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	
	print("CameraRig initialized - distance: ", camera_distance)

func _physics_process(delta: float) -> void:
	_update_rotation(delta)

func _update_rotation(delta: float) -> void:
	"""Apply rotation based on look input (head tracking)."""
	# Smooth the input
	if input_smoothing > 0:
		smoothed_input = smoothed_input.lerp(look_input, 1.0 - input_smoothing)
	else:
		smoothed_input = look_input
	
	# Apply input curve for precision
	var curved_x: float = sign(smoothed_input.x) * pow(abs(smoothed_input.x), input_curve)
	var curved_y: float = sign(smoothed_input.y) * pow(abs(smoothed_input.y), input_curve)
	
	# Apply inversion
	if invert_x:
		curved_x = -curved_x
	if invert_y:
		curved_y = -curved_y
	
	# Apply yaw rotation to this node (horizontal)
	rotation.y -= curved_x * sensitivity_x * delta
	
	# Apply pitch to spring arm (vertical) with clamping
	current_pitch -= curved_y * sensitivity_y * delta
	current_pitch = clamp(current_pitch, pitch_min, pitch_max)
	spring_arm.rotation.x = current_pitch

func set_look_input(input: Vector2) -> void:
	"""Set the look input from vision tracking."""
	look_input = input

func get_forward_direction() -> Vector3:
	"""Get the camera's forward direction on the XZ plane (for movement)."""
	var forward := -global_transform.basis.z
	forward.y = 0
	return forward.normalized()

func get_right_direction() -> Vector3:
	"""Get the camera's right direction on the XZ plane (for strafing)."""
	var right := global_transform.basis.x
	right.y = 0
	return right.normalized()

func get_look_direction() -> Vector3:
	"""Get the actual camera look direction (for aiming spells)."""
	if camera:
		return -camera.global_transform.basis.z
	return -global_transform.basis.z

## Called when camera settings are changed in editor
func _update_spring_arm_settings() -> void:
	if spring_arm:
		spring_arm.spring_length = camera_distance
		spring_arm.margin = collision_margin
		spring_arm.collision_mask = collision_mask
		spring_arm.position = Vector3(shoulder_offset, camera_height_offset, 0)
