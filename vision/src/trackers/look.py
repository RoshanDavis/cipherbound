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
        """
        Initialize the LookTracker and set its deadzone and maximum radius from configuration.
        
        Calls the BaseTracker initializer, then sets `deadzone` to LOOK_DEADZONE_RADIUS and `max_radius` to LOOK_MAX_RADIUS.
        """
        super().__init__()
        self.deadzone = LOOK_DEADZONE_RADIUS
        self.max_radius = LOOK_MAX_RADIUS
    
    def _complete_calibration(self):
        """
        Compute the average of collected calibration samples and store it as the calibrated center.
        
        Sets self.calibrated_value to a (x, y) tuple representing the mean nose position from self.calibration_samples. Also prints a brief confirmation message with the computed center coordinates.
        """
        avg_x = sum(s[0] for s in self.calibration_samples) / len(self.calibration_samples)
        avg_y = sum(s[1] for s in self.calibration_samples) / len(self.calibration_samples)
        self.calibrated_value = (avg_x, avg_y)
        print(f"Face Calibrated! Center: ({avg_x:.3f}, {avg_y:.3f})")
    
    def process(self, nose_x: float, nose_y: float, 
                body_offset: Tuple[float, float] = (0.0, 0.0)) -> dict:
        """
                Convert a nose position into a normalized look vector representing camera direction.
                
                If the tracker is still calibrating, the current sample is recorded and (0.0, 0.0) is returned. Once calibrated, the calibrated center is adjusted by `body_offset`; the nose offset from that center is interpreted like a joystick: offsets within the deadzone produce no movement, and offsets between the deadzone edge and `max_radius` are scaled to a magnitude in [0, 1] along the computed angle.
                
                Parameters:
                    nose_x (float): Normalized nose X position.
                    nose_y (float): Normalized nose Y position.
                    body_offset (Tuple[float, float], optional): X/Y offset to apply to the calibrated center to compensate for body lean. Defaults to (0.0, 0.0).
                
                Returns:
                    dict: A mapping with keys `look_x` and `look_y` containing scaled look values in the range [-1.0, 1.0]. When inside the deadzone or during calibration, both values are 0.0.
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
        """
        Get the calibrated center point adjusted by an optional body offset.
        
        Parameters:
            body_offset (Tuple[float, float]): (x, y) offset to apply to the calibrated center to compensate for body position.
        
        Returns:
            adjusted_center (Optional[Tuple[float, float]]): Adjusted (x, y) center coordinates if calibration is complete, otherwise `None`.
        """
        if not self.is_calibrated:
            return None
        return (
            self.calibrated_value[0] + body_offset[0],
            self.calibrated_value[1] + body_offset[1]
        )