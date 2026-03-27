extends Node
## GameManager - Singleton for game state, player stats, and wave tracking.
## Autoload as "GameManager" in Project Settings.

# --- PLAYER STATS ---
@export_group("Player Stats")
@export var max_health := 100.0

var current_health: float

# --- WAVE SYSTEM ---
@export_group("Wave System")
@export var starting_wave := 1

var current_wave := 0
var enemies_remaining := 0
var total_enemies_killed := 0
var score := 0
var is_wave_active := false

# --- GAME STATE ---
enum GameState { MENU, PLAYING, PAUSED, GAME_OVER, VICTORY }
var game_state: GameState = GameState.MENU

# --- SIGNALS ---
signal health_changed(current: float, maximum: float)
signal wave_started(wave_number: int, enemy_count: int)
signal wave_completed(wave_number: int)
signal enemy_killed(enemy: Node, points: int)
signal score_changed(new_score: int)
signal game_over(victory: bool)
signal game_state_changed(new_state: GameState)

func _ready() -> void:
	reset_stats()
	print("GameManager initialized")

# --- STAT MANAGEMENT ---
func reset_stats() -> void:
	"""Reset all player stats to starting values."""
	current_health = max_health
	current_wave = 0
	enemies_remaining = 0
	total_enemies_killed = 0
	score = 0
	is_wave_active = false
	health_changed.emit(current_health, max_health)
	score_changed.emit(score)

func take_damage(amount: float) -> void:
	"""Player takes damage. Triggers game over if health reaches 0."""
	if game_state != GameState.PLAYING:
		return
	
	current_health = maxf(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_trigger_game_over(false)

func heal(amount: float) -> void:
	"""Heal the player."""
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

# --- WAVE MANAGEMENT ---
func start_wave(wave_number: int, enemy_count: int) -> void:
	"""Called by EnemySpawner when a wave begins."""
	current_wave = wave_number
	enemies_remaining = enemy_count
	is_wave_active = true
	wave_started.emit(wave_number, enemy_count)
	print("Wave ", wave_number, " started with ", enemy_count, " enemies")

func register_enemy_death(enemy: Node, points: int = 100) -> void:
	"""Called when an enemy dies."""
	enemies_remaining = maxi(0, enemies_remaining - 1)
	total_enemies_killed += 1
	add_score(points)
	enemy_killed.emit(enemy, points)
	
	if enemies_remaining <= 0 and is_wave_active:
		_complete_wave()

func _complete_wave() -> void:
	"""Called when all enemies in a wave are defeated."""
	is_wave_active = false
	wave_completed.emit(current_wave)
	print("Wave ", current_wave, " completed!")

# --- SCORE ---
func add_score(points: int) -> void:
	"""Add points to score."""
	score += points
	score_changed.emit(score)

# --- GAME STATE ---
func start_game() -> void:
	"""Start the game from menu state."""
	reset_stats()
	set_game_state(GameState.PLAYING)

func set_game_state(new_state: GameState) -> void:
	"""Change game state."""
	if game_state != new_state:
		game_state = new_state
		game_state_changed.emit(new_state)
		
		match new_state:
			GameState.PAUSED:
				get_tree().paused = true
			GameState.PLAYING:
				get_tree().paused = false
			GameState.GAME_OVER, GameState.VICTORY:
				pass  # Don't pause — let death screen handle it

func pause_game() -> void:
	set_game_state(GameState.PAUSED)

func resume_game() -> void:
	set_game_state(GameState.PLAYING)

func _trigger_game_over(victory: bool) -> void:
	"""Trigger game over state."""
	set_game_state(GameState.VICTORY if victory else GameState.GAME_OVER)
	game_over.emit(victory)

func restart_game() -> void:
	"""Restart the game."""
	reset_stats()
	set_game_state(GameState.PLAYING)
	get_tree().reload_current_scene()
