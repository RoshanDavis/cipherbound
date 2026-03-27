extends Node3D
class_name EnemySpawner
## EnemySpawner - Handles wave-based enemy spawning with configurable waves.
## Place in the game scene and configure spawn points and wave data.

# --- SIGNALS ---
signal wave_started(wave_number: int, enemy_count: int)
signal wave_completed(wave_number: int)
signal all_waves_completed()
signal enemy_spawned(enemy: Node)

# --- WAVE CONFIGURATION ---
## Define each wave's composition
@export var waves: Array[WaveData] = []

## Enemy scene preloads
@export_group("Enemy Scenes")
@export var slime_scene: PackedScene
@export var enemy_scenes: Dictionary = {}  ## Name -> PackedScene for custom enemies

@export_group("Spawn Settings")
@export var spawn_radius := 15.0  ## How far from center to spawn
@export var spawn_height := 1.0  ## Height offset for spawning
@export var spawn_delay := 0.5  ## Delay between each enemy spawn
@export var wave_delay := 3.0  ## Delay between waves
@export var auto_start := false  ## Start spawning automatically

@export_group("Spawn Points")
@export var use_spawn_markers := true  ## Use child Marker3D nodes as spawn points
@export var spawn_around_player := false  ## Spawn relative to player position

# --- INTERNAL STATE ---
var current_wave := 0
var enemies_spawned := 0
var enemies_alive := 0
var is_spawning := false
var spawn_points: Array[Vector3] = []
var player: Node3D = null

func _ready() -> void:
	_collect_spawn_points()
	_find_player()
	_setup_default_waves()
	
	if auto_start:
		call_deferred("start_waves")
	elif has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		if gm.game_state == gm.GameState.PLAYING:
			call_deferred("start_waves")

func _setup_default_waves() -> void:
	"""Create default waves if none configured."""
	if waves.size() == 0:
		# Create some default waves
		for i in range(5):
			var wave := WaveData.new()
			wave.enemy_count = 3 + (i * 2)  # 3, 5, 7, 9, 11
			wave.enemy_type = "slime"
			wave.spawn_interval = maxf(0.3, 0.5 - (i * 0.05))
			waves.append(wave)

func _collect_spawn_points() -> void:
	"""Collect spawn points from child Marker3D nodes."""
	spawn_points.clear()
	
	if use_spawn_markers:
		for child in get_children():
			if child is Marker3D:
				spawn_points.append(child.global_position)
	
	# If no markers, generate points in a circle
	if spawn_points.size() == 0:
		for i in range(8):
			var angle := (i / 8.0) * TAU
			var point := Vector3(
				cos(angle) * spawn_radius,
				spawn_height,
				sin(angle) * spawn_radius
			)
			spawn_points.append(global_position + point)

func _find_player() -> void:
	"""Find the player node."""
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

# --- PUBLIC API ---
func start_waves() -> void:
	"""Begin spawning waves."""
	if is_spawning:
		return
	
	current_wave = 0
	is_spawning = true
	_start_next_wave()

func stop_waves() -> void:
	"""Stop spawning and clear state."""
	is_spawning = false

func spawn_wave(wave_index: int) -> void:
	"""Manually spawn a specific wave."""
	if wave_index >= 0 and wave_index < waves.size():
		current_wave = wave_index
		_spawn_wave(waves[wave_index])

func spawn_enemy_at(enemy_type: String, spawn_position: Vector3) -> Node:
	"""Manually spawn a single enemy at a position."""
	var enemy := _create_enemy(enemy_type)
	if enemy:
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_position
		_connect_enemy_signals(enemy)
		enemy_spawned.emit(enemy)
		enemies_alive += 1
		return enemy
	return null

func get_alive_count() -> int:
	return enemies_alive

# --- WAVE MANAGEMENT ---
func _start_next_wave() -> void:
	if not is_spawning:
		return
	
	if current_wave >= waves.size():
		all_waves_completed.emit()
		is_spawning = false
		return
	
	var wave_data := waves[current_wave]
	_spawn_wave(wave_data)
	current_wave += 1

func _spawn_wave(wave_data: WaveData) -> void:
	var wave_number := current_wave + 1
	wave_started.emit(wave_number, wave_data.enemy_count)
	
	# Notify GameManager
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		gm.start_wave(wave_number, wave_data.enemy_count)
	
	enemies_spawned = 0
	
	# Spawn enemies with delay
	for i in range(wave_data.enemy_count):
		await get_tree().create_timer(wave_data.spawn_interval).timeout
		if not is_spawning:
			return
		_spawn_single_enemy(wave_data.enemy_type)
		enemies_spawned += 1

func _spawn_single_enemy(enemy_type: String) -> void:
	var spawn_pos := _get_spawn_position()
	var enemy := _create_enemy(enemy_type)
	
	if enemy:
		get_tree().current_scene.add_child(enemy)
		enemy.global_position = spawn_pos
		_connect_enemy_signals(enemy)
		enemy_spawned.emit(enemy)
		enemies_alive += 1

func _create_enemy(enemy_type: String) -> Node:
	var scene: PackedScene = null
	
	match enemy_type:
		"slime":
			scene = slime_scene if slime_scene else load("res://scenes/enemies/slime.tscn")
		_:
			if enemy_scenes.has(enemy_type):
				scene = enemy_scenes[enemy_type]
			else:
				push_warning("Unknown enemy type: " + enemy_type)
				return null
	
	if scene:
		return scene.instantiate()
	return null

func _get_spawn_position() -> Vector3:
	if spawn_around_player and player:
		# Spawn in a ring around the player
		var angle := randf() * TAU
		var distance := randf_range(spawn_radius * 0.7, spawn_radius)
		return player.global_position + Vector3(
			cos(angle) * distance,
			spawn_height,
			sin(angle) * distance
		)
	elif spawn_points.size() > 0:
		# Use a random spawn point with some variation
		var base_point := spawn_points[randi() % spawn_points.size()]
		return base_point + Vector3(
			randf_range(-2, 2),
			0,
			randf_range(-2, 2)
		)
	else:
		# Fallback: spawn at spawner position
		return global_position + Vector3(
			randf_range(-spawn_radius, spawn_radius),
			spawn_height,
			randf_range(-spawn_radius, spawn_radius)
		)

func _connect_enemy_signals(enemy: Node) -> void:
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)

func _on_enemy_died(_enemy: Node) -> void:
	enemies_alive -= 1
	
	# Check if wave is complete
	if enemies_alive <= 0 and enemies_spawned >= (waves[current_wave - 1].enemy_count if current_wave > 0 else 0):
		wave_completed.emit(current_wave)
		
		# Start next wave after delay
		if is_spawning:
			await get_tree().create_timer(wave_delay).timeout
			_start_next_wave()


## WaveData - Configuration for a single wave
class WaveData:
	extends Resource
	
	@export var enemy_count := 5
	@export var enemy_type := "slime"
	@export var spawn_interval := 0.5  ## Time between spawns
	@export var bonus_enemies: Array[String] = []  ## Additional enemy types to mix in
