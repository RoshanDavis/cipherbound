from abc import ABC, abstractmethod
from typing import Optional, Tuple, List
from config import CALIBRATION_FRAMES


class BaseTracker(ABC):
    """Base class for all trackers with calibration support."""
    
    def __init__(self, calibration_frames: int = CALIBRATION_FRAMES):
        # Validate calibration_frames is a positive integer
        calibration_frames = int(calibration_frames)
        if calibration_frames <= 0:
            raise ValueError(f"calibration_frames must be positive, got {calibration_frames}")
        self.calibration_frames = calibration_frames
        self.calibration_samples: List = []
        self.calibrated_value: Optional[Tuple] = None
    
    @property
    def is_calibrated(self) -> bool:
        return self.calibrated_value is not None
    
    @property
    def calibration_progress(self) -> float:
        """Returns calibration progress from 0.0 to 1.0"""
        if self.is_calibrated:
            return 1.0
        return len(self.calibration_samples) / self.calibration_frames
    
    def reset_calibration(self):
        """Reset calibration to start fresh."""
        self.calibration_samples = []
        self.calibrated_value = None
    
    def add_calibration_sample(self, sample):
        """Add a sample and check if calibration is complete."""
        self.calibration_samples.append(sample)
        if len(self.calibration_samples) >= self.calibration_frames:
            self._complete_calibration()
    
    @abstractmethod
    def _complete_calibration(self):
        """Override to compute final calibrated value from samples."""
        pass
    
    @abstractmethod
    def process(self, *args, **kwargs) -> dict:
        """Process tracking data and return results."""
        pass
