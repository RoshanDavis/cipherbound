extends Node
## Cipher drawing and recognition system.
## Captures finger movement when pointing to draw symbols,
## then matches against known cipher patterns to cast spells.

class_name CipherDrawer

# --- SIGNALS ---
signal drawing_started
signal drawing_point_added(point: Vector2)
signal drawing_ended
signal cipher_recognized(cipher_name: String, confidence: float)
signal cipher_failed
signal drawing_beautified(beautified_points: Array) ## Emitted with clean shape points

# --- SETTINGS ---
@export_group("Drawing")
@export var min_points := 10 ## Minimum points needed for recognition
@export var max_points := 200 ## Max points to store (prevents memory issues)
@export var point_distance_threshold := 0.02 ## Min distance between points (normalized)
@export var drawing_timeout := 2.0 ## Seconds of no movement before auto-end

@export_group("Recognition")
@export var recognition_threshold := 0.7 ## Minimum confidence to recognize (0-1)
@export var sample_points := 32 ## Points to resample to for comparison

# --- STATE ---
var is_drawing := false
var current_stroke: Array[Vector2] = []
var last_point := Vector2.ZERO
var time_since_last_point := 0.0

# --- CIPHER PATTERNS ---
# Each pattern is an array of normalized points (0-1 range)
# These will be compared against drawn strokes
var cipher_patterns := {
	"fire": [], # Will be defined below
	"water": [],
	"shield": [],
	"lightning": [],
}

func _ready():
	_init_cipher_patterns()

func _process(delta: float):
	if is_drawing:
		time_since_last_point += delta
		if time_since_last_point > drawing_timeout:
			end_drawing()

func _init_cipher_patterns():
	"""Initialize the cipher patterns for recognition."""
	# Fire: Upward triangle (^)
	cipher_patterns["fire"] = _generate_triangle_up()
	
	# Water: Downward triangle (v)
	cipher_patterns["water"] = _generate_triangle_down()
	
	# Shield: Circle
	cipher_patterns["shield"] = _generate_circle()
	
	# Lightning: Zigzag
	cipher_patterns["lightning"] = _generate_zigzag()

func _generate_triangle_up() -> Array[Vector2]:
	var points: Array[Vector2] = []
	@warning_ignore("integer_division")
	var seg_points := sample_points / 3
	if seg_points == 0:
		seg_points = 1
	# Start bottom-left, go up to top, down to bottom-right
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.2, 0.5, t), lerpf(0.8, 0.2, t)))
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.5, 0.8, t), lerpf(0.2, 0.8, t)))
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.8, 0.2, t), 0.8))
	return points

func _generate_triangle_down() -> Array[Vector2]:
	var points: Array[Vector2] = []
	@warning_ignore("integer_division")
	var seg_points := sample_points / 3
	if seg_points == 0:
		seg_points = 1
	# Start top-left, go down to bottom, up to top-right
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.2, 0.5, t), lerpf(0.2, 0.8, t)))
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.5, 0.8, t), lerpf(0.8, 0.2, t)))
	for i in range(seg_points):
		var t = float(i) / float(seg_points)
		points.append(Vector2(lerpf(0.8, 0.2, t), 0.2))
	return points

func _generate_circle() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in range(sample_points):
		var angle = (float(i) / sample_points) * TAU
		points.append(Vector2(
			0.5 + cos(angle) * 0.3,
			0.5 + sin(angle) * 0.3
		))
	return points

func _generate_zigzag() -> Array[Vector2]:
	var points: Array[Vector2] = []
	# Zigzag pattern: top-left -> middle-right -> middle-left -> bottom-right
	var segments = 4
	@warning_ignore("integer_division")
	var pts_per_seg = sample_points / segments
	if pts_per_seg == 0:
		pts_per_seg = 1
	
	# Segment 1: top-left to upper-middle-right
	for i in range(pts_per_seg):
		var t = float(i) / float(pts_per_seg)
		points.append(Vector2(lerpf(0.2, 0.7, t), lerpf(0.2, 0.4, t)))
	# Segment 2: upper-middle-right to middle-left
	for i in range(pts_per_seg):
		var t = float(i) / float(pts_per_seg)
		points.append(Vector2(lerpf(0.7, 0.3, t), lerpf(0.4, 0.5, t)))
	# Segment 3: middle-left to lower-middle-right
	for i in range(pts_per_seg):
		var t = float(i) / float(pts_per_seg)
		points.append(Vector2(lerpf(0.3, 0.7, t), lerpf(0.5, 0.6, t)))
	# Segment 4: lower-middle-right to bottom-left
	for i in range(pts_per_seg):
		var t = float(i) / float(pts_per_seg)
		points.append(Vector2(lerpf(0.7, 0.8, t), lerpf(0.6, 0.8, t)))
	return points

# --- DRAWING API ---

func start_drawing():
	"""Begin capturing a new cipher drawing."""
	if is_drawing:
		return
	
	is_drawing = true
	current_stroke.clear()
	time_since_last_point = 0.0
	drawing_started.emit()

func add_point(normalized_pos: Vector2):
	"""Add a point to the current drawing (position should be 0-1 normalized)."""
	if not is_drawing:
		return
	
	# Check minimum distance from last point
	if current_stroke.size() > 0:
		var dist = normalized_pos.distance_to(last_point)
		if dist < point_distance_threshold:
			return # Too close, skip
	
	# Add the point
	if current_stroke.size() < max_points:
		current_stroke.append(normalized_pos)
		last_point = normalized_pos
		time_since_last_point = 0.0
		drawing_point_added.emit(normalized_pos)
	else:
		# Max points reached, auto-end drawing to prevent stuck state
		time_since_last_point = 0.0
		end_drawing()

func end_drawing():
	"""Finish drawing and attempt recognition."""
	if not is_drawing:
		return
	
	is_drawing = false
	drawing_ended.emit()
	
	# Attempt recognition
	if current_stroke.size() >= min_points:
		var result = recognize_cipher()
		if result.confidence >= recognition_threshold:
			cipher_recognized.emit(result.name, result.confidence)
			print("=== CIPHER RECOGNIZED ===")
			print("  Shape: ", result.name.to_upper())
			print("  Confidence: ", snapped(result.confidence * 100, 0.1), "%")
			print("=========================")
			
			# Beautify the drawing - replace messy stroke with clean template
			var beautified = _beautify_stroke(result.name)
			if beautified.size() > 0:
				drawing_beautified.emit(beautified)
		else:
			cipher_failed.emit()
			print("=== CIPHER FAILED ===")
			print("  Best match: ", result.name)
			print("  Confidence: ", snapped(result.confidence * 100, 0.1), "% (need ", recognition_threshold * 100, "%)")
			print("=====================")
	else:
		cipher_failed.emit()
		print("=== CIPHER FAILED ===")
		print("  Not enough points: ", current_stroke.size(), " (need ", min_points, ")")
		print("=====================")
	
	current_stroke.clear()

func cancel_drawing():
	"""Cancel current drawing without recognition."""
	is_drawing = false
	current_stroke.clear()
	drawing_ended.emit()

# --- RECOGNITION ---

func recognize_cipher() -> Dictionary:
	"""
	Compare current stroke against all patterns.
	Returns {name: String, confidence: float}
	"""
	if current_stroke.size() < min_points:
		return {"name": "", "confidence": 0.0}
	
	# Resample stroke to fixed number of points
	var resampled = _resample_stroke(current_stroke, sample_points)
	
	# Normalize to 0-1 bounding box
	var normalized = _normalize_stroke(resampled)
	
	# Compare against each pattern
	var best_name := ""
	var best_score := 0.0
	
	for pattern_name in cipher_patterns:
		var pattern = cipher_patterns[pattern_name]
		if pattern.size() == 0:
			continue
		
		var score = _compare_strokes(normalized, pattern)
		if score > best_score:
			best_score = score
			best_name = pattern_name
	
	return {"name": best_name, "confidence": best_score}

func _resample_stroke(stroke: Array[Vector2], n: int) -> Array[Vector2]:
	"""Resample stroke to exactly n evenly-spaced points."""
	if stroke.size() < 2:
		return stroke.duplicate()
	
	# Make a copy to avoid modifying input
	var stroke_copy: Array[Vector2] = []
	for p in stroke:
		stroke_copy.append(p)
	
	# Calculate total path length
	var total_length := 0.0
	for i in range(1, stroke_copy.size()):
		total_length += stroke_copy[i].distance_to(stroke_copy[i - 1])
	
	if total_length == 0:
		return stroke_copy
	
	var interval := total_length / float(n - 1)
	var resampled: Array[Vector2] = [stroke_copy[0]]
	var accumulated := 0.0
	var j := 1
	
	while resampled.size() < n and j < stroke_copy.size():
		var seg_len = stroke_copy[j].distance_to(stroke_copy[j - 1])
		
		if accumulated + seg_len >= interval:
			var t = (interval - accumulated) / seg_len if seg_len > 0 else 0.0
			var new_point = stroke_copy[j - 1].lerp(stroke_copy[j], t)
			resampled.append(new_point)
			stroke_copy.insert(j, new_point) # Insert for next iteration
			accumulated = 0.0
		else:
			accumulated += seg_len
			j += 1
	
	# Fill remaining if needed
	while resampled.size() < n:
		resampled.append(stroke_copy[-1])
	
	return resampled

func _normalize_stroke(stroke: Array[Vector2]) -> Array[Vector2]:
	"""Normalize stroke to fit in 0-1 bounding box, centered."""
	if stroke.size() == 0:
		return stroke
	
	# Find bounding box
	var min_p := stroke[0]
	var max_p := stroke[0]
	for p in stroke:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	
	var size := max_p - min_p
	var scale: float = maxf(size.x, size.y)
	if scale == 0:
		scale = 1.0
	
	# Normalize
	var normalized: Array[Vector2] = []
	for p in stroke:
		var np = (p - min_p) / scale
		# Center in 0-1 space
		np.x = np.x * 0.8 + 0.1
		np.y = np.y * 0.8 + 0.1
		normalized.append(np)
	
	return normalized

func _compare_strokes(stroke1: Array[Vector2], stroke2: Array[Vector2]) -> float:
	"""
	Compare two strokes and return similarity score (0-1).
	Uses average point distance.
	"""
	if stroke1.size() != stroke2.size():
		return 0.0
	
	var total_dist := 0.0
	for i in range(stroke1.size()):
		total_dist += stroke1[i].distance_to(stroke2[i])
	
	var avg_dist := total_dist / stroke1.size()
	
	# Convert distance to score (closer = higher score)
	# Max reasonable distance is ~1.4 (diagonal of unit square)
	var score: float = 1.0 - clampf(avg_dist / 0.5, 0.0, 1.0)
	
	return score

func _beautify_stroke(cipher_name: String) -> Array[Vector2]:
	"""
	Replace the messy user drawing with a clean template shape.
	Scales and positions the template to match the user's drawn bounding box.
	This creates the 'ink to shape' effect like Microsoft Whiteboard.
	"""
	if not cipher_patterns.has(cipher_name):
		return []
	
	var template: Array[Vector2] = cipher_patterns[cipher_name]
	if template.size() == 0 or current_stroke.size() == 0:
		return []
	
	# Find bounding box of user's stroke
	var user_min := current_stroke[0]
	var user_max := current_stroke[0]
	for p in current_stroke:
		user_min.x = min(user_min.x, p.x)
		user_min.y = min(user_min.y, p.y)
		user_max.x = max(user_max.x, p.x)
		user_max.y = max(user_max.y, p.y)
	
	var user_center := (user_min + user_max) / 2.0
	var user_size := user_max - user_min
	
	# Ensure minimum size to avoid division issues
	user_size.x = maxf(user_size.x, 0.05)
	user_size.y = maxf(user_size.y, 0.05)
	
	# Find bounding box of template
	var tmpl_min := template[0]
	var tmpl_max := template[0]
	for p in template:
		tmpl_min.x = min(tmpl_min.x, p.x)
		tmpl_min.y = min(tmpl_min.y, p.y)
		tmpl_max.x = max(tmpl_max.x, p.x)
		tmpl_max.y = max(tmpl_max.y, p.y)
	
	var tmpl_center := (tmpl_min + tmpl_max) / 2.0
	var tmpl_size := tmpl_max - tmpl_min
	tmpl_size.x = maxf(tmpl_size.x, 0.01)
	tmpl_size.y = maxf(tmpl_size.y, 0.01)
	
	# Calculate scale to fit template into user's bounding box
	# Use uniform scale to preserve aspect ratio
	var scale_factor := minf(user_size.x / tmpl_size.x, user_size.y / tmpl_size.y)
	
	# Transform template points to match user's stroke location and size
	var beautified: Array[Vector2] = []
	for p in template:
		# Center, scale, then translate to user's center
		var transformed := (p - tmpl_center) * scale_factor + user_center
		beautified.append(transformed)
	
	return beautified

# --- HELPER FOR VISION INPUT ---

func process_hand_data(hand_data: Dictionary, is_pointing: bool):
	"""
	Process hand tracking data for drawing.
	Call this each frame with the relevant hand's data.
	Note: This only captures points - end_drawing() must be called separately.
	"""
	if is_pointing:
		if not is_drawing:
			start_drawing()
		
		# Convert index fingertip to normalized screen position
		var index_tip = hand_data.get("index_tip", {"x": 0.0, "y": 0.0})
		# Vision data is -1 to 1, convert to 0 to 1
		var normalized = Vector2(
			(index_tip.get("x", 0.0) + 1.0) / 2.0,
			(index_tip.get("y", 0.0) + 1.0) / 2.0
		)
		add_point(normalized)
