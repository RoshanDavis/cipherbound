"""
Line Direction Tester

A standalone test mode to verify that individual line directions are 
detected accurately. This is essential for building reliable shape recognition.

Usage:
  python line_tester.py

Draw single lines in the webcam view and see which direction is detected.
Press 'R' to reset, 'ESC' to quit.
"""
import cv2
import numpy as np
import math
import sys
import os

# Add parent to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import WEBCAM_ID
import mediapipe as mp


# Direction constants and names
DIR_NAMES = ['↑ UP', '↗ UP-RIGHT', '→ RIGHT', '↘ DOWN-RIGHT', 
             '↓ DOWN', '↙ DOWN-LEFT', '← LEFT', '↖ UP-LEFT']
DIR_COLORS = [
    (0, 255, 0),    # UP - Green
    (0, 255, 255),  # UP-RIGHT - Yellow
    (0, 165, 255),  # RIGHT - Orange
    (0, 0, 255),    # DOWN-RIGHT - Red
    (255, 0, 255),  # DOWN - Magenta
    (255, 0, 0),    # DOWN-LEFT - Blue
    (255, 255, 0),  # LEFT - Cyan
    (128, 255, 128) # UP-LEFT - Light Green
]


def angle_to_direction(angle: float) -> int:
    """Convert angle (radians) to 8-direction code."""
    # Normalize to 0-2π
    angle = angle % (2 * math.pi)
    if angle < 0:
        angle += 2 * math.pi
    
    # Each direction spans 45° (π/4), centered
    adjusted = (angle + math.pi / 8) % (2 * math.pi)
    direction = int(adjusted / (math.pi / 4)) % 8
    
    # Map from angle-based to our direction scheme
    mapping = [2, 3, 4, 5, 6, 7, 0, 1]
    return mapping[direction]


def detect_line_direction(points: list) -> tuple:
    """
    Detect the primary direction of a line from points.
    
    Returns: (direction_code, confidence, start_point, end_point)
    """
    if len(points) < 2:
        return None, 0.0, None, None
    
    pts = np.array(points, dtype=np.float32)
    
    # Get start and end points
    start = pts[0]
    end = pts[-1]
    
    # Calculate overall direction vector
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    
    length = math.sqrt(dx*dx + dy*dy)
    if length < 0.05:  # Minimum line length threshold
        return None, 0.0, start, end
    
    # Calculate angle
    angle = math.atan2(dy, dx)
    direction = angle_to_direction(angle)
    
    # Calculate confidence based on line straightness
    # Compare total path length to direct distance
    total_length = 0.0
    for i in range(len(pts) - 1):
        seg_dx = pts[i+1][0] - pts[i][0]
        seg_dy = pts[i+1][1] - pts[i][1]
        total_length += math.sqrt(seg_dx*seg_dx + seg_dy*seg_dy)
    
    straightness = length / total_length if total_length > 0 else 0
    confidence = straightness  # 1.0 = perfectly straight
    
    return direction, confidence, start, end


def main():
    print("=== LINE DIRECTION TESTER ===")
    print("Draw single lines to test direction detection")
    print("Press 'R' to reset, 'ESC' to quit")
    print()
    
    cap = cv2.VideoCapture(WEBCAM_ID)
    if not cap.isOpened():
        print(f"ERROR: Could not open camera {WEBCAM_ID}")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    # MediaPipe hands
    mp_hands = mp.solutions.hands
    hands = mp_hands.Hands(
        min_detection_confidence=0.7,
        min_tracking_confidence=0.7,
        max_num_hands=1
    )
    
    # State
    is_drawing = False
    current_stroke = []
    last_direction = None
    last_confidence = 0.0
    last_start = None
    last_end = None
    
    cv2.namedWindow('Line Tester', cv2.WINDOW_AUTOSIZE)
    
    while True:
        success, image = cap.read()
        if not success:
            continue
        
        image = cv2.flip(image, 1)
        h, w = image.shape[:2]
        
        # Process with MediaPipe
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = hands.process(rgb)
        
        # Check for pointing gesture (index finger extended)
        hand_pointing = False
        index_x, index_y = 0, 0
        
        if results.multi_hand_landmarks:
            hand = results.multi_hand_landmarks[0]
            
            # Get index fingertip
            index_tip = hand.landmark[8]
            index_x = index_tip.x
            index_y = index_tip.y
            
            # Check if pointing (index extended, others curled)
            wrist = hand.landmark[0]
            index_mcp = hand.landmark[5]
            middle_tip = hand.landmark[12]
            
            # Simple check: index tip far from wrist, middle tip closer
            index_dist = math.sqrt((index_tip.x - wrist.x)**2 + (index_tip.y - wrist.y)**2)
            middle_dist = math.sqrt((middle_tip.x - wrist.x)**2 + (middle_tip.y - wrist.y)**2)
            mcp_dist = math.sqrt((index_mcp.x - wrist.x)**2 + (index_mcp.y - wrist.y)**2)
            
            hand_pointing = index_dist > mcp_dist * 1.3 and index_dist > middle_dist * 1.1
            
            # Draw hand landmarks
            for lm in hand.landmark:
                cx, cy = int(lm.x * w), int(lm.y * h)
                cv2.circle(image, (cx, cy), 3, (200, 200, 200), -1)
        
        # State machine
        if hand_pointing:
            if not is_drawing:
                # Start drawing
                is_drawing = True
                current_stroke = []
                last_direction = None
                print("[Drawing started]")
            
            # Add point
            current_stroke.append((index_x, index_y))
            
            # Draw current stroke
            if len(current_stroke) > 1:
                for i in range(1, len(current_stroke)):
                    x1 = int(current_stroke[i-1][0] * w)
                    y1 = int(current_stroke[i-1][1] * h)
                    x2 = int(current_stroke[i][0] * w)
                    y2 = int(current_stroke[i][1] * h)
                    cv2.line(image, (x1, y1), (x2, y2), (0, 255, 0), 3)
        else:
            if is_drawing:
                # End drawing - detect direction
                is_drawing = False
                if len(current_stroke) >= 5:
                    last_direction, last_confidence, last_start, last_end = detect_line_direction(current_stroke)
                    
                    if last_direction is not None:
                        print(f"Detected: {DIR_NAMES[last_direction]} ({last_confidence:.0%} straight)")
                    else:
                        print("Line too short or not detected")
                else:
                    print("Not enough points")
        
        # Draw last detected line
        if last_start is not None and last_end is not None and last_direction is not None:
            x1, y1 = int(last_start[0] * w), int(last_start[1] * h)
            x2, y2 = int(last_end[0] * w), int(last_end[1] * h)
            color = DIR_COLORS[last_direction]
            cv2.line(image, (x1, y1), (x2, y2), color, 4)
            cv2.circle(image, (x1, y1), 8, (255, 255, 255), -1)  # Start
            cv2.circle(image, (x2, y2), 8, color, -1)  # End
        
        # Draw UI
        cv2.rectangle(image, (0, 0), (w, 60), (40, 40, 40), -1)
        
        if last_direction is not None:
            text = f"DIRECTION: {DIR_NAMES[last_direction]}"
            color = DIR_COLORS[last_direction]
            cv2.putText(image, text, (10, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
            cv2.putText(image, f"Straightness: {last_confidence:.0%}", (10, 55), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
        else:
            cv2.putText(image, "Point with index finger to draw a line", 
                       (10, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (200, 200, 200), 2)
        
        # Draw direction legend on right side
        legend_x = w - 150
        cv2.putText(image, "DIRECTIONS:", (legend_x, 80), 
                   cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        for i, name in enumerate(DIR_NAMES):
            y = 100 + i * 20
            cv2.putText(image, name, (legend_x, y), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, DIR_COLORS[i], 1)
        
        # Status
        status = "DRAWING" if is_drawing else "READY"
        status_color = (0, 255, 0) if is_drawing else (200, 200, 200)
        cv2.putText(image, status, (w - 100, 35), 
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
        
        cv2.imshow('Line Tester', image)
        
        key = cv2.waitKey(5) & 0xFF
        if key == 27:  # ESC
            break
        elif key == ord('r') or key == ord('R'):
            last_direction = None
            last_start = None
            last_end = None
            current_stroke = []
            print("[Reset]")
    
    cap.release()
    hands.close()
    cv2.destroyAllWindows()
    print("Done.")


if __name__ == "__main__":
    main()
