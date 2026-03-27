extends Node
## SceneManager - Singleton for scene transitions and loading.
## Autoload as "SceneManager" in Project Settings.

# --- CONFIGURATION ---
@export_group("Transitions")
@export var default_fade_duration := 0.5
@export var fade_color := Color.BLACK

# --- SCENE PATHS ---
const SCENES := {
	"main_menu": "res://scenes/main_menu.tscn",
	"game": "res://scenes/game.tscn",
	"game_over": "res://scenes/game_over.tscn",
}

# --- INTERNAL ---
var _transition_layer: CanvasLayer
var _fade_rect: ColorRect
var _is_transitioning := false
var _current_scene_path := ""

# --- SIGNALS ---
signal transition_started
signal transition_midpoint  ## Emitted when fade is complete, before new scene loads
signal transition_completed
signal scene_loaded(scene_path: String)

func _ready() -> void:
	_setup_transition_layer()
	process_mode = Node.PROCESS_MODE_ALWAYS  # Work even when paused
	print("SceneManager initialized")

func _setup_transition_layer() -> void:
	"""Create the transition overlay."""
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = 100  # Above everything
	add_child(_transition_layer)
	
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.add_child(_fade_rect)

# --- PUBLIC API ---

## Change to a scene by key (from SCENES dictionary)
func change_scene(scene_key: String, fade_duration: float = -1.0) -> void:
	if not SCENES.has(scene_key):
		push_error("SceneManager: Unknown scene key: ", scene_key)
		return
	change_scene_to_file(SCENES[scene_key], fade_duration)

## Change to a scene by file path
func change_scene_to_file(scene_path: String, fade_duration: float = -1.0) -> void:
	if _is_transitioning:
		push_warning("SceneManager: Transition already in progress")
		return
	
	if fade_duration < 0:
		fade_duration = default_fade_duration
	
	_is_transitioning = true
	_current_scene_path = scene_path
	transition_started.emit()
	
	if fade_duration > 0:
		await _fade_out(fade_duration)
	
	transition_midpoint.emit()
	
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneManager: Failed to load scene: ", scene_path)
		_is_transitioning = false
		return
	
	# Wait a frame for scene to initialize
	await get_tree().process_frame
	
	scene_loaded.emit(scene_path)
	
	if fade_duration > 0:
		await _fade_in(fade_duration)
	
	_is_transitioning = false
	transition_completed.emit()

## Reload the current scene
func reload_current_scene(fade_duration: float = -1.0) -> void:
	if _is_transitioning:
		return
	
	if fade_duration < 0:
		fade_duration = default_fade_duration
	
	_is_transitioning = true
	transition_started.emit()
	
	if fade_duration > 0:
		await _fade_out(fade_duration)
	
	transition_midpoint.emit()
	get_tree().reload_current_scene()
	
	await get_tree().process_frame
	
	if fade_duration > 0:
		await _fade_in(fade_duration)
	
	_is_transitioning = false
	transition_completed.emit()

## Quit the game
func quit_game(fade_duration: float = 0.5) -> void:
	if fade_duration > 0:
		await _fade_out(fade_duration)
	get_tree().quit()

## Go to main menu
func go_to_main_menu() -> void:
	if SCENES.has("main_menu"):
		change_scene("main_menu")
	else:
		push_warning("SceneManager: main_menu scene not configured")

## Go to game scene
func start_game() -> void:
	if SCENES.has("game"):
		change_scene("game")
	else:
		push_warning("SceneManager: game scene not configured")

## Simple fade to black and back (for effect)
func fade_flash(duration: float = 0.3) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	await _fade_out(duration * 0.5)
	await _fade_in(duration * 0.5)
	_is_transitioning = false

# --- FADE HELPERS ---
func _fade_out(duration: float) -> void:
	"""Fade to black."""
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, duration)
	await tween.finished

func _fade_in(duration: float) -> void:
	"""Fade from black."""
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, duration)
	await tween.finished

## Check if currently transitioning
func is_transitioning() -> bool:
	return _is_transitioning

## Get the last loaded scene path
func get_current_scene_path() -> String:
	return _current_scene_path
