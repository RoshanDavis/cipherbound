import cv2
import mediapipe as mp

from config import WEBCAM_ID, DEBUG_MODE, UDP_IP, UDP_PORT
from config import LOOK_DEADZONE_RADIUS, LOOK_MAX_RADIUS
from config import MOVE_DEADZONE_RADIUS, MOVE_MAX_RADIUS
from network import UDPSender
from trackers import LookTracker, StrafeTracker, DepthTracker


def main():
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
    
    print(f"--- CIPHERBOUND VISION SERVER ---")
    print(f"Target: {UDP_IP}:{UDP_PORT}")
    print(f"Press 'ESC' to quit, 'R' to recalibrate")
    print(f"Mode: Holistic (Face + Body + Depth)")
    
    cap = cv2.VideoCapture(WEBCAM_ID)
    
    while cap.isOpened():
        success, image = cap.read()
        if not success:
            print("Ignoring empty camera frame.")
            continue
        
        # Flip for selfie-view
        image = cv2.flip(image, 1)
        h, w, _ = image.shape
        
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
                      body_offset, mp_holistic)
            
            cv2.imshow('Cipherbound Vision Eye', image)
            key = cv2.waitKey(5) & 0xFF
            
            if key == 27:  # ESC
                break
            elif key == ord('r') or key == ord('R'):
                look_tracker.reset_calibration()
                strafe_tracker.reset_calibration()
                depth_tracker.reset_calibration()
                print("Recalibrating...")
    
    # Cleanup
    cap.release()
    holistic.close()
    sender.close()
    cv2.destroyAllWindows()


def draw_debug(image, results, data_packet, look_tracker, strafe_tracker, depth_tracker, body_offset, mp_holistic):
    """Draw debug visualization on the image."""
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


if __name__ == "__main__":
    main()