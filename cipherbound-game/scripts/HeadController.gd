extends Camera3D

# --- CONFIGURATION ---
# NOTE: This controller is deprecated. Use Player.gd instead.
# Port 5006 to avoid conflict with Player.gd (5005)
var server := UDPServer.new()
var port := 5006

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
func _exit_tree():
	# Stop the UDP server and release the port when node is freed
	if server:
		server.stop()
		print("HeadController UDP server stopped")
func _process(delta):
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
			# Verify data is a Dictionary before accessing keys
			if typeof(data) != TYPE_DICTIONARY:
				return
			if data.has("has_face") and data["has_face"]:
				if data.has("head_x") and data.has("head_y"):
					var head_x = data["head_x"]
					var head_y = data["head_y"]
					if typeof(head_x) in [TYPE_FLOAT, TYPE_INT] and typeof(head_y) in [TYPE_FLOAT, TYPE_INT]:
						update_target_rotation(head_x, head_y)
					else:
						printerr("Invalid head_x or head_y type in vision data")
				else:
					printerr("Missing head_x or head_y in vision data")

	# 3. Smoothly move the camera towards the target
	# We use 'lerp' (Linear Interpolation) to filter out webcam jitter
	# Frame-rate independent smoothing: t = 1 - (1 - smoothing) ^ delta
	var t = 1.0 - pow(1.0 - smoothing, delta * 60.0)  # Normalized to 60 FPS baseline
	rotation.y = lerp_angle(rotation.y, target_rotation.y, t)
	rotation.x = lerp_angle(rotation.x, target_rotation.x, t)

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
