import math
from typing import Tuple
from .base import BaseTracker
from config import MOVE_DEADZONE_RADIUS, MOVE_MAX_RADIUS


class StrafeTracker(BaseTracker):
    """
    Tracks shoulder position for left/right strafe movement.
    Body lean left/right controls strafing.
    """
    
    def __init__(self):
        """
        Initialize a StrafeTracker with calibration and movement bounds.
        
        Sets the deadzone and maximum movement radius from module constants and initializes the current body offset to (0.0, 0.0) for use by other trackers.
        
        Attributes:
            deadzone (float): Radius within which horizontal offset is ignored.
            max_radius (float): Maximum radius used to normalize horizontal offset into a signed magnitude.
            current_offset (Tuple[float, float]): Latest shoulder-center offset used by other trackers.
        """
        super().__init__()
        self.deadzone = MOVE_DEADZONE_RADIUS
        self.max_radius = MOVE_MAX_RADIUS
        self.current_offset = (0.0, 0.0)  # Store for other trackers to use
    
    def _complete_calibration(self):
        """
        Compute the calibrated shoulder-center from collected calibration samples and store it.
        
        Calculates the mean x and y from self.calibration_samples and assigns the tuple (avg_x, avg_y) to self.calibrated_value. Also prints the calibrated center coordinates.
        """
        avg_x = sum(s[0] for s in self.calibration_samples) / len(self.calibration_samples)
        avg_y = sum(s[1] for s in self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = (avg_x, avg_y)
        print(f"Body Calibrated! Center: ({avg_x:.3f}, {avg_y:.3f})")
    
    def process(self, shoulder_center_x: float, shoulder_center_y: float) -> dict:
        """
        Compute strafe lean and body offset from shoulder-center coordinates.
        
        While calibration is ongoing, the sample is recorded and the returned lean is 0. After calibration, the shoulder position is compared to the calibrated center to produce:
        - `lean_x`: signed horizontal strafe value in the range -1.0 to 1.0, applying a deadzone and clamping to the configured max radius.
        - `body_offset`: tuple (offset_x, offset_y) of the raw offset from the calibrated center.
        
        Parameters:
            shoulder_center_x (float): Normalized horizontal shoulder center (0.0 to 1.0).
            shoulder_center_y (float): Normalized vertical shoulder center (0.0 to 1.0).
        
        Returns:
            dict: {
                'lean_x': float,       # signed strafe magnitude (-1.0 to 1.0)
                'body_offset': (float, float)  # (offset_x, offset_y) from calibrated center
            }
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
            if max_effective <= 0:
                magnitude = 1.0  # Fallback to max if config is invalid
            else:
                magnitude = min(effective_distance / max_effective, 1.0)
            result["lean_x"] = math.copysign(magnitude, offset_x)
        
        return result
    
    def get_body_offset(self) -> Tuple[float, float]:
        """
        Return the current body offset used by other trackers.
        
        Returns:
            Tuple[float, float]: (offset_x, offset_y) latest shoulder-center offset in tracker coordinates.
        """
        return self.current_offset