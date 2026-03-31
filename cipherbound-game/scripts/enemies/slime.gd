extends CharacterBody3D
## Simple Slime enemy.
## Wanders randomly, chases the player when detected, and deals contact damage.

# --- CONFIGURATION ---
signal died(enemy: Node)

@export_group("Movement")
@export var wander_speed := 2.0       ## Speed while wandering
@export var chase_speed := 4.5        ## Speed while chasing
@export var rotation_speed := 5.0     ## How fast the slime turns

@export_group("Wander")
@export var wander_radius := 6.0      ## Max distance for random wander points
@export var wander_pause_min := 1.0   ## Min seconds to pause between wanders
@export var wander_pause_max := 3.0   ## Max seconds to pause between wanders

@export_group("Combat")
@export var contact_damage := 10.0    ## Damage dealt on contact per tick
@export var damage_cooldown := 1.0    ## Seconds between damage ticks
@export var detection_range := 10.0   ## Range to detect the player (overrides DetectionArea radius)

@export_group("Stats")
@export var max_health := 30.0
@export var mesh_color := Color(0.3, 0.52, 1.0, 1.0)

# --- STATE ---
enum State { IDLE, WANDER, CHASE }
var state := State.IDLE
var target: CharacterBody3D = null
var wander_target := Vector3.ZERO
var spawn_position := Vector3.ZERO

var _damage_timer := 0.0
var _wander_pause_timer := 0.0
var _health: float

# --- ANIMATION ---
var _animation_time := 0.0
var _visual_nodes: Array[Dictionary] = []

# --- GRAVITY ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- REFERENCES ---
@onready var detection_area: Area3D = $DetectionArea
@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_health = max_health
	spawn_position = global_position
	
	# Apply color to the mesh
	if mesh and mesh.mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mesh_color
		mesh.material_override = mat
		
	# Store animation baselines for all mesh parts
	for child in get_children():
		if child is MeshInstance3D:
			_visual_nodes.append({
				"node": child,
				"orig_y": child.position.y,
				"base_scale": child.scale
			})
	
	# Connect detection area signals
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)
	
	# Start with a short pause before first wander
	_wander_pause_timer = randf_range(0.5, 1.5)
	state = State.IDLE

func _process(delta: float) -> void:
	if _visual_nodes.is_empty(): return
	
	_animation_time += delta
	var target_scale := Vector3.ONE
	var y_offset := 0.0
	
	match state:
		State.IDLE:
			# Gentle breathing
			var breath: float = sin(_animation_time * 2.0) * 0.1
			target_scale = Vector3(1.0 + breath, 1.0 - breath, 1.0 + breath)
		State.WANDER:
			# Slow bounce
			var bounce: float = absf(sin(_animation_time * wander_speed * 1.5))
			y_offset = bounce * 0.3
			target_scale = Vector3(1.0 - bounce * 0.2, 1.0 + bounce * 0.4, 1.0 - bounce * 0.2)
		State.CHASE:
			# Fast, more erratic bounce
			var bounce: float = absf(sin(_animation_time * chase_speed * 2.0))
			y_offset = bounce * 0.5
			target_scale = Vector3(1.0 - bounce * 0.3, 1.0 + bounce * 0.5, 1.0 - bounce * 0.3)
			
	# Lerp for smooth transitions and squish recovery on all parts
	for data in _visual_nodes:
		var node: MeshInstance3D = data["node"]
		var base_scale: Vector3 = data["base_scale"]
		var orig_y: float = data["orig_y"]
		node.scale = node.scale.lerp(target_scale * base_scale, delta * 15.0)
		node.position.y = lerpf(node.position.y, orig_y + y_offset, delta * 15.0)

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	match state:
		State.IDLE:
			_state_idle(delta)
		State.WANDER:
			_state_wander(delta)
		State.CHASE:
			_state_chase(delta)
	
	# Contact damage
	_update_contact_damage(delta)
	
	move_and_slide()

# ============================================================================
# STATES
# ============================================================================

func _state_idle(delta: float) -> void:
	"""Stand still for a moment, then pick a new wander target."""
	velocity.x = 0
	velocity.z = 0
	
	_wander_pause_timer -= delta
	if _wander_pause_timer <= 0:
		_pick_wander_target()
		state = State.WANDER

func _state_wander(delta: float) -> void:
	"""Move toward the random wander target."""
	var direction := (wander_target - global_position)
	direction.y = 0  # Stay on XZ plane
	
	var distance := direction.length()
	
	# Reached wander target — go idle
	if distance < 1.0:
		state = State.IDLE
		_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
		velocity.x = 0
		velocity.z = 0
		return
	
	direction = direction.normalized()
	velocity.x = direction.x * wander_speed
	velocity.z = direction.z * wander_speed
	
	# Smoothly face movement direction
	_face_direction(direction, delta)

func _state_chase(delta: float) -> void:
	"""Move toward the player at chase speed."""
	if not target or not is_instance_valid(target):
		target = _find_player()
		if not target:
			state = State.IDLE
			_wander_pause_timer = 1.0
			return
	
	# Check if player is still in range
	var distance := global_position.distance_to(target.global_position)
	if distance > detection_range * 1.5:
		target = null
		state = State.IDLE
		_wander_pause_timer = 1.0
		return
	
	var direction := (target.global_position - global_position)
	direction.y = 0
	
	if direction.length() > 0.3:
		direction = direction.normalized()
		velocity.x = direction.x * chase_speed
		velocity.z = direction.z * chase_speed
		_face_direction(direction, delta)
	else:
		velocity.x = 0
		velocity.z = 0

# ============================================================================
# DETECTION
# ============================================================================

func _on_body_entered_detection(body: Node3D) -> void:
	if body.is_in_group("player") and body is CharacterBody3D:
		target = body
		state = State.CHASE

func _on_body_exited_detection(body: Node3D) -> void:
	if body == target:
		# Keep chasing a bit beyond detection area (detection_range * 1.5)
		pass

func _find_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is CharacterBody3D:
		return players[0]
	return null

# ============================================================================
# CONTACT DAMAGE
# ============================================================================

func _update_contact_damage(delta: float) -> void:
	"""Deal damage to the player on contact (with cooldown)."""
	_damage_timer -= delta
	
	if _damage_timer > 0:
		return
	
	if not target or not is_instance_valid(target):
		return
	
	# Check if we're touching the player
	var distance := global_position.distance_to(target.global_position)
	if distance < 1.5:  # Contact range (roughly sum of collision radii)
		_damage_timer = damage_cooldown
		
		# Deal damage through GameManager
		if has_node("/root/GameManager"):
			var gm := get_node("/root/GameManager")
			gm.take_damage(contact_damage)
			print("Slime dealt ", contact_damage, " damage!")
		
		# Small knockback — push slime back slightly
		var knockback_dir := (global_position - target.global_position).normalized()
		velocity.x = knockback_dir.x * 3.0
		velocity.z = knockback_dir.z * 3.0

# ============================================================================
# HELPERS
# ============================================================================

func _pick_wander_target() -> void:
	"""Pick a random point near the spawn position."""
	var angle := randf() * TAU
	var dist := randf_range(2.0, wander_radius)
	wander_target = spawn_position + Vector3(
		cos(angle) * dist,
		0,
		sin(angle) * dist
	)

func _face_direction(direction: Vector3, delta: float) -> void:
	"""Smoothly rotate to face a direction."""
	if direction.length_squared() < 0.01:
		return
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

# ============================================================================
# HEALTH / DAMAGE RECEIVED
# ============================================================================

func take_damage(amount: float) -> void:
	"""Called when the slime takes damage from spells."""
	_health -= amount
	print("Slime took ", amount, " damage! HP: ", _health, "/", max_health)
	
	# Visual squish for all parts
	for data in _visual_nodes:
		var node: MeshInstance3D = data["node"]
		var base_scale: Vector3 = data["base_scale"]
		node.scale = Vector3(1.5, 0.4, 1.5) * base_scale
	
	if _health <= 0:
		_die()

func _die() -> void:
	"""Handle slime death."""
	# Notify GameManager
	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		if gm.has_method("register_enemy_death"):
			gm.register_enemy_death(self, 100)
	
	print("Slime defeated!")
	died.emit(self)
	queue_free()
