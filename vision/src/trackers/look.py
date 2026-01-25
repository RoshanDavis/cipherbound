import math
from typing import Tuple, Optional
from .base import BaseTracker
from config import LOOK_DEADZONE_RADIUS, LOOK_MAX_RADIUS


class LookTracker(BaseTracker):
    """
    Tracks nose position for camera look direction.
    Works like a joystick - offset from center = rotation speed.
    """
    
    def __init__(self):
        super().__init__()
        self.deadzone = LOOK_DEADZONE_RADIUS
        self.max_radius = LOOK_MAX_RADIUS
    
    def _complete_calibration(self):
        """Average all nose samples to find center."""
        avg_x = sum(s[0] for s in self.calibration_samples) / len(self.calibration_samples)
        avg_y = sum(s[1] for s in self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = (avg_x, avg_y)
        print(f"Face Calibrated! Center: ({avg_x:.3f}, {avg_y:.3f})")
    
    def process(self, nose_x: float, nose_y: float, 
                body_offset: Tuple[float, float] = (0.0, 0.0)) -> dict:
        """
        Process nose position and return look values.
        
        Args:
            nose_x, nose_y: Normalized nose position (0-1)
            body_offset: Body movement offset to compensate for leaning
            
        Returns:
            dict with 'look_x' and 'look_y' (-1 to 1)
        """
        result = {"look_x": 0.0, "look_y": 0.0}
        
        # Calibration phase
        if not self.is_calibrated:
            self.add_calibration_sample((nose_x, nose_y))
            return result
        
        # Adjust center based on body movement (so leaning doesn't rotate camera)
        adjusted_center_x = self.calibrated_value[0] + body_offset[0]
        adjusted_center_y = self.calibrated_value[1] + body_offset[1]
        
        # Calculate offset from adjusted center
        offset_x = nose_x - adjusted_center_x
        offset_y = nose_y - adjusted_center_y
        
        # Calculate distance (joystick displacement)
        distance = math.sqrt(offset_x**2 + offset_y**2)
        
        # Inside deadzone - no movement
        if distance < self.deadzone:
            return result
        
        # Calculate angle for direction
        angle = math.atan2(offset_y, offset_x)
        
        # Map distance from deadzone edge to max radius -> 0.0 to 1.0
        effective_distance = distance - self.deadzone
        max_effective = self.max_radius - self.deadzone
        if max_effective <= 0:
            magnitude = 0.0
        else:
            magnitude = min(effective_distance / max_effective, 1.0)
        
        # Convert back to X/Y using the angle
        result["look_x"] = math.cos(angle) * magnitude
        result["look_y"] = math.sin(angle) * magnitude
        
        return result
    
    def get_adjusted_center(self, body_offset: Tuple[float, float] = (0.0, 0.0)) -> Optional[Tuple[float, float]]:
        """Get the current adjusted center point for debug drawing."""
        if not self.is_calibrated:
            return None
        return (
            self.calibrated_value[0] + body_offset[0],
            self.calibrated_value[1] + body_offset[1]
        )
