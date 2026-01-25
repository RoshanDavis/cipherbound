extends CanvasLayer
## HUD for displaying cipher drawing feedback and spell effects.
## Shows the trail of the player's finger when drawing ciphers.

# --- REFERENCES (created dynamically since loaded via script) ---
var draw_canvas: Control
var status_label: Label
var spell_label: Label

# --- SETTINGS ---
@export var trail_color := Color(0.3, 0.8, 1.0, 0.9) ## Cyan glow color
@export var trail_width := 4.0
@export var trail_fade_time := 0.5 ## Seconds for trail to fade after drawing ends
@export var success_color := Color(0.2, 1.0, 0.4) ## Green for success
@export var fail_color := Color(1.0, 0.3, 0.3) ## Red for failure

# --- STATE ---
var draw_points: Array[Vector2] = []
var beautified_points: Array[Vector2] = [] ## Clean shape after recognition
var is_showing_trail := false
var fade_timer := 0.0
var current_alpha := 1.0
var beautify_progress := 0.0 ## 0 = original, 1 = beautified
var is_beautifying := false
@export var beautify_duration := 0.3 ## Seconds to morph to clean shape

func _ready():
	# Create all UI elements dynamically (since this is loaded via script)
	draw_canvas = Control.new()
	draw_canvas.name = "DrawCanvas"
	draw_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(draw_canvas)
	
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.position = Vector2(20, 20)
	status_label.add_theme_font_size_override("font_size", 24)
	add_child(status_label)
	
	spell_label = Label.new()
	spell_label.name = "SpellLabel"
	spell_label.set_anchors_preset(Control.PRESET_CENTER)
	spell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_label.add_theme_font_size_override("font_size", 48)
	add_child(spell_label)
	
	# Connect drawing to canvas redraw
	draw_canvas.draw.connect(_on_draw_canvas_draw)
	
	# Hide spell label initially
	spell_label.visible = false
	status_label.text = "Open left hand, then point with right to draw"

func _process(delta: float):
	# Handle beautification animation
	if is_beautifying:
		beautify_progress = minf(beautify_progress + delta / beautify_duration, 1.0)
		draw_canvas.queue_redraw()
		
		if beautify_progress >= 1.0:
			is_beautifying = false
			# Replace draw_points with beautified for the fade
			draw_points = beautified_points.duplicate()
	
	# Handle trail fade
	if fade_timer > 0:
		fade_timer -= delta
		current_alpha = fade_timer / trail_fade_time
		draw_canvas.queue_redraw()
		
		if fade_timer <= 0:
			draw_points.clear()
			beautified_points.clear()
			is_showing_trail = false

func _on_draw_canvas_draw():
	"""Draw the cipher trail on the canvas."""
	if draw_points.size() < 2:
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Determine which points to draw based on beautification state
	var points_to_draw: Array[Vector2] = []
	
	if is_beautifying and beautified_points.size() >= 2:
		# Interpolate between original and beautified points
		var num_points = mini(draw_points.size(), beautified_points.size())
		for i in range(num_points):
			var original = draw_points[i] if i < draw_points.size() else draw_points[-1]
			var target = beautified_points[i] if i < beautified_points.size() else beautified_points[-1]
			var interpolated = original.lerp(target, beautify_progress)
			points_to_draw.append(interpolated)
	else:
		points_to_draw = draw_points
	
	# Convert normalized points (0-1) to screen coordinates
	var screen_points: PackedVector2Array = []
	for p in points_to_draw:
		screen_points.append(Vector2(p.x * viewport_size.x, p.y * viewport_size.y))
	
	# Draw with fade
	var color = trail_color
	color.a *= current_alpha
	
	# Change color during beautification to indicate success
	if is_beautifying or beautify_progress >= 1.0:
		color = success_color
		color.a *= current_alpha
	
	# Draw glow (wider, more transparent)
	var glow_color = color
	glow_color.a *= 0.3
	draw_canvas.draw_polyline(screen_points, glow_color, trail_width * 3, true)
	
	# Draw main line
	draw_canvas.draw_polyline(screen_points, color, trail_width, true)
	
	# Draw points at each vertex for extra visibility
	for p in screen_points:
		draw_canvas.draw_circle(p, trail_width * 0.8, color)

# --- PUBLIC API ---

func on_drawing_started():
	"""Called when cipher drawing begins."""
	draw_points.clear()
	beautified_points.clear()
	is_showing_trail = true
	current_alpha = 1.0
	fade_timer = 0.0
	beautify_progress = 0.0
	is_beautifying = false
	status_label.text = "Drawing..."
	status_label.add_theme_color_override("font_color", trail_color)

func on_drawing_point_added(point: Vector2):
	"""Called when a new point is added to the drawing."""
	draw_points.append(point)
	draw_canvas.queue_redraw()

func on_drawing_ended():
	"""Called when drawing ends, start fade."""
	fade_timer = trail_fade_time
	status_label.text = "Recognizing..."

func on_cipher_recognized(cipher_name: String, _confidence: float):
	"""Called when a cipher is successfully recognized."""
	status_label.text = "Cast: " + cipher_name.capitalize() + "!"
	status_label.add_theme_color_override("font_color", success_color)
	
	# Show big spell name
	spell_label.text = cipher_name.capitalize().to_upper()
	spell_label.add_theme_color_override("font_color", success_color)
	spell_label.visible = true
	
	# Hide after delay
	await get_tree().create_timer(1.5).timeout
	spell_label.visible = false
	status_label.text = "Open left hand, then point with right to draw"
	status_label.add_theme_color_override("font_color", Color.WHITE)

func on_cipher_failed():
	"""Called when cipher recognition fails."""
	status_label.text = "Cipher not recognized"
	status_label.add_theme_color_override("font_color", fail_color)
	
	# Reset after delay
	await get_tree().create_timer(1.0).timeout
	status_label.text = "Open left hand, then point with right to draw"
	status_label.add_theme_color_override("font_color", Color.WHITE)

func on_cipher_cancelled():
	"""Called when cipher is cancelled (control hand closed)."""
	draw_points.clear()
	beautified_points.clear()
	is_showing_trail = false
	is_beautifying = false
	beautify_progress = 0.0
	fade_timer = 0.0
	draw_canvas.queue_redraw()
	
	status_label.text = "Cipher cancelled"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2)) # Orange
	
	# Reset after delay
	await get_tree().create_timer(0.8).timeout
	status_label.text = "Open left hand, then point with right to draw"
	status_label.add_theme_color_override("font_color", Color.WHITE)

func on_drawing_beautified(points: Array):
	"""Called when drawing is recognized - instantly snap to clean shape."""
	beautified_points.clear()
	for p in points:
		if p is Vector2:
			beautified_points.append(p)
	
	if beautified_points.size() >= 2:
		# Instant snap - replace draw points immediately
		draw_points = beautified_points.duplicate()
		is_beautifying = false
		beautify_progress = 1.0
		# Show the clean shape for longer
		fade_timer = trail_fade_time * 2.0
		current_alpha = 1.0
		draw_canvas.queue_redraw()

func update_tracking_status(has_hands: bool, is_drawing: bool):
	"""Update status based on tracking state."""
	if not has_hands:
		status_label.text = "No hands detected"
		status_label.add_theme_color_override("font_color", Color.GRAY)
	elif is_drawing:
		status_label.text = "Drawing... (open right hand to finish)"
		status_label.add_theme_color_override("font_color", trail_color)
	else:
		# Hands detected but not drawing
		status_label.text = "Open left hand, then point with right to draw"
		status_label.add_theme_color_override("font_color", Color.WHITE)
