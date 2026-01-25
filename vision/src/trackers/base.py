from abc import ABC, abstractmethod
from typing import Optional, Tuple, List
from config import CALIBRATION_FRAMES


class BaseTracker(ABC):
    """Base class for all trackers with calibration support."""
    
    def __init__(self, calibration_frames: int = CALIBRATION_FRAMES):
        """
        Initialize the BaseTracker's calibration configuration and state.
        
        Parameters:
            calibration_frames (int): Number of samples required to complete calibration.
        """
        self.calibration_frames = calibration_frames
        self.calibration_samples: List = []
        self.calibrated_value: Optional[Tuple] = None
    
    @property
    def is_calibrated(self) -> bool:
        """
        Indicates whether the tracker has completed calibration.
        
        Returns:
            True if the tracker has a calibrated value, False otherwise.
        """
        return self.calibrated_value is not None
    
    @property
    def calibration_progress(self) -> float:
        """
        Report the tracker's calibration progress as a fraction between 0.0 and 1.0.
        
        Returns:
            float: `1.0` if the tracker is calibrated; otherwise the ratio of collected
            calibration samples to `calibration_frames` (expected range 0.0–1.0).
        """
        if self.is_calibrated:
            return 1.0
        return len(self.calibration_samples) / self.calibration_frames
    
    def reset_calibration(self):
        """
        Reset the tracker's calibration state.
        
        Clears any collected calibration samples and removes the stored calibrated value so calibration can be performed again.
        """
        self.calibration_samples = []
        self.calibrated_value = None
    
    def add_calibration_sample(self, sample):
        """
        Add a calibration sample and trigger completion when the configured number of samples is reached.
        
        Parameters:
            sample: A calibration sample (format depends on the concrete tracker). The sample is appended to internal storage; when the count of stored samples reaches `calibration_frames`, the tracker finalizes calibration.
        """
        self.calibration_samples.append(sample)
        if len(self.calibration_samples) >= self.calibration_frames:
            self._complete_calibration()
    
    @abstractmethod
    def _complete_calibration(self):
        """
        Compute and set the final calibrated value from collected calibration_samples.
        
        Called once the number of collected samples reaches calibration_frames; implementations should compute the tracker-specific calibrated value and assign it to self.calibrated_value.
        """
        pass
    
    @abstractmethod
    def process(self, *args, **kwargs) -> dict:
        """
        Process tracking input and produce a dictionary of results.
        
        Subclasses must implement this to perform tracker-specific processing using the provided positional and keyword arguments.
        
        Parameters:
            *args: Positional inputs required by the concrete tracker (interpretation is tracker-specific).
            **kwargs: Keyword inputs required by the concrete tracker (interpretation is tracker-specific).
        
        Returns:
            dict: Tracker-specific result dictionary (for example: position, confidence, and any metadata).
        """
        pass