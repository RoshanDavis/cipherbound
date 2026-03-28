extends CanvasLayer
class_name GameHUD
## GameHUD - Main game UI with health bar, wave info, cipher drawing, menus.

# --- NODE REFERENCES ---
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthContainer/HealthLabel
@onready var wave_label: Label = $TopRight/WaveLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var spell_feedback: Label = $CenterContainer/SpellFeedback
@onready var cipher_canvas: Control = $CipherCanvas
@onready var status_label: Label = $StatusLabel
@onready var _cipher_ref_panel: PanelContainer = $CipherReference

# --- CONFIGURATION ---
@export_group("Bar Settings")
@export var health_color := Color(0.8, 0.2, 0.2) ## Red
@export var health_bg_color := Color(0.3, 0.1, 0.1)
@export var bar_smooth_speed := 10.0 ## How fast bars animate

@export_group("Feedback")
@export var show_spell_feedback := false ## Show big centered spell name on cast
@export var show_status_label := false ## Show tracking status at bottom
@export var feedback_duration := 2.0
@export var feedback_fade_time := 0.5

@export_group("Cipher Drawing")
@export var trail_color := Color(0.3, 0.8, 1.0, 0.9) ## Cyan glow
@export var trail_width := 4.0
@export var trail_fade_time := 1.5
@export var success_color := Color(0.2, 1.0, 0.4) ## Green
@export var fail_color := Color(1.0, 0.3, 0.3) ## Red

# --- INTERNAL STATE ---
var _target_health := 100.0
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

# --- MENU PANELS ---
var _main_menu_panel: PanelContainer
var _death_screen_panel: PanelContainer
var _death_score_label: Label
var _death_kills_label: Label

# --- Reference for draw_canvas compatibility ---
var draw_canvas: Control:
	get:
		return cipher_canvas

func _ready() -> void:
	_connect_signals()
	_setup_bars()
	_hide_feedback()
	_setup_cipher_canvas()
	_create_main_menu()
	_create_death_screen()
	
	# Show correct panel based on game state
	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		if gm.game_state == gm.GameState.MENU:
			_show_main_menu()
	
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
		gm.wave_started.connect(_on_wave_started)
		gm.wave_completed.connect(_on_wave_completed)
		gm.score_changed.connect(_on_score_changed)
		gm.enemy_killed.connect(_on_enemy_killed)
		gm.game_over.connect(_on_game_over)
		gm.game_state_changed.connect(_on_game_state_changed)
		
		# Initialize with current values
		_on_health_changed(gm.current_health, gm.max_health)
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

func _setup_cipher_canvas() -> void:
	"""Setup cipher drawing canvas."""
	if cipher_canvas:
		cipher_canvas.draw.connect(_on_cipher_canvas_draw)

func _update_bar_smoothing(delta: float) -> void:
	"""Smoothly animate bar values."""
	if health_bar:
		health_bar.value = lerpf(health_bar.value, _target_health, bar_smooth_speed * delta)

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

func _on_game_over(victory: bool) -> void:
	if victory:
		show_feedback("VICTORY!", 5.0)
	else:
		_show_death_screen()

func _on_game_state_changed(new_state: int) -> void:
	# GameState enum values: MENU=0, PLAYING=1, PAUSED=2, GAME_OVER=3, VICTORY=4
	match new_state:
		0: # MENU
			_show_main_menu()
		1: # PLAYING
			_hide_main_menu()
			_hide_death_screen()

# --- PUBLIC API ---
func show_feedback(text: String, duration: float = -1.0) -> void:
	"""Show centered spell/event feedback."""
	if not show_spell_feedback:
		return
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

# ============================================================================
# MAIN MENU
# ============================================================================

func _create_main_menu() -> void:
	"""Create the main menu overlay."""
	_main_menu_panel = PanelContainer.new()
	_main_menu_panel.name = "MainMenu"
	_main_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_main_menu_panel.visible = false
	
	# Dark overlay
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.75)
	_main_menu_panel.add_theme_stylebox_override("panel", overlay_style)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu_panel.add_child(center)
	
	# Content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "CIPHERBOUND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 1))
	vbox.add_child(title)
	
	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Cast spells with gestures"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(subtitle)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)
	
	# Start button
	var start_btn := Button.new()
	start_btn.text = "START GAME"
	start_btn.custom_minimum_size = Vector2(250, 60)
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(start_btn)
	
	add_child(_main_menu_panel)

func _show_main_menu() -> void:
	if _main_menu_panel:
		_main_menu_panel.visible = true

func _hide_main_menu() -> void:
	if _main_menu_panel:
		_main_menu_panel.visible = false

func _on_start_pressed() -> void:
	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		gm.start_game()
	_hide_main_menu()
	
	# Start enemy spawner if present
	var spawner := get_tree().root.get_node_or_null("Game/EnemySpawner")
	if spawner and spawner.has_method("start_waves"):
		spawner.start_waves()

# ============================================================================
# DEATH SCREEN
# ============================================================================

func _create_death_screen() -> void:
	"""Create the death/game over screen overlay."""
	_death_screen_panel = PanelContainer.new()
	_death_screen_panel.name = "DeathScreen"
	_death_screen_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_death_screen_panel.visible = false
	
	# Dark red overlay
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.15, 0, 0, 0.8)
	_death_screen_panel.add_theme_stylebox_override("panel", overlay_style)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen_panel.add_child(center)
	
	# Content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	vbox.add_child(title)
	
	# Score label (updated on show)
	var death_score := Label.new()
	death_score.name = "DeathScore"
	death_score.text = "Score: 0"
	death_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_score.add_theme_font_size_override("font_size", 28)
	death_score.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(death_score)
	_death_score_label = death_score
	
	# Enemies killed
	var kills_label := Label.new()
	kills_label.name = "KillsLabel"
	kills_label.text = "Enemies Defeated: 0"
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", 20)
	kills_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(kills_label)
	_death_kills_label = kills_label
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)
	
	# Restart button
	var restart_btn := Button.new()
	restart_btn.text = "RESTART"
	restart_btn.custom_minimum_size = Vector2(250, 60)
	restart_btn.add_theme_font_size_override("font_size", 24)
	restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_btn)
	
	add_child(_death_screen_panel)

func _show_death_screen() -> void:
	if _death_screen_panel:
		_death_screen_panel.visible = true
		
		# Update score/kills from GameManager
		if has_node("/root/GameManager"):
			var gm := get_node("/root/GameManager")
			if _death_score_label:
				_death_score_label.text = "Score: %d" % gm.score
			if _death_kills_label:
				_death_kills_label.text = "Enemies Defeated: %d  |  Wave: %d" % [gm.total_enemies_killed, gm.current_wave]

func _hide_death_screen() -> void:
	if _death_screen_panel:
		_death_screen_panel.visible = false

func _on_restart_pressed() -> void:
	_hide_death_screen()
	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		gm.restart_game()

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

func set_drawing_mode(is_active: bool) -> void:
	"""Show or hide the cipher reference panel depending on the stance."""
	if is_active:
		_show_cipher_reference()
	else:
		_hide_cipher_reference()

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

# ============================================================================
# CIPHER REFERENCE PANEL (shown during drawing mode)
# ============================================================================

func _show_cipher_reference() -> void:
	if _cipher_ref_panel:
		_cipher_ref_panel.visible = true
		_cipher_ref_panel.modulate.a = 1.0

func _hide_cipher_reference() -> void:
	if _cipher_ref_panel:
		_cipher_ref_panel.visible = false

# --- INTERNAL HELPERS ---
func _set_status(text: String, color: Color) -> void:
	"""Set status label text and color."""
	if not show_status_label:
		if status_label:
			status_label.visible = false
		return
	if status_label:
		status_label.visible = true
		status_label.text = text
		status_label.add_theme_color_override("font_color", color)

func _reset_status_after_delay(delay: float) -> void:
	"""Reset status to default after a delay."""
	await get_tree().create_timer(delay).timeout
	_set_status("Open left hand, then point with right to draw", Color.WHITE)
	_is_showing_result = false
