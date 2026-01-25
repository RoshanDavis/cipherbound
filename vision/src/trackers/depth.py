import math
from .base import BaseTracker
from config import DEPTH_DEADZONE, DEPTH_MAX


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
        """
        Initialize the DepthTracker and apply depth configuration.
        
        Initializes the base tracker state and sets the tracker-specific parameters:
        - deadzone: threshold within which small depth changes are ignored (from DEPTH_DEADZONE).
        - max_change: maximum relative change used to scale depth movement (from DEPTH_MAX).
        """
        super().__init__()
        self.deadzone = DEPTH_DEADZONE
        self.max_change = DEPTH_MAX
    
    def _complete_calibration(self):
        """
        Set the tracker's calibrated neutral eye distance by averaging collected calibration samples.
        
        Calculates the mean of self.calibration_samples, stores it in self.calibrated_value, and emits a console message with the calibrated distance.
        """
        avg_distance = sum(self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = avg_distance
        print(f"Depth Calibrated! Neutral eye distance: {avg_distance:.4f}")
    
    def calculate_eye_distance(self, face_landmarks) -> float:
        """
        Compute the Euclidean distance between the outer corners of the left and right eyes.
        
        Parameters:
            face_landmarks: An object with a `landmark` sequence of normalized points (x, y) such as MediaPipe face landmarks. The landmarks at indices LEFT_EYE_OUTER and RIGHT_EYE_OUTER are used.
        
        Returns:
            distance (float): Euclidean distance between the two eye landmarks in normalized landmark coordinates (x/y space).
        """
        left_eye = face_landmarks.landmark[self.LEFT_EYE_OUTER]
        right_eye = face_landmarks.landmark[self.RIGHT_EYE_OUTER]
        
        # Calculate Euclidean distance
        dx = right_eye.x - left_eye.x
        dy = right_eye.y - left_eye.y
        distance = math.sqrt(dx**2 + dy**2)
        
        return distance
    
    def process(self, face_landmarks) -> dict:
        """
        Estimate forward/backward movement from face landmarks by comparing current eye distance to the calibrated neutral.
        
        Parameters:
            face_landmarks: MediaPipe face landmarks object or None. When None, no measurement is produced and defaults are returned.
        
        Returns:
            dict: {
                'lean_y': float — Signed magnitude in the range [-1, 1] representing forward/backward movement (positive = forward/closer, negative = backward/farther),
                'eye_distance': float — Euclidean distance between the left and right outer eye landmarks (current measurement)
            }
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
        """
        Return internal calibration and configuration values useful for debugging visualizations.
        
        Returns:
            dict: Mapping with keys:
                - calibrated_distance (float): Calibrated neutral eye distance.
                - deadzone (float): Deadzone threshold applied to relative change.
                - max_change (float): Maximum relative change used to map eye-distance change to lean.
        """
        return {
            "calibrated_distance": self.calibrated_value,
            "deadzone": self.deadzone,
            "max_change": self.max_change
        }