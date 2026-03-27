extends CharacterBody3D
class_name BaseEnemy
## BaseEnemy - Base class for all enemies with health, AI states, and combat.
## Extend this class to create specific enemy types.

# --- SIGNALS ---
signal health_changed(current: float, maximum: float)
signal died(enemy: Node)
signal attacked(target: Node)

# --- ENUMS ---
enum AIState { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD }

# --- EXPORTS ---
@export_group("Stats")
@export var max_health := 30.0
@export var move_speed := 3.0
@export var chase_speed := 5.0
@export var attack_damage := 10.0
@export var attack_range := 2.0
@export var detection_range := 10.0
@export var attack_cooldown := 1.5
@export var score_value := 100

@export_group("Combat")
@export var knockback_resistance := 0.0  ## 0 = full knockback, 1 = immune
@export var hurt_duration := 0.3

@export_group("Navigation")
@export var patrol_points: Array[Vector3] = []
@export var patrol_wait_time := 2.0
@export var path_update_interval := 0.25

@export_group("Visual")
@export var mesh_color := Color(0.4, 0.8, 0.3)  ## Default green slime color
@export var hurt_flash_color := Color(1.0, 0.3, 0.3)

# --- INTERNAL STATE ---
var current_health := max_health
var current_state := AIState.IDLE
var target: Node3D = null
var attack_timer := 0.0
var hurt_timer := 0.0
var patrol_index := 0
var patrol_wait_timer := 0.0
var path_timer := 0.0
var _knockback_velocity := Vector3.ZERO

# --- NODE REFERENCES (override in derived classes if different) ---
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision_shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var detection_area: Area3D = $DetectionArea if has_node("DetectionArea") else null
@onready var attack_area: Area3D = $AttackArea if has_node("AttackArea") else null

func _ready() -> void:
	current_health = max_health
	_setup_detection()
	_setup_navigation()
	_apply_mesh_color()
	
	# Register with GameManager
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		if gm.has_method("register_enemy"):
			gm.register_enemy(self)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	
	# State machine
	match current_state:
		AIState.IDLE:
			_state_idle(delta)
		AIState.PATROL:
			_state_patrol(delta)
		AIState.CHASE:
			_state_chase(delta)
		AIState.ATTACK:
			_state_attack(delta)
		AIState.HURT:
			_state_hurt(delta)
		AIState.DEAD:
			return
	
	# Apply knockback decay
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 10.0 * delta)
	velocity.x += _knockback_velocity.x
	velocity.z += _knockback_velocity.z
	
	move_and_slide()

# --- STATE MACHINE ---
func _state_idle(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	
	# Check for player
	if _can_see_target():
		_change_state(AIState.CHASE)
	elif patrol_points.size() > 0:
		patrol_wait_timer += delta
		if patrol_wait_timer >= patrol_wait_time:
			patrol_wait_timer = 0.0
			_change_state(AIState.PATROL)

func _state_patrol(_delta: float) -> void:
	if patrol_points.size() == 0:
		_change_state(AIState.IDLE)
		return
	
	# Check for player
	if _can_see_target():
		_change_state(AIState.CHASE)
		return
	
	var target_pos := global_position + patrol_points[patrol_index]
	var direction := (target_pos - global_position).normalized()
	direction.y = 0
	
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	# Look at movement direction
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)
	
	# Check if reached patrol point
	var distance := global_position.distance_to(target_pos)
	if distance < 1.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		_change_state(AIState.IDLE)

func _state_chase(delta: float) -> void:
	if not target or not is_instance_valid(target):
		target = _find_player()
		if not target:
			_change_state(AIState.IDLE)
			return
	
	var distance := global_position.distance_to(target.global_position)
	
	# Check if target out of range
	if distance > detection_range * 1.5:
		target = null
		_change_state(AIState.IDLE)
		return
	
	# Check if in attack range
	if distance <= attack_range:
		_change_state(AIState.ATTACK)
		return
	
	# Update navigation path
	path_timer += delta
	if path_timer >= path_update_interval and nav_agent:
		path_timer = 0.0
		nav_agent.target_position = target.global_position
	
	# Move towards target
	var direction: Vector3
	if nav_agent and nav_agent.is_navigation_finished() == false:
		var next_pos := nav_agent.get_next_path_position()
		direction = (next_pos - global_position).normalized()
	else:
		direction = (target.global_position - global_position).normalized()
	
	direction.y = 0
	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed
	
	# Face target
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)

func _state_attack(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	
	attack_timer += delta
	
	if attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_perform_attack()
		
		# Check if should continue chasing or stay attacking
		if target and is_instance_valid(target):
			var distance := global_position.distance_to(target.global_position)
			if distance > attack_range:
				_change_state(AIState.CHASE)

func _state_hurt(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	
	hurt_timer -= delta
	if hurt_timer <= 0:
		_apply_mesh_color()
		if current_health > 0:
			_change_state(AIState.CHASE)

func _change_state(new_state: AIState) -> void:
	current_state = new_state

# --- COMBAT ---
func take_damage(amount: float, source: Node3D = null, knockback_force := Vector3.ZERO) -> void:
	if current_state == AIState.DEAD:
		return
	
	current_health = maxf(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	
	# Apply knockback
	if knockback_force != Vector3.ZERO:
		var kb := knockback_force * (1.0 - knockback_resistance)
		_knockback_velocity = kb
	
	# Flash hurt color
	if mesh_instance:
		var mat := mesh_instance.get_active_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color = hurt_flash_color
	
	# Set target to attacker
	if source and source.is_in_group("player"):
		target = source
	
	if current_health <= 0:
		_die()
	else:
		hurt_timer = hurt_duration
		_change_state(AIState.HURT)

func _perform_attack() -> void:
	if not target or not is_instance_valid(target):
		return
	
	attacked.emit(target)
	
	# Deal damage if target has method
	if target.has_method("take_damage"):
		target.take_damage(attack_damage)
	elif has_node("/root/GameManager"):
		# Fallback: damage player through GameManager
		var gm = get_node("/root/GameManager")
		gm.take_damage(attack_damage)

func _die() -> void:
	_change_state(AIState.DEAD)
	died.emit(self)
	
	# Notify GameManager
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		gm.register_enemy_death(self, score_value)
	
	# Death animation/effects would go here
	# For now, just queue free after a delay
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)

# --- DETECTION ---
func _setup_detection() -> void:
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)

func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		target = body

func _on_detection_body_exited(body: Node3D) -> void:
	if body == target:
		# Keep chasing for a bit before losing target
		pass

func _can_see_target() -> bool:
	if not target or not is_instance_valid(target):
		target = _find_player()
	
	if target:
		var distance := global_position.distance_to(target.global_position)
		return distance <= detection_range
	return false

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null

# --- NAVIGATION ---
func _setup_navigation() -> void:
	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.avoidance_enabled = true

# --- VISUAL ---
func _apply_mesh_color() -> void:
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mesh_color
		mesh_instance.material_override = mat
