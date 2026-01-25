"""
Hand tracking for first-person arm visualization and gesture recognition.

Tracks both hands using MediaPipe Holistic hand landmarks.
Converts 2D screen positions to normalized coordinates for 3D positioning in Godot.

Simplified Gesture System:
- Left hand (control): Open = drawing mode ON, Closed (not open) = cancel/OFF
- Right hand (drawing): Open = idle, Pointing (not open) = draws in drawing mode

Open Detection:
- Hand is considered "open" when fingertips are far from palm center
- Hand is considered "closed/pointing" when fingertips are close to palm center
"""
import math
from typing import Optional, Dict, List, Tuple


class HandTracker:
    """
    Tracks hand positions and key landmarks for first-person arm rendering.
    
    For FPS arms, we primarily care about:
    - Wrist position (base of the arm)
    - Palm center (for general hand position)
    - Fingertips (for gesture detection and visual feedback)
    - Hand open/closed state (for grab/cast detection)
    """
    
    # MediaPipe hand landmark indices
    WRIST = 0
    THUMB_CMC = 1
    THUMB_MCP = 2
    THUMB_IP = 3
    THUMB_TIP = 4
    INDEX_MCP = 5   # Base of index finger
    INDEX_PIP = 6
    INDEX_DIP = 7
    INDEX_TIP = 8
    MIDDLE_MCP = 9  # Base of middle finger
    MIDDLE_PIP = 10
    MIDDLE_DIP = 11
    MIDDLE_TIP = 12
    RING_MCP = 13
    RING_PIP = 14
    RING_DIP = 15
    RING_TIP = 16
    PINKY_MCP = 17  # Base of pinky
    PINKY_PIP = 18
    PINKY_DIP = 19
    PINKY_TIP = 20
    
    def __init__(self):
        self.smoothing = 0.3  # Position smoothing factor
        self.prev_left: Optional[Dict] = None
        self.prev_right: Optional[Dict] = None
        
        # Persistent gesture states - retained when hand is temporarily lost
        self.left_gesture_state = {"is_open": False, "is_closed": True, "is_pointing": False}
        self.right_gesture_state = {"is_open": False, "is_closed": False, "is_pointing": True}
        
        # Debounce counters - require consistent detection for N frames before changing state
        self.debounce_frames = 4  # Number of frames required to confirm gesture change
        self.left_open_counter = 0   # Counts consecutive frames where left hand is detected as open
        self.right_open_counter = 0  # Counts consecutive frames where right hand is detected as open
    
    def process(self, left_hand_landmarks, right_hand_landmarks, 
                image_width: int = 640, image_height: int = 480) -> Dict:
        """
        Process both hands and return position data.
        
        Gesture states persist when hands are temporarily lost (moved too fast,
        out of frame, etc.) and only update when the hand is detected again.
        
        Args:
            left_hand_landmarks: MediaPipe left hand landmarks (or None)
            right_hand_landmarks: MediaPipe right hand landmarks (or None)
            image_width, image_height: Frame dimensions for aspect ratio
            
        Returns:
            Dict with left_hand and right_hand data
        """
        result = {
            "has_left_hand": False,
            "has_right_hand": False,
            "left_hand": self._empty_hand_data(),
            "right_hand": self._empty_hand_data()
        }
        
        # Process left hand
        if left_hand_landmarks:
            result["has_left_hand"] = True
            hand_data = self._extract_hand_data(left_hand_landmarks, image_width, image_height, is_left=True)
            result["left_hand"] = self._smooth_hand(hand_data, self.prev_left)
            self.prev_left = result["left_hand"]
            
            # Debounce gesture state change for left hand
            detected_open = hand_data["is_open"]
            current_open = self.left_gesture_state["is_open"]
            
            if detected_open != current_open:
                # Gesture differs from current state - increment counter
                self.left_open_counter += 1
                
                # Check if we've reached the threshold to change state
                if self.left_open_counter >= self.debounce_frames:
                    self.left_gesture_state = {"is_open": detected_open, "is_closed": not detected_open, "is_pointing": False}
                    self.left_open_counter = 0  # Reset counter after state change
            else:
                # Gesture matches current state - reset counter
                self.left_open_counter = 0
            
            # Apply debounced gesture state
            result["left_hand"]["is_open"] = self.left_gesture_state["is_open"]
            result["left_hand"]["is_closed"] = self.left_gesture_state["is_closed"]
            result["left_hand"]["is_pointing"] = self.left_gesture_state["is_pointing"]
        else:
            # Hand not detected - use last known gesture state with last position
            if self.prev_left is not None:
                result["left_hand"] = self.prev_left.copy()
            # Apply persistent gesture state
            result["left_hand"]["is_open"] = self.left_gesture_state["is_open"]
            result["left_hand"]["is_closed"] = self.left_gesture_state["is_closed"]
            result["left_hand"]["is_pointing"] = self.left_gesture_state["is_pointing"]
        
        # Process right hand
        if right_hand_landmarks:
            result["has_right_hand"] = True
            hand_data = self._extract_hand_data(right_hand_landmarks, image_width, image_height, is_left=False)
            result["right_hand"] = self._smooth_hand(hand_data, self.prev_right)
            self.prev_right = result["right_hand"]
            
            # Debounce gesture state change for right hand
            detected_open = hand_data["is_open"]
            current_open = self.right_gesture_state["is_open"]
            
            if detected_open != current_open:
                # Gesture differs from current state - increment counter
                self.right_open_counter += 1
                
                # Check if we've reached the threshold to change state
                if self.right_open_counter >= self.debounce_frames:
                    self.right_gesture_state = {"is_open": detected_open, "is_closed": False, "is_pointing": not detected_open}
                    self.right_open_counter = 0  # Reset counter after state change
            else:
                # Gesture matches current state - reset counter
                self.right_open_counter = 0
            
            # Apply debounced gesture state
            result["right_hand"]["is_open"] = self.right_gesture_state["is_open"]
            result["right_hand"]["is_closed"] = self.right_gesture_state["is_closed"]
            result["right_hand"]["is_pointing"] = self.right_gesture_state["is_pointing"]
        else:
            # Hand not detected - use last known gesture state with last position
            if self.prev_right is not None:
                result["right_hand"] = self.prev_right.copy()
            # Apply persistent gesture state
            result["right_hand"]["is_open"] = self.right_gesture_state["is_open"]
            result["right_hand"]["is_closed"] = self.right_gesture_state["is_closed"]
            result["right_hand"]["is_pointing"] = self.right_gesture_state["is_pointing"]
        
        return result
    
    def _empty_hand_data(self) -> Dict:
        """Return empty hand data structure."""
        return {
            "wrist": {"x": 0.0, "y": 0.0, "z": 0.0},
            "palm": {"x": 0.0, "y": 0.0, "z": 0.0},
            "index_tip": {"x": 0.0, "y": 0.0, "z": 0.0},
            "thumb_tip": {"x": 0.0, "y": 0.0, "z": 0.0},
            "is_open": False,        # Hand open (fingers extended from palm)
            "is_pointing": False,    # Right hand: not open = pointing
            "is_closed": False       # Left hand: not open = closed
        }
    
    def _extract_hand_data(self, landmarks, img_w: int, img_h: int, is_left: bool = True) -> Dict:
        """Extract relevant hand data from landmarks."""
        lm = landmarks.landmark
        
        # Get key positions (normalized 0-1, with z for depth)
        wrist = lm[self.WRIST]
        index_tip = lm[self.INDEX_TIP]
        thumb_tip = lm[self.THUMB_TIP]
        
        # Calculate palm center (average of MCP joints)
        index_mcp = lm[self.INDEX_MCP]
        middle_mcp = lm[self.MIDDLE_MCP]
        pinky_mcp = lm[self.PINKY_MCP]
        
        palm_x = (index_mcp.x + middle_mcp.x + pinky_mcp.x + wrist.x) / 4
        palm_y = (index_mcp.y + middle_mcp.y + pinky_mcp.y + wrist.y) / 4
        palm_z = (index_mcp.z + middle_mcp.z + pinky_mcp.z + wrist.z) / 4
        
        # Convert to centered coordinates (-1 to 1 range, 0 = center)
        # X: left = -1, right = 1
        # Y: up = -1, down = 1 (screen coords, will flip in Godot)
        def to_centered(x, y, z):
            return {
                "x": (x - 0.5) * 2,  # -1 to 1
                "y": (y - 0.5) * 2,  # -1 to 1
                "z": z * -1  # Flip Z so closer = positive
            }
        
        # Detect if hand is open by checking if fingers are extended
        is_open = self._is_hand_open(lm)
        
        # Simple two-state logic per hand:
        # Left hand: open or closed (not open = closed)
        # Right hand: open or pointing (not open = pointing)
        is_closed = False
        is_pointing = False
        
        if is_left:
            # Left hand: if not open, it's closed
            is_closed = not is_open
        else:
            # Right hand: if not open, it's pointing
            is_pointing = not is_open
        
        return {
            "wrist": to_centered(wrist.x, wrist.y, wrist.z),
            "palm": to_centered(palm_x, palm_y, palm_z),
            "index_tip": to_centered(index_tip.x, index_tip.y, index_tip.z),
            "thumb_tip": to_centered(thumb_tip.x, thumb_tip.y, thumb_tip.z),
            "is_open": is_open,
            "is_pointing": is_pointing,
            "is_closed": is_closed
        }
    
    def _is_hand_open(self, landmarks) -> bool:
        """
        Detect if hand is open by comparing fingertip distances to knuckle distances.
        
        Logic: If fingertips are significantly farther from wrist than knuckles,
        the fingers are extended (hand is open). If fingertips are close to or
        nearer than knuckles, fingers are curled (hand is closed/pointing).
        
        This approach is scale-invariant - works regardless of hand size or
        distance from camera because we compare ratios, not absolute distances.
        
        Args:
            landmarks: MediaPipe hand landmark list
            
        Returns:
            True if hand is open (fingers extended), False if closed/pointing
        """
        wrist = landmarks[self.WRIST]
        
        # Check each finger (excluding thumb - it behaves differently)
        finger_tips = [self.INDEX_TIP, self.MIDDLE_TIP, self.RING_TIP, self.PINKY_TIP]
        finger_mcps = [self.INDEX_MCP, self.MIDDLE_MCP, self.RING_MCP, self.PINKY_MCP]
        
        extended_count = 0
        
        for tip_idx, mcp_idx in zip(finger_tips, finger_mcps):
            tip = landmarks[tip_idx]
            mcp = landmarks[mcp_idx]
            
            # Calculate 2D distances from wrist (more reliable than 3D)
            tip_dist = math.sqrt((tip.x - wrist.x) ** 2 + (tip.y - wrist.y) ** 2)
            mcp_dist = math.sqrt((mcp.x - wrist.x) ** 2 + (mcp.y - wrist.y) ** 2)
            
            # Finger is extended if tip is farther from wrist than knuckle
            # Using 1.2 ratio to account for slight curl in relaxed open hand
            if tip_dist > mcp_dist * 1.2:
                extended_count += 1
        
        # Hand is "open" if at least 3 fingers are extended
        return extended_count >= 3
    
    def _smooth_hand(self, current: Dict, previous: Optional[Dict]) -> Dict:
        """Apply smoothing to hand positions."""
        if previous is None:
            return current
        
        def smooth_point(curr: Dict, prev: Dict) -> Dict:
            return {
                "x": prev["x"] + (curr["x"] - prev["x"]) * self.smoothing,
                "y": prev["y"] + (curr["y"] - prev["y"]) * self.smoothing,
                "z": prev["z"] + (curr["z"] - prev["z"]) * self.smoothing
            }
        
        return {
            "wrist": smooth_point(current["wrist"], previous["wrist"]),
            "palm": smooth_point(current["palm"], previous["palm"]),
            "index_tip": smooth_point(current["index_tip"], previous["index_tip"]),
            "thumb_tip": smooth_point(current["thumb_tip"], previous["thumb_tip"]),
            "is_open": current["is_open"],
            "is_pointing": current["is_pointing"],
            "is_closed": current["is_closed"]
        }
    
    def get_drawing_point(self, hand_data: Dict) -> Optional[Tuple[float, float]]:
        """
        Get the point to use for gesture drawing (index fingertip).
        Returns None if not in drawing mode.
        
        For cipher casting: draw when pointing (index extended), stop when open/fist.
        """
        if hand_data["is_pointing"]:
            return (hand_data["index_tip"]["x"], hand_data["index_tip"]["y"])
        return None
