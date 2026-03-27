extends Node
## AudioManager - Singleton for sound effects and music playback.
## Autoload as "AudioManager" in Project Settings.

# --- CONFIGURATION ---
@export_group("Audio Settings")
@export_range(0.0, 1.0) var master_volume := 1.0
@export_range(0.0, 1.0) var sfx_volume := 1.0
@export_range(0.0, 1.0) var music_volume := 0.7
@export var sfx_pool_size := 8  ## Number of concurrent SFX players

# --- AUDIO BUSES ---
const BUS_MASTER := "Master"
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"

# --- SFX LIBRARY ---
## Preload sound effects here or load dynamically
var sfx_library: Dictionary = {
	# UI sounds
	"ui_click": null,
	"ui_hover": null,
	
	# Combat sounds
	"spell_cast": null,
	"spell_hit": null,
	"enemy_hit": null,
	"enemy_death": null,
	"player_hit": null,
	"player_death": null,
	
	# Movement sounds
	"footstep": null,
	"jump": null,
	"land": null,
	"dash": null,
	
	# Spell-specific sounds
	"air_blast": null,
	"shield": null,
	"lightning": null,
	"ground_slam": null,
}

# --- MUSIC TRACKS ---
var music_library: Dictionary = {
	"menu": null,
	"gameplay": null,
	"boss": null,
	"victory": null,
	"game_over": null,
}

# --- INTERNAL ---
var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _sfx_index := 0
var _current_music_track := ""

func _ready() -> void:
	_setup_audio_buses()
	_setup_music_player()
	_setup_sfx_pool()
	print("AudioManager initialized with ", sfx_pool_size, " SFX channels")

func _setup_audio_buses() -> void:
	"""Ensure audio buses exist. Create them if needed."""
	# Note: Audio buses should be configured in Godot's Audio tab
	# This just applies initial volumes
	_apply_volumes()

func _setup_music_player() -> void:
	"""Create the music player."""
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)

func _setup_sfx_pool() -> void:
	"""Create a pool of 3D audio players for spatial sound effects."""
	for i in sfx_pool_size:
		var player := AudioStreamPlayer3D.new()
		player.name = "SFXPlayer" + str(i)
		player.bus = BUS_SFX
		player.max_distance = 50.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_sfx_pool.append(player)

func _apply_volumes() -> void:
	"""Apply volume settings to audio buses."""
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	var sfx_idx := AudioServer.get_bus_index(BUS_SFX)
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))

# --- PUBLIC API ---

## Play a sound effect at a 3D position
func play_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO, pitch_variation: float = 0.0) -> void:
	var stream: AudioStream = sfx_library.get(sfx_name)
	if not stream:
		push_warning("AudioManager: SFX not found: ", sfx_name)
		return
	
	var player := _get_available_sfx_player()
	if player:
		player.stream = stream
		player.global_position = position
		player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
		player.play()

## Play a 2D (non-positional) sound effect
func play_sfx_2d(sfx_name: String, pitch_variation: float = 0.0) -> void:
	var stream: AudioStream = sfx_library.get(sfx_name)
	if not stream:
		push_warning("AudioManager: SFX not found: ", sfx_name)
		return
	
	# Use a temporary AudioStreamPlayer for 2D sounds
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

## Play music track (with optional crossfade)
func play_music(track_name: String, crossfade_duration: float = 1.0) -> void:
	if track_name == _current_music_track and _music_player.playing:
		return
	
	var stream: AudioStream = music_library.get(track_name)
	if not stream:
		push_warning("AudioManager: Music track not found: ", track_name)
		return
	
	_current_music_track = track_name
	
	if crossfade_duration > 0 and _music_player.playing:
		# Fade out current, then play new
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -40.0, crossfade_duration)
		tween.tween_callback(_start_new_music.bind(stream))
	else:
		_start_new_music(stream)

func _start_new_music(stream: AudioStream) -> void:
	_music_player.stream = stream
	_music_player.volume_db = 0.0
	_music_player.play()

## Stop music (with optional fade)
func stop_music(fade_duration: float = 1.0) -> void:
	if not _music_player.playing:
		return
	
	_current_music_track = ""
	
	if fade_duration > 0:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -40.0, fade_duration)
		tween.tween_callback(_music_player.stop)
	else:
		_music_player.stop()

## Pause/resume music
func pause_music() -> void:
	_music_player.stream_paused = true

func resume_music() -> void:
	_music_player.stream_paused = false

## Set volumes (0.0 to 1.0)
func set_master_volume(volume: float) -> void:
	master_volume = clampf(volume, 0.0, 1.0)
	_apply_volumes()

func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)
	_apply_volumes()

func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	_apply_volumes()

## Register a sound effect at runtime
func register_sfx(sfx_name: String, stream: AudioStream) -> void:
	sfx_library[sfx_name] = stream

## Register a music track at runtime
func register_music(track_name: String, stream: AudioStream) -> void:
	music_library[track_name] = stream

# --- INTERNAL ---
func _get_available_sfx_player() -> AudioStreamPlayer3D:
	"""Get next available SFX player using round-robin."""
	var player := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % sfx_pool_size
	return player

func _on_music_finished() -> void:
	"""Handle music track completion - loop by default."""
	if _current_music_track != "" and music_library.has(_current_music_track):
		_music_player.play()
