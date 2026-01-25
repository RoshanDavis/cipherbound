import sys
import os
import time

# Ensure imports work regardless of current working directory
_src_dir = os.path.dirname(os.path.abspath(__file__))
if _src_dir not in sys.path:
    sys.path.insert(0, _src_dir)

import cv2
import mediapipe as mp

from config import WEBCAM_ID, DEBUG_MODE, UDP_IP, UDP_PORT
from config import LOOK_DEADZONE_RADIUS, LOOK_MAX_RADIUS
from config import MOVE_DEADZONE_RADIUS, MOVE_MAX_RADIUS
from config import LEFT_HANDED
from network import UDPSender
from trackers import LookTracker, StrafeTracker, DepthTracker, HandTracker
from trackers.shape_recognizer import GestureTracker  # Use new OpenCV-based recognizer


def main():
    """
    Run the vision processing loop: capture frames from the configured webcam,
    process them with MediaPipe Holistic to detect face and pose landmarks,
    update trackers to compute look/lean control values, and send a data packet
    over UDP each frame.
    """
    print("--- CIPHERBOUND VISION SERVER ---")
    print(f"Target: {UDP_IP}:{UDP_PORT}")
    print("Press 'ESC' to quit, 'R' to recalibrate")
    print("Mode: Holistic (Face + Body + Hands)")
    print(f"Handedness: {'Left-handed' if LEFT_HANDED else 'Right-handed'}")
    print()
    
    # --- CAMERA SETUP ---
    print(f"Opening camera {WEBCAM_ID}...")
    cap = cv2.VideoCapture(WEBCAM_ID)
    
    if not cap.isOpened():
        print(f"ERROR: Could not open camera {WEBCAM_ID}")
        print("Try changing WEBCAM_ID in config.py (0, 1, 2, etc.)")
        return
    
    # Configure camera for better performance
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # Reduce latency
    
    # Wait for camera to initialize and verify it's working
    print("Waiting for camera to initialize...")
    for attempt in range(10):
        success, test_frame = cap.read()
        if success and test_frame is not None:
            h, w = test_frame.shape[:2]
            print(f"Camera ready: {w}x{h}")
            break
        time.sleep(0.1)
    else:
        print("ERROR: Camera opened but not returning frames")
        print("Check if another application is using the camera")
        cap.release()
        return
    
    # --- NETWORK SETUP ---
    sender = UDPSender()
    
    # --- MEDIAPIPE SETUP ---
    mp_holistic = mp.solutions.holistic
    holistic = mp_holistic.Holistic(
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
        model_complexity=1,
        refine_face_landmarks=True
    )
    
    # --- TRACKERS ---
    look_tracker = LookTracker()
    strafe_tracker = StrafeTracker()
    depth_tracker = DepthTracker()
    hand_tracker = HandTracker()
    gesture_tracker = GestureTracker()
    
    # Gesture state machine
    gesture_state = "idle"  # idle, ready_to_draw, drawing
    
    print("Starting vision loop...")
    empty_frame_count = 0
    
    # Create window explicitly and bring to front
    if DEBUG_MODE:
        cv2.namedWindow('Cipherbound Vision Eye', cv2.WINDOW_AUTOSIZE)
        cv2.setWindowProperty('Cipherbound Vision Eye', cv2.WND_PROP_TOPMOST, 1)
        print("Debug window created - should appear on screen")
    
    while True:
        success, image = cap.read()
        
        if not success or image is None:
            empty_frame_count += 1
            if empty_frame_count >= 30:  # Only warn after many failures
                print(f"Warning: {empty_frame_count} empty frames, camera may be disconnected")
                empty_frame_count = 0
            continue
        
        empty_frame_count = 0  # Reset counter on successful read
        
        # Flip for selfie-view
        image = cv2.flip(image, 1)
        
        # Convert to RGB for MediaPipe
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = holistic.process(rgb_image)
        
        # Initialize data packet
        data_packet = {
            "has_face": False,
            "look_x": 0.0,
            "look_y": 0.0,
            "has_body": False,
            "lean_x": 0.0,
            "lean_y": 0.0,
            "calibrated": False
        }
        
        body_offset = (0.0, 0.0)
        
        # --- BODY/STRAFE TRACKING (process first for body offset) ---
        if results.pose_landmarks:
            pose = results.pose_landmarks.landmark
            left_shoulder = pose[mp_holistic.PoseLandmark.LEFT_SHOULDER]
            right_shoulder = pose[mp_holistic.PoseLandmark.RIGHT_SHOULDER]
            
            if left_shoulder.visibility > 0.5 and right_shoulder.visibility > 0.5:
                data_packet["has_body"] = True
                
                shoulder_center_x = (left_shoulder.x + right_shoulder.x) / 2
                shoulder_center_y = (left_shoulder.y + right_shoulder.y) / 2
                
                strafe_result = strafe_tracker.process(shoulder_center_x, shoulder_center_y)
                data_packet["lean_x"] = strafe_result["lean_x"]
                body_offset = strafe_result["body_offset"]
        
        # --- FACE/LOOK TRACKING ---
        if results.face_landmarks:
            data_packet["has_face"] = True
            
            nose_tip = results.face_landmarks.landmark[1]
            look_result = look_tracker.process(nose_tip.x, nose_tip.y, body_offset)
            data_packet["look_x"] = look_result["look_x"]
            data_packet["look_y"] = look_result["look_y"]
            
            # --- DEPTH TRACKING (forward/back via face size) ---
            depth_result = depth_tracker.process(results.face_landmarks)
            data_packet["lean_y"] = depth_result["lean_y"]
        
        # --- HAND TRACKING ---
        # Note: We swap left/right because the image is flipped for selfie-view
        # MediaPipe's "left hand" becomes the user's right hand visually
        h, w, _ = image.shape
        hand_result = hand_tracker.process(
            results.right_hand_landmarks,  # User's left hand (swapped)
            results.left_hand_landmarks,   # User's right hand (swapped)
            w, h
        )
        data_packet["has_left_hand"] = hand_result["has_left_hand"]
        data_packet["has_right_hand"] = hand_result["has_right_hand"]
        data_packet["left_hand"] = hand_result["left_hand"]
        data_packet["right_hand"] = hand_result["right_hand"]
        data_packet["left_handed"] = LEFT_HANDED  # Send handedness preference
        
        # --- GESTURE RECOGNITION STATE MACHINE ---
        # Left open = ready to draw, Left closed = cancel
        # Right pointing = drawing, Right open = finish
        left_hand = hand_result["left_hand"]
        right_hand = hand_result["right_hand"]
        
        data_packet["gesture_state"] = gesture_state
        data_packet["gesture_recognized"] = None
        data_packet["gesture_score"] = 0.0
        
        if gesture_state == "idle":
            # Enter draw mode when left hand opens
            if hand_result["has_left_hand"] and left_hand["is_open"]:
                gesture_state = "ready_to_draw"
        
        elif gesture_state == "ready_to_draw":
            # Cancel if left hand closes
            if hand_result["has_left_hand"] and left_hand["is_closed"]:
                gesture_state = "idle"
            # Start drawing when right hand points
            elif hand_result["has_right_hand"] and right_hand["is_pointing"]:
                gesture_tracker.start_drawing()
                gesture_state = "drawing"
            # Also cancel if left hand lost while not drawing
            elif not hand_result["has_left_hand"]:
                gesture_state = "idle"
        
        elif gesture_state == "drawing":
            # Capture drawing point from right index finger
            if hand_result["has_right_hand"]:
                index_tip = right_hand["index_tip"]
                gesture_tracker.add_point(index_tip["x"], index_tip["y"])
            
            # Cancel if left hand closes
            if hand_result["has_left_hand"] and left_hand["is_closed"]:
                gesture_tracker.cancel_drawing()
                gesture_state = "idle"
            # Finish when right hand opens OR no longer pointing
            elif hand_result["has_right_hand"] and right_hand["is_open"]:
                result = gesture_tracker.end_drawing()
                if result:
                    print(f"=== RECOGNIZED: {result.name.upper()} ({result.confidence:.0%}) ===")
                    data_packet["gesture_recognized"] = result.name
                    data_packet["gesture_score"] = result.confidence
                else:
                    print("Shape not recognized")
                gesture_state = "idle"
        
        data_packet["gesture_state"] = gesture_state
        data_packet["drawing_points"] = len(gesture_tracker.current_stroke)
        
        # Send stroke points for visualization in Godot (convert to list of [x,y])
        # Limit to every Nth point to reduce packet size
        stroke = gesture_tracker.current_stroke
        if len(stroke) > 50:
            # Downsample to ~50 points
            step = len(stroke) // 50
            stroke = stroke[::step]
        data_packet["stroke_points"] = [[p[0], p[1]] for p in stroke]
        
        # Update calibration status
        data_packet["calibrated"] = (
            look_tracker.is_calibrated and 
            strafe_tracker.is_calibrated and
            depth_tracker.is_calibrated
        )
        
        # --- SEND DATA ---
        sender.send(data_packet)
        
        # --- DEBUG VISUALIZATION ---
        if DEBUG_MODE:
            draw_debug(image, results, data_packet, 
                      look_tracker, strafe_tracker, depth_tracker,
                      body_offset, mp_holistic, hand_tracker, gesture_tracker)
            
            cv2.imshow('Cipherbound Vision Eye', image)
            key = cv2.waitKey(5) & 0xFF
            
            if key == 27:  # ESC
                break
            elif key == ord('r') or key == ord('R'):
                look_tracker.reset_calibration()
                strafe_tracker.reset_calibration()
                depth_tracker.reset_calibration()
                print("Recalibrating...")
        else:
            # Non-debug mode: check for keyboard interrupt periodically
            if cv2.waitKey(1) & 0xFF == 27:
                break
    
    # Cleanup
    print("Shutting down...")
    cap.release()
    holistic.close()
    sender.close()
    cv2.destroyAllWindows()
    print("Done.")


def draw_debug(image, results, data_packet, look_tracker, strafe_tracker, depth_tracker, body_offset, mp_holistic, hand_tracker=None, gesture_tracker=None):
    """
    Render debug overlays onto the provided BGR image showing calibration progress and visualizations for face, look, depth, body, and hand tracking.
    
    Parameters:
        image (numpy.ndarray): BGR image buffer to draw overlays on (modified in place).
        results: MediaPipe Holistic processing result containing face and pose landmarks.
        data_packet (dict): Current control/state values (e.g., 'calibrated', 'look_x', 'look_y', 'lean_x', 'lean_y') used for on-screen text.
        look_tracker: LookTracker instance used to obtain adjusted look center and calibration progress.
        strafe_tracker: StrafeTracker instance used for body-center visualization and calibration state.
        depth_tracker: DepthTracker instance used for depth calibration progress.
        body_offset (tuple | None): Current body offset applied when computing adjusted look center, or None if unavailable.
        mp_holistic: MediaPipe Holistic module (used for landmark enums).
        hand_tracker: Optional HandTracker instance for hand visualization.
        gesture_tracker: Optional GestureTracker instance for drawing visualization.
    """
    h, w, _ = image.shape
    
    # Check if still calibrating
    if not data_packet["calibrated"]:
        progress = min(
            look_tracker.calibration_progress,
            strafe_tracker.calibration_progress,
            depth_tracker.calibration_progress
        )
        cv2.putText(image, f"CALIBRATING... {int(progress * 100)}%", 
                   (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
        cv2.putText(image, "Stand still, face forward", 
                   (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
    else:
        # Show control values
        cv2.putText(image, f"Look: ({data_packet['look_x']:.2f}, {data_packet['look_y']:.2f})", 
                   (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
        cv2.putText(image, f"Strafe: {data_packet['lean_x']:.2f}", 
                   (10, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
        cv2.putText(image, f"Depth: {data_packet['lean_y']:.2f}", 
                   (10, 80), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 200, 0), 1)
        cv2.putText(image, "Press 'R' to recalibrate", 
                   (10, h - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
    
    # --- FACE VISUALIZATION ---
    if results.face_landmarks:
        nose = results.face_landmarks.landmark[1]
        cx, cy = int(nose.x * w), int(nose.y * h)
        cv2.circle(image, (cx, cy), 8, (0, 255, 0), -1)
        
        adjusted_center = look_tracker.get_adjusted_center(body_offset)
        if adjusted_center:
            fcx, fcy = int(adjusted_center[0] * w), int(adjusted_center[1] * h)
            
            # Deadzone circle (red)
            deadzone_px = int(LOOK_DEADZONE_RADIUS * w)
            cv2.circle(image, (fcx, fcy), deadzone_px, (0, 0, 255), 1)
            
            # Max radius circle (green)
            max_px = int(LOOK_MAX_RADIUS * w)
            cv2.circle(image, (fcx, fcy), max_px, (0, 255, 0), 1)
            
            # Center and line
            cv2.circle(image, (fcx, fcy), 4, (255, 0, 255), -1)
            cv2.line(image, (fcx, fcy), (cx, cy), (255, 0, 255), 2)
        
        # Draw eyes for depth tracking debug
        left_eye = results.face_landmarks.landmark[33]
        right_eye = results.face_landmarks.landmark[263]
        lex, ley = int(left_eye.x * w), int(left_eye.y * h)
        rex, rey = int(right_eye.x * w), int(right_eye.y * h)
        cv2.circle(image, (lex, ley), 5, (255, 200, 0), -1)
        cv2.circle(image, (rex, rey), 5, (255, 200, 0), -1)
        cv2.line(image, (lex, ley), (rex, rey), (255, 200, 0), 1)
    
    # --- BODY VISUALIZATION ---
    if results.pose_landmarks:
        pose = results.pose_landmarks.landmark
        left_shoulder = pose[mp_holistic.PoseLandmark.LEFT_SHOULDER]
        right_shoulder = pose[mp_holistic.PoseLandmark.RIGHT_SHOULDER]
        
        if left_shoulder.visibility > 0.5 and right_shoulder.visibility > 0.5:
            # Draw shoulders
            lsx, lsy = int(left_shoulder.x * w), int(left_shoulder.y * h)
            rsx, rsy = int(right_shoulder.x * w), int(right_shoulder.y * h)
            cv2.circle(image, (lsx, lsy), 8, (255, 100, 0), -1)
            cv2.circle(image, (rsx, rsy), 8, (255, 100, 0), -1)
            cv2.line(image, (lsx, lsy), (rsx, rsy), (255, 100, 0), 2)
            
            # Draw shoulder center
            shoulder_center_x = (left_shoulder.x + right_shoulder.x) / 2
            shoulder_center_y = (left_shoulder.y + right_shoulder.y) / 2
            scx, scy = int(shoulder_center_x * w), int(shoulder_center_y * h)
            cv2.circle(image, (scx, scy), 10, (0, 255, 255), -1)
            
            # Draw calibrated body center with zones
            if strafe_tracker.is_calibrated:
                ccx = int(strafe_tracker.calibrated_value[0] * w)
                ccy = int(strafe_tracker.calibrated_value[1] * h)
                
                # Deadzone (red)
                move_deadzone_px = int(MOVE_DEADZONE_RADIUS * w)
                cv2.circle(image, (ccx, ccy), move_deadzone_px, (0, 0, 255), 1)
                
                # Max radius (cyan)
                move_max_px = int(MOVE_MAX_RADIUS * w)
                cv2.circle(image, (ccx, ccy), move_max_px, (255, 255, 0), 1)
                
                # Center and line
                cv2.circle(image, (ccx, ccy), 4, (0, 0, 255), -1)
                cv2.line(image, (ccx, ccy), (scx, scy), (0, 200, 200), 2)
    
    # --- HAND VISUALIZATION ---
    mp_hands = mp.solutions.hands
    mp_drawing = mp.solutions.drawing_utils
    mp_drawing_styles = mp.solutions.drawing_styles
    
    # Draw left hand
    if results.left_hand_landmarks:
        mp_drawing.draw_landmarks(
            image,
            results.left_hand_landmarks,
            mp_hands.HAND_CONNECTIONS,
            mp_drawing_styles.get_default_hand_landmarks_style(),
            mp_drawing_styles.get_default_hand_connections_style()
        )
        # Show hand state
        if data_packet.get("has_left_hand"):
            left_hand = data_packet["left_hand"]
            if left_hand["is_open"]:
                state = "OPEN"
                color = (0, 255, 255)  # Yellow
            elif left_hand["is_closed"]:
                state = "CLOSED"
                color = (0, 165, 255)  # Orange
            else:
                state = "---"
                color = (200, 200, 200)
            palm = left_hand["palm"]
            px, py = int((palm["x"] / 2 + 0.5) * w), int((palm["y"] / 2 + 0.5) * h)
            cv2.putText(image, f"L: {state}", (px - 30, py - 20), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    
    # Draw right hand
    if results.right_hand_landmarks:
        mp_drawing.draw_landmarks(
            image,
            results.right_hand_landmarks,
            mp_hands.HAND_CONNECTIONS,
            mp_drawing_styles.get_default_hand_landmarks_style(),
            mp_drawing_styles.get_default_hand_connections_style()
        )
        # Show hand state
        if data_packet.get("has_right_hand"):
            right_hand = data_packet["right_hand"]
            if right_hand["is_open"]:
                state = "OPEN"
                color = (0, 255, 255)  # Yellow
            elif right_hand["is_pointing"]:
                state = "POINT"
                color = (0, 255, 0)  # Green when drawing
            else:
                state = "---"
                color = (200, 200, 200)
            palm = right_hand["palm"]
            px, py = int((palm["x"] / 2 + 0.5) * w), int((palm["y"] / 2 + 0.5) * h)
            cv2.putText(image, f"R: {state}", (px - 30, py - 20), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    
    # Show hand tracking status
    left_status = "L:Y" if data_packet.get("has_left_hand") else "L:-"
    right_status = "R:Y" if data_packet.get("has_right_hand") else "R:-"
    cv2.putText(image, f"Hands: {left_status} {right_status}", 
               (10, 105), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 150, 255), 1)
    
    # --- GESTURE DRAWING VISUALIZATION ---
    if gesture_tracker is not None:
        gesture_state = data_packet.get("gesture_state", "idle")
        
        # Show gesture state
        state_colors = {
            "idle": (150, 150, 150),
            "ready_to_draw": (0, 255, 255),  # Yellow
            "drawing": (0, 255, 0),  # Green
        }
        state_color = state_colors.get(gesture_state, (150, 150, 150))
        cv2.putText(image, f"Cipher: {gesture_state.upper()}", 
                   (10, 130), cv2.FONT_HERSHEY_SIMPLEX, 0.5, state_color, 2)
        
        # Draw the current stroke
        if gesture_tracker.is_drawing and len(gesture_tracker.current_stroke) > 1:
            points = gesture_tracker.current_stroke
            num_points = len(points)
            cv2.putText(image, f"Points: {num_points}", 
                       (10, 155), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
            
            # Convert normalized coordinates to pixel coordinates
            # Points are in normalized space (-1 to 1), need to map to screen
            for i in range(1, len(points)):
                # Map from gesture coord space to screen
                x1 = int((points[i-1][0] / 2 + 0.5) * w)
                y1 = int((points[i-1][1] / 2 + 0.5) * h)
                x2 = int((points[i][0] / 2 + 0.5) * w)
                y2 = int((points[i][1] / 2 + 0.5) * h)
                
                # Draw line segment with gradient color (cyan to green)
                progress = i / len(points)
                color = (int(255 * (1 - progress)), 255, int(255 * progress))
                cv2.line(image, (x1, y1), (x2, y2), color, 3)
        
        # Show recognized gesture if any
        recognized = data_packet.get("gesture_recognized")
        if recognized:
            score = data_packet.get("gesture_score", 0)
            cv2.putText(image, f"SPELL: {recognized.upper()} ({score:.0%})", 
                       (w // 2 - 100, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)


if __name__ == "__main__":
    main()