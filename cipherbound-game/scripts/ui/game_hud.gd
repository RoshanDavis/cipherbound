extends CanvasLayer
class_name GameHUD
## GameHUD - Main game UI with health/mana bars, wave info, cipher drawing, and spell feedback.
## Consolidates all UI functionality including the old CipherHUD.

# --- NODE REFERENCES ---
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthContainer/HealthLabel
@onready var mana_bar: ProgressBar = $MarginContainer/VBoxContainer/ManaContainer/ManaBar
@onready var mana_label: Label = $MarginContainer/VBoxContainer/ManaContainer/ManaLabel
@onready var wave_label: Label = $TopRight/WaveLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var spell_feedback: Label = $CenterContainer/SpellFeedback
@onready var cipher_canvas: Control = $CipherCanvas
@onready var status_label: Label = $StatusLabel

# --- CONFIGURATION ---
@export_group("Bar Settings")
@export var health_color := Color(0.8, 0.2, 0.2)  ## Red
@export var health_bg_color := Color(0.3, 0.1, 0.1)
@export var mana_color := Color(0.2, 0.4, 0.9)  ## Blue
@export var mana_bg_color := Color(0.1, 0.15, 0.3)
@export var bar_smooth_speed := 10.0  ## How fast bars animate

@export_group("Feedback")
@export var feedback_duration := 2.0
@export var feedback_fade_time := 0.5

@export_group("Cipher Drawing")
@export var trail_color := Color(0.3, 0.8, 1.0, 0.9)  ## Cyan glow
@export var trail_width := 4.0
@export var trail_fade_time := 1.5
@export var success_color := Color(0.2, 1.0, 0.4)  ## Green
@export var fail_color := Color(1.0, 0.3, 0.3)  ## Red

# --- INTERNAL STATE ---
var _target_health := 100.0
var _target_mana := 100.0
var _feedback_timer := 0.0

# --- CIPHER DRAWING STATE ---
var draw_points: Array[Vector2] = []
var beautified_points: Array[Vector2] = []
var is_showing_trail := false
var fade_timer := 0.0
var current_alpha := 1.0
var beautify_progress := 0.0
var is_beautifying := false
var _is_showing_result := false
const BEAUTIFY_DURATION := 0.3

# --- Reference for draw_canvas compatibility (Player.gd accesses this) ---
var draw_canvas: Control:
	get:
		return cipher_canvas

func _ready() -> void:
	_connect_signals()
	_setup_bars()
	_hide_feedback()
	_setup_cipher_canvas()
	print("GameHUD initialized")

func _process(delta: float) -> void:
	_update_bar_smoothing(delta)
	_update_feedback_fade(delta)
	_update_cipher_drawing(delta)

func _connect_signals() -> void:
	"""Connect to GameManager signals if it exists."""
	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		gm.health_changed.connect(_on_health_changed)
		gm.mana_changed.connect(_on_mana_changed)
		gm.wave_started.connect(_on_wave_started)
		gm.wave_completed.connect(_on_wave_completed)
		gm.score_changed.connect(_on_score_changed)
		gm.enemy_killed.connect(_on_enemy_killed)
		
		# Initialize with current values
		_on_health_changed(gm.current_health, gm.max_health)
		_on_mana_changed(gm.current_mana, gm.max_mana)
		_on_score_changed(gm.score)

func _setup_bars() -> void:
	"""Apply visual styling to progress bars."""
	if health_bar:
		var health_style := StyleBoxFlat.new()
		health_style.bg_color = health_color
		health_style.corner_radius_top_left = 4
		health_style.corner_radius_top_right = 4
		health_style.corner_radius_bottom_left = 4
		health_style.corner_radius_bottom_right = 4
		health_bar.add_theme_stylebox_override("fill", health_style)
		
		var health_bg := StyleBoxFlat.new()
		health_bg.bg_color = health_bg_color
		health_bg.corner_radius_top_left = 4
		health_bg.corner_radius_top_right = 4
		health_bg.corner_radius_bottom_left = 4
		health_bg.corner_radius_bottom_right = 4
		health_bar.add_theme_stylebox_override("background", health_bg)
	
	if mana_bar:
		var mana_style := StyleBoxFlat.new()
		mana_style.bg_color = mana_color
		mana_style.corner_radius_top_left = 4
		mana_style.corner_radius_top_right = 4
		mana_style.corner_radius_bottom_left = 4
		mana_style.corner_radius_bottom_right = 4
		mana_bar.add_theme_stylebox_override("fill", mana_style)
		
		var mana_bg := StyleBoxFlat.new()
		mana_bg.bg_color = mana_bg_color
		mana_bg.corner_radius_top_left = 4
		mana_bg.corner_radius_top_right = 4
		mana_bg.corner_radius_bottom_left = 4
		mana_bg.corner_radius_bottom_right = 4
		mana_bar.add_theme_stylebox_override("background", mana_bg)

func _setup_cipher_canvas() -> void:
	"""Setup cipher drawing canvas."""
	if cipher_canvas:
		cipher_canvas.draw.connect(_on_cipher_canvas_draw)

func _update_bar_smoothing(delta: float) -> void:
	"""Smoothly animate bar values."""
	if health_bar:
		health_bar.value = lerpf(health_bar.value, _target_health, bar_smooth_speed * delta)
	if mana_bar:
		mana_bar.value = lerpf(mana_bar.value, _target_mana, bar_smooth_speed * delta)

func _update_feedback_fade(delta: float) -> void:
	"""Fade out spell feedback over time."""
	if _feedback_timer > 0:
		_feedback_timer -= delta
		if _feedback_timer <= feedback_fade_time and spell_feedback:
			spell_feedback.modulate.a = _feedback_timer / feedback_fade_time
		if _feedback_timer <= 0:
			_hide_feedback()

func _hide_feedback() -> void:
	if spell_feedback:
		spell_feedback.visible = false

# --- SIGNAL HANDLERS ---
func _on_health_changed(current: float, maximum: float) -> void:
	_target_health = (current / maximum) * 100.0
	if health_bar:
		health_bar.max_value = 100.0
	if health_label:
		health_label.text = "%d / %d" % [int(current), int(maximum)]

func _on_mana_changed(current: float, maximum: float) -> void:
	_target_mana = (current / maximum) * 100.0
	if mana_bar:
		mana_bar.max_value = 100.0
	if mana_label:
		mana_label.text = "%d / %d" % [int(current), int(maximum)]

func _on_wave_started(wave_number: int, enemy_count: int) -> void:
	if wave_label:
		wave_label.text = "Wave %d" % wave_number
	show_feedback("Wave %d - %d Enemies!" % [wave_number, enemy_count])

func _on_wave_completed(wave_number: int) -> void:
	show_feedback("Wave %d Complete!" % wave_number)

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "Score: %d" % new_score

func _on_enemy_killed(_enemy: Node, _points: int) -> void:
	pass

# --- PUBLIC API: HEALTH/MANA ---
func show_feedback(text: String, duration: float = -1.0) -> void:
	"""Show centered spell/event feedback."""
	if spell_feedback:
		spell_feedback.text = text
		spell_feedback.visible = true
		spell_feedback.modulate.a = 1.0
		_feedback_timer = duration if duration > 0 else feedback_duration

func show_spell_cast(spell_name: String, emoji: String = "") -> void:
	"""Show spell cast feedback."""
	var text := emoji + " " + spell_name if emoji else spell_name
	show_feedback(text)

func update_health(current: float, maximum: float) -> void:
	"""Manually update health (if not using GameManager)."""
	_on_health_changed(current, maximum)

func update_mana(current: float, maximum: float) -> void:
	"""Manually update mana (if not using GameManager)."""
	_on_mana_changed(current, maximum)

# ============================================================================
# CIPHER DRAWING SYSTEM (consolidated from CipherHUD)
# ============================================================================

func _update_cipher_drawing(delta: float) -> void:
	"""Handle cipher trail fading and beautification."""
	# Handle beautification animation
	if is_beautifying:
		beautify_progress = minf(beautify_progress + delta / BEAUTIFY_DURATION, 1.0)
		if cipher_canvas:
			cipher_canvas.queue_redraw()
		
		if beautify_progress >= 1.0:
			is_beautifying = false
			draw_points = beautified_points.duplicate()
	
	# Handle trail fade
	if fade_timer > 0:
		fade_timer -= delta
		current_alpha = fade_timer / trail_fade_time
		if cipher_canvas:
			cipher_canvas.queue_redraw()
		
		if fade_timer <= 0:
			draw_points.clear()
			beautified_points.clear()
			is_showing_trail = false

func _on_cipher_canvas_draw() -> void:
	"""Draw the cipher trail on the canvas."""
	if draw_points.size() < 2:
		return
	
	var viewport_size := get_viewport().get_visible_rect().size
	
	# Determine which points to draw based on beautification state
	var points_to_draw: Array[Vector2] = []
	
	if is_beautifying and beautified_points.size() >= 2:
		var num_points := mini(draw_points.size(), beautified_points.size())
		for i in range(num_points):
			var original: Vector2 = draw_points[i] if i < draw_points.size() else draw_points[-1]
			var target_pt: Vector2 = beautified_points[i] if i < beautified_points.size() else beautified_points[-1]
			points_to_draw.append(original.lerp(target_pt, beautify_progress))
	else:
		points_to_draw = draw_points
	
	# Convert normalized points (0-1) to screen coordinates
	var screen_points: PackedVector2Array = []
	for p in points_to_draw:
		screen_points.append(Vector2(p.x * viewport_size.x, p.y * viewport_size.y))
	
	# Set color with fade
	var color := trail_color
	color.a *= current_alpha
	
	# Change color during beautification
	if is_beautifying or beautify_progress >= 1.0:
		color = success_color
		color.a *= current_alpha
	
	# Draw glow (wider, more transparent)
	var glow_color := color
	glow_color.a *= 0.3
	cipher_canvas.draw_polyline(screen_points, glow_color, trail_width * 3, true)
	
	# Draw main line
	cipher_canvas.draw_polyline(screen_points, color, trail_width, true)
	
	# Draw points at each vertex
	for p in screen_points:
		cipher_canvas.draw_circle(p, trail_width * 0.8, color)

# --- PUBLIC API: CIPHER DRAWING ---
func on_drawing_started() -> void:
	"""Called when cipher drawing begins."""
	draw_points.clear()
	beautified_points.clear()
	is_showing_trail = true
	current_alpha = 1.0
	fade_timer = 0.0
	beautify_progress = 0.0
	is_beautifying = false
	_set_status("Drawing...", trail_color)

func on_drawing_point_added(point: Vector2) -> void:
	"""Called when a new point is added to the drawing."""
	draw_points.append(point)
	if cipher_canvas:
		cipher_canvas.queue_redraw()

func on_drawing_ended() -> void:
	"""Called when drawing ends, start fade."""
	fade_timer = trail_fade_time
	_set_status("Recognizing...", trail_color)

func on_cipher_recognized(cipher_name: String, _confidence: float) -> void:
	"""Called when a cipher is successfully recognized."""
	if _is_showing_result:
		return
	
	_is_showing_result = true
	_set_status("Cast: " + cipher_name.capitalize() + "!", success_color)
	
	# Show big spell name
	show_feedback(cipher_name.capitalize().to_upper(), 1.5)
	
	# Start fade
	fade_timer = trail_fade_time * 1.5
	current_alpha = 1.0
	
	# Reset after delay
	_reset_status_after_delay(1.5)

func on_cipher_failed() -> void:
	"""Called when cipher recognition fails."""
	_set_status("Cipher not recognized", fail_color)
	_reset_status_after_delay(1.0)

func on_cipher_cancelled() -> void:
	"""Called when cipher is cancelled (control hand closed)."""
	draw_points.clear()
	beautified_points.clear()
	is_showing_trail = false
	is_beautifying = false
	beautify_progress = 0.0
	fade_timer = 0.0
	if cipher_canvas:
		cipher_canvas.queue_redraw()
	
	_set_status("Cipher cancelled", Color(1.0, 0.6, 0.2))
	_reset_status_after_delay(0.8)

func on_drawing_beautified(points: Array) -> void:
	"""Called when drawing is recognized - morph to clean shape."""
	beautified_points.clear()
	for p in points:
		if p is Vector2:
			beautified_points.append(p)
		elif p is Array and p.size() >= 2:
			beautified_points.append(Vector2(p[0], p[1]))
	
	if beautified_points.size() >= 2:
		is_beautifying = true
		beautify_progress = 0.0
		fade_timer = trail_fade_time * 2.0
		current_alpha = 1.0

func update_tracking_status(has_hands: bool, is_drawing: bool) -> void:
	"""Update status based on tracking state."""
	if _is_showing_result:
		return
	
	if not has_hands:
		_set_status("No hands detected", Color.GRAY)
	elif is_drawing:
		_set_status("Drawing... (open right hand to finish)", trail_color)
	else:
		_set_status("Open left hand, then point with right to draw", Color.WHITE)

func update_stroke_from_vision(stroke_points: Array) -> void:
	"""Update stroke visualization from Python vision data (centered coords)."""
	draw_points.clear()
	for point in stroke_points:
		if point is Array and point.size() >= 2:
			# Convert from centered (-1, 1) to normalized (0, 1)
			var x := (float(point[0]) + 1.0) / 2.0
			var y := (float(point[1]) + 1.0) / 2.0
			draw_points.append(Vector2(x, y))
	
	current_alpha = 1.0
	fade_timer = 0.0
	if cipher_canvas:
		cipher_canvas.queue_redraw()

func clear_stroke() -> void:
	"""Clear the stroke visualization."""
	draw_points.clear()
	if cipher_canvas:
		cipher_canvas.queue_redraw()

# --- INTERNAL HELPERS ---
func _set_status(text: String, color: Color) -> void:
	"""Set status label text and color."""
	if status_label:
		status_label.text = text
		status_label.add_theme_color_override("font_color", color)

func _reset_status_after_delay(delay: float) -> void:
	"""Reset status to default after a delay."""
	await get_tree().create_timer(delay).timeout
	_set_status("Open left hand, then point with right to draw", Color.WHITE)
	_is_showing_result = false
