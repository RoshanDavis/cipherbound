extends Node3D
## First-person arm controller that mirrors real hand movements.
## Attach this as a child of Camera3D.
## 
## Structure:
##   Camera3D
##     └── Arms (this script)
##           ├── LeftArm (Node3D with MeshInstance3D children)
##           └── RightArm (Node3D with MeshInstance3D children)

# --- ARM REFERENCES ---
@onready var left_arm: Node3D = $LeftArm
@onready var right_arm: Node3D = $RightArm

# --- SETTINGS ---
@export_group("Arm Positioning")
@export var arm_distance := 0.4 ## How far in front of camera
@export var arm_scale := Vector3(0.15, 0.15, 0.4) ## Scale of arm mesh
@export var hand_scale := Vector3(0.1, 0.1, 0.1) ## Scale of hand mesh

@export_group("Movement")
@export_range(0.0, 1.0, 0.05) var position_smoothing := 0.15 ## Lower = smoother
@export var horizontal_range := 0.6 ## How far arms can move left/right
@export var vertical_range := 0.4 ## How far arms can move up/down
@export var depth_range := 0.3 ## How far arms can move forward/back

@export_group("Rest Position")
@export var left_rest_pos := Vector3(-0.25, -0.2, -0.4) ## Left arm rest position
@export var right_rest_pos := Vector3(0.25, -0.2, -0.4) ## Right arm rest position

# --- STATE ---
var left_target_pos := Vector3.ZERO
var right_target_pos := Vector3.ZERO
var left_visible := false
var right_visible := false

# Hand state for gameplay
var left_hand_open := false
var right_hand_open := false
var left_pointing := false
var right_pointing := false
var left_fist := false
var right_fist := false

func _ready():
	# Arms should already exist in the scene
	if not left_arm:
		push_warning("Arms: LeftArm node not found - add it to the scene")
	if not right_arm:
		push_warning("Arms: RightArm node not found - add it to the scene")
	
	# Set initial positions
	if left_arm:
		left_arm.position = left_rest_pos
		left_target_pos = left_rest_pos
	if right_arm:
		right_arm.position = right_rest_pos
		right_target_pos = right_rest_pos

func _process(_delta: float):
	# Smoothly interpolate arm positions
	if left_arm:
		if left_visible:
			left_arm.position = left_arm.position.lerp(left_target_pos, position_smoothing)
			left_arm.visible = true
		else:
			# Return to rest position when not tracked
			left_arm.position = left_arm.position.lerp(left_rest_pos, position_smoothing * 0.5)
			# Hide and reset state if completely lost tracking for a bit (simulate immediate loss for now)
			left_arm.visible = false
			left_pointing = false
			left_fist = false
			left_hand_open = false
			_check_state_changes()
	
	if right_arm:
		if right_visible:
			right_arm.position = right_arm.position.lerp(right_target_pos, position_smoothing)
			right_arm.visible = true
		else:
			right_arm.position = right_arm.position.lerp(right_rest_pos, position_smoothing * 0.5)
			right_arm.visible = false
			right_pointing = false
			right_fist = false
			right_hand_open = false
			_check_state_changes()

func update_from_vision_data(data: Dictionary):
	"""Called from Player.gd with vision tracking data."""
	
	# Left hand
	left_visible = data.get("has_left_hand", false)
	if left_visible and data.has("left_hand"):
		var hand = data["left_hand"]
		left_target_pos = _hand_data_to_position(hand, true)
		left_hand_open = hand.get("is_open", false)
		left_pointing = hand.get("is_pointing", false)
		left_fist = hand.get("is_closed", false) # Use is_closed instead of is_fist
		_update_hand_visual(left_arm, left_hand_open, left_pointing, left_fist)
	
	# Right hand
	right_visible = data.get("has_right_hand", false)
	if right_visible and data.has("right_hand"):
		var hand = data["right_hand"]
		right_target_pos = _hand_data_to_position(hand, false)
		right_hand_open = hand.get("is_open", false)
		right_pointing = hand.get("is_pointing", false)
		right_fist = hand.get("is_closed", false) # Use is_closed instead of is_fist
		_update_hand_visual(right_arm, right_hand_open, right_pointing, right_fist)
	
	# Check for state changes and emit signals
	_check_state_changes()

func _hand_data_to_position(hand_data: Dictionary, is_left: bool) -> Vector3:
	"""Convert vision hand data to local 3D position."""
	var palm = hand_data.get("palm", {"x": 0.0, "y": 0.0, "z": 0.0})
	
	# Vision data is -1 to 1, convert to world position
	# X: left/right (flip for mirroring)
	# Y: up/down (flip because screen Y is inverted)
	# Z: depth (forward/back)
	
	var x = palm.get("x", 0.0) * horizontal_range
	var y = - palm.get("y", 0.0) * vertical_range # Flip Y
	var z = - arm_distance + palm.get("z", 0.0) * depth_range
	
	# Offset based on which hand
	if is_left:
		x -= 0.1 # Offset left
	else:
		x += 0.1 # Offset right
	
	return Vector3(x, y, z)

func _update_hand_visual(arm: Node3D, is_open: bool, is_pointing: bool, is_fist: bool):
	"""Update hand visual based on state (for future: animate fingers)."""
	if not arm:
		return
	
	var hand = arm.get_node_or_null("Hand")
	if hand and hand is MeshInstance3D:
		var mat = hand.material_override as StandardMaterial3D
		if mat:
			if is_pointing:
				mat.albedo_color = Color(0.2, 1.0, 0.4) # Green when pointing (drawing mode)
			elif is_fist:
				mat.albedo_color = Color(1.0, 0.5, 0.2) # Orange when fist
			elif is_open:
				mat.albedo_color = Color(0.8, 0.6, 0.5) # Normal skin tone
			else:
				mat.albedo_color = Color(0.7, 0.55, 0.45) # Slightly darker when closed

# --- SIGNALS FOR GESTURE SYSTEM ---
signal hand_pointing_started(is_left: bool)
signal hand_pointing_ended(is_left: bool)
signal hand_fist_started(is_left: bool)
signal hand_fist_ended(is_left: bool)
signal hand_opened(is_left: bool)
signal hand_closed(is_left: bool)

var _prev_left_pointing := false
var _prev_right_pointing := false
var _prev_left_fist := false
var _prev_right_fist := false
var _prev_left_open := false
var _prev_right_open := false

func _check_state_changes():
	"""Emit signals when hand state changes (for gesture/spell system)."""
	# Left hand pointing
	if left_pointing and not _prev_left_pointing:
		hand_pointing_started.emit(true)
	elif not left_pointing and _prev_left_pointing:
		hand_pointing_ended.emit(true)
	
	# Right hand pointing
	if right_pointing and not _prev_right_pointing:
		hand_pointing_started.emit(false)
	elif not right_pointing and _prev_right_pointing:
		hand_pointing_ended.emit(false)
	
	# Left hand fist
	if left_fist and not _prev_left_fist:
		hand_fist_started.emit(true)
	elif not left_fist and _prev_left_fist:
		hand_fist_ended.emit(true)
	
	# Right hand fist
	if right_fist and not _prev_right_fist:
		hand_fist_started.emit(false)
	elif not right_fist and _prev_right_fist:
		hand_fist_ended.emit(false)
	
	# Left hand open/close
	if left_hand_open and not _prev_left_open:
		hand_opened.emit(true)
	elif not left_hand_open and _prev_left_open:
		hand_closed.emit(true)
	
	# Right hand open/close
	if right_hand_open and not _prev_right_open:
		hand_opened.emit(false)
	elif not right_hand_open and _prev_right_open:
		hand_closed.emit(false)
	
	# Store previous state
	_prev_left_pointing = left_pointing
	_prev_right_pointing = right_pointing
	_prev_left_fist = left_fist
	_prev_right_fist = right_fist
	_prev_left_open = left_hand_open
	_prev_right_open = right_hand_open
