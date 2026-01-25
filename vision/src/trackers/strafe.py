import math
from typing import Tuple
from .base import BaseTracker
from ..config import MOVE_DEADZONE_RADIUS, MOVE_MAX_RADIUS


class StrafeTracker(BaseTracker):
    """
    Tracks shoulder position for left/right strafe movement.
    Body lean left/right controls strafing.
    """
    
    def __init__(self):
        super().__init__()
        self.deadzone = MOVE_DEADZONE_RADIUS
        self.max_radius = MOVE_MAX_RADIUS
        self.current_offset = (0.0, 0.0)  # Store for other trackers to use
    
    def _complete_calibration(self):
        """Average all shoulder center samples."""
        avg_x = sum(s[0] for s in self.calibration_samples) / len(self.calibration_samples)
        avg_y = sum(s[1] for s in self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = (avg_x, avg_y)
        print(f"Body Calibrated! Center: ({avg_x:.3f}, {avg_y:.3f})")
    
    def process(self, shoulder_center_x: float, shoulder_center_y: float) -> dict:
        """
        Process shoulder center position and return strafe value.
        
        Args:
            shoulder_center_x, shoulder_center_y: Normalized shoulder center (0-1)
            
        Returns:
            dict with 'lean_x' (-1 to 1) and body_offset tuple
        """
        result = {"lean_x": 0.0, "body_offset": (0.0, 0.0)}
        
        # Calibration phase
        if not self.is_calibrated:
            self.add_calibration_sample((shoulder_center_x, shoulder_center_y))
            return result
        
        # Calculate offset from calibrated center
        offset_x = shoulder_center_x - self.calibrated_value[0]
        offset_y = shoulder_center_y - self.calibrated_value[1]
        
        # Store offset for look tracker compensation
        self.current_offset = (offset_x, offset_y)
        result["body_offset"] = self.current_offset
        
        # Apply joystick zones (X axis only for strafe)
        distance = abs(offset_x)
        
        if distance < self.deadzone:
            result["lean_x"] = 0.0
        else:
            effective_distance = distance - self.deadzone
            max_effective = self.max_radius - self.deadzone
            magnitude = min(effective_distance / max_effective, 1.0)
            result["lean_x"] = math.copysign(magnitude, offset_x)
        
        return result
    
    def get_body_offset(self) -> Tuple[float, float]:
        """Get current body offset for other trackers."""
        return self.current_offset
