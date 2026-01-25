import math
from .base import BaseTracker
from ..config import DEPTH_DEADZONE, DEPTH_MAX


class DepthTracker(BaseTracker):
    """
    Tracks face size (eye distance) for forward/backward movement.
    
    - Leaning toward screen = face appears larger = walk forward
    - Leaning away = face appears smaller = walk backward
    """
    
    # Face mesh landmark indices
    LEFT_EYE_OUTER = 33   # Left eye outer corner
    RIGHT_EYE_OUTER = 263  # Right eye outer corner
    
    def __init__(self):
        super().__init__()
        self.deadzone = DEPTH_DEADZONE
        self.max_change = DEPTH_MAX
    
    def _complete_calibration(self):
        """Average all eye distance samples to find neutral distance."""
        avg_distance = sum(self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = avg_distance
        print(f"Depth Calibrated! Neutral eye distance: {avg_distance:.4f}")
    
    def calculate_eye_distance(self, face_landmarks) -> float:
        """Calculate normalized distance between outer eye corners."""
        left_eye = face_landmarks.landmark[self.LEFT_EYE_OUTER]
        right_eye = face_landmarks.landmark[self.RIGHT_EYE_OUTER]
        
        # Calculate Euclidean distance
        dx = right_eye.x - left_eye.x
        dy = right_eye.y - left_eye.y
        distance = math.sqrt(dx**2 + dy**2)
        
        return distance
    
    def process(self, face_landmarks) -> dict:
        """
        Process face landmarks and return depth/forward movement.
        
        Args:
            face_landmarks: MediaPipe face landmarks
            
        Returns:
            dict with 'lean_y' (-1 to 1): negative = back, positive = forward
        """
        result = {"lean_y": 0.0, "eye_distance": 0.0}
        
        if face_landmarks is None:
            return result
        
        # Calculate current eye distance
        eye_distance = self.calculate_eye_distance(face_landmarks)
        result["eye_distance"] = eye_distance
        
        # Calibration phase
        if not self.is_calibrated:
            self.add_calibration_sample(eye_distance)
            return result
        
        # Calculate relative change from calibrated distance
        # Positive change = face closer (larger) = move forward
        # Negative change = face farther (smaller) = move backward
        if self.calibrated_value == 0:
            print("Warning: calibrated_value is zero, skipping depth calculation")
            return result
        relative_change = (eye_distance - self.calibrated_value) / self.calibrated_value
        
        # Apply deadzone
        if abs(relative_change) < self.deadzone:
            result["lean_y"] = 0.0
        else:
            # Remove deadzone from calculation
            if relative_change > 0:
                effective_change = relative_change - self.deadzone
            else:
                effective_change = relative_change + self.deadzone
            
            # Map to -1 to 1 range
            max_effective = self.max_change - self.deadzone
            magnitude = min(abs(effective_change) / max_effective, 1.0)
            result["lean_y"] = math.copysign(magnitude, relative_change)
        
        return result
    
    def get_debug_info(self) -> dict:
        """Get debug information for visualization."""
        return {
            "calibrated_distance": self.calibrated_value,
            "deadzone": self.deadzone,
            "max_change": self.max_change
        }
