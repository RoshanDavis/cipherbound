extends Camera3D

# --- CONFIGURATION ---
var server := UDPServer.new()
var port := 5005

@export_range(0.1, 5.0, 0.1) var sensitivity_x := 1.5  ## How much the camera turns left/right
@export_range(0.1, 5.0, 0.1) var sensitivity_y := 1.0  ## How much the camera looks up/down

## Smoothing factor (0.1 = slow/smooth, 0.9 = fast/jittery)
@export_range(0.05, 1.0, 0.05) var smoothing := 0.1

# The target rotation we want to reach
var target_rotation := Vector3.ZERO

func _ready():
	# Start listening on the port
	var err = server.listen(port)
	if err != OK:
		printerr("Failed to listen on port " + str(port))
	else:
		print("Cipherbound Client listening on port " + str(port))

func _process(_delta):
	# 1. Check for new data packets
	server.poll()
	if server.is_connection_available():
		var peer = server.take_connection()
		var packet = peer.get_packet()
		var data_str = packet.get_string_from_utf8()
		
		# 2. Parse the JSON
		var json = JSON.new()
		var error = json.parse(data_str)
		
		if error == OK:
			var data = json.data
			if data.has("has_face") and data["has_face"]:
				update_target_rotation(data["head_x"], data["head_y"])

	# 3. Smoothly move the camera towards the target
	# We use 'lerp' (Linear Interpolation) to filter out webcam jitter
	rotation.y = lerp_angle(rotation.y, target_rotation.y, smoothing)
	rotation.x = lerp_angle(rotation.x, target_rotation.x, smoothing)

func update_target_rotation(nose_x: float, nose_y: float):
	# Map the 0.0-1.0 range to angles (Radians)
	
	# X-Axis (Looking Left/Right)
	# nose_x: 0.0 (Left) -> 1.0 (Right)
	# We subtract 0.5 so center is 0.0
	# We multiply by -1 to invert it (Mirror feel)
	var yaw = (nose_x - 0.5) * -sensitivity_x
	
	# Y-Axis (Looking Up/Down)
	var pitch = (nose_y - 0.5) * -sensitivity_y
	
	target_rotation = Vector3(pitch, yaw, 0.0)
