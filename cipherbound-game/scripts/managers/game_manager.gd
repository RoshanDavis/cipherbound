extends Node
## GameManager - Singleton for game state, player stats, and wave tracking.
## Autoload as "GameManager" in Project Settings.

# --- PLAYER STATS ---
@export_group("Player Stats")
@export var max_health := 100.0
@export var max_mana := 100.0
@export var mana_regen_rate := 5.0  ## Mana per second
@export var mana_cost_default := 10.0  ## Default spell cost

var current_health: float
var current_mana: float

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
var game_state: GameState = GameState.PLAYING

# --- SIGNALS ---
signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal wave_started(wave_number: int, enemy_count: int)
signal wave_completed(wave_number: int)
signal enemy_killed(enemy: Node, points: int)
signal score_changed(new_score: int)
signal game_over(victory: bool)
signal game_state_changed(new_state: GameState)

func _ready() -> void:
	reset_stats()
	print("GameManager initialized")

func _process(delta: float) -> void:
	if game_state == GameState.PLAYING:
		_regenerate_mana(delta)

# --- STAT MANAGEMENT ---
func reset_stats() -> void:
	"""Reset all player stats to starting values."""
	current_health = max_health
	current_mana = max_mana
	current_wave = 0
	enemies_remaining = 0
	total_enemies_killed = 0
	score = 0
	is_wave_active = false
	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)
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

func use_mana(amount: float) -> bool:
	"""Attempt to use mana. Returns true if successful."""
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, max_mana)
		return true
	return false

func restore_mana(amount: float) -> void:
	"""Restore mana to the player."""
	current_mana = minf(max_mana, current_mana + amount)
	mana_changed.emit(current_mana, max_mana)

func _regenerate_mana(delta: float) -> void:
	"""Regenerate mana over time."""
	if current_mana < max_mana:
		current_mana = minf(max_mana, current_mana + mana_regen_rate * delta)
		mana_changed.emit(current_mana, max_mana)

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
				get_tree().paused = true

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

# --- SPELL INTEGRATION ---
func get_spell_mana_cost(_spell_name: String) -> float:
	"""Get mana cost for a spell. Override in spell_registry if needed."""
	# Default cost, can be extended to read from SpellManager
	return mana_cost_default

func can_cast_spell(spell_name: String) -> bool:
	"""Check if player has enough mana to cast a spell."""
	return current_mana >= get_spell_mana_cost(spell_name)
