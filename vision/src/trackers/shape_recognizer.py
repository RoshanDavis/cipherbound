"""
Shape recognition using OpenCV contour analysis and heuristics.

Uses multiple approaches for robust recognition:
1. Polygon approximation (corner counting)
2. Circularity measurement
3. Hu moments for template matching
4. Direction change analysis

This is more reliable than the $1 recognizer for simple geometric shapes.
"""
import cv2
import numpy as np
import math
from typing import List, Tuple, Optional, Dict
from dataclasses import dataclass


@dataclass
class ShapeResult:
    name: str
    confidence: float  # 0-1
    details: Dict  # Additional info for debugging


class ShapeRecognizer:
    """
    Recognizes basic shapes from point sequences using multiple methods.
    
    Supported shapes:
    - fire: Triangle pointing up (^)
    - water: Triangle pointing down (v)
    - shield: Circle or ellipse
    - lightning: Zigzag / Z-shape
    """
    
    def __init__(self):
        # Minimum points needed
        self.min_points = 10
        
        # Thresholds
        self.circle_threshold = 0.75  # How circular (0-1)
        self.triangle_threshold = 0.6
        self.zigzag_direction_changes = 2  # Minimum direction reversals for zigzag
        
    def recognize(self, points: List[Tuple[float, float]]) -> Optional[ShapeResult]:
        """
        Recognize a shape from a list of (x, y) points.
        
        Args:
            points: List of (x, y) coordinates (any scale)
            
        Returns:
            ShapeResult with name and confidence, or None if not recognized
        """
        if len(points) < self.min_points:
            print(f"[Shape] Not enough points: {len(points)}")
            return None
        
        # Convert to numpy array and normalize to 0-1000 range for cv2
        pts = np.array(points, dtype=np.float32)
        pts = self._normalize_points(pts)
        
        # Smooth the points to reduce noise
        pts = self._smooth_points(pts, window=5)
        
        # Calculate features
        features = self._extract_features(pts)
        
        # Debug output
        print(f"[Shape] {len(points)} points")
        print(f"  Corners: {features['corners']}, Circularity: {features['circularity']:.2f}")
        print(f"  Direction changes: {features['direction_changes']}, Aspect: {features['aspect_ratio']:.2f}")
        
        # Decision tree for shape classification
        result = self._classify_shape(features, pts)
        
        if result:
            print(f"  -> {result.name.upper()} ({result.confidence:.0%})")
        else:
            print(f"  -> Not recognized")
        
        return result
    
    def _normalize_points(self, pts: np.ndarray) -> np.ndarray:
        """Normalize points to a consistent scale (0-1000)."""
        min_vals = pts.min(axis=0)
        max_vals = pts.max(axis=0)
        
        # Avoid division by zero
        range_vals = max_vals - min_vals
        range_vals[range_vals == 0] = 1
        
        # Scale to 0-1000 range
        normalized = (pts - min_vals) / range_vals * 900 + 50  # Leave margin
        return normalized.astype(np.float32)
    
    def _smooth_points(self, pts: np.ndarray, window: int = 5) -> np.ndarray:
        """Apply moving average smoothing to reduce jitter."""
        if len(pts) < window:
            return pts
        
        smoothed = np.zeros_like(pts)
        half = window // 2
        
        for i in range(len(pts)):
            start = max(0, i - half)
            end = min(len(pts), i + half + 1)
            smoothed[i] = pts[start:end].mean(axis=0)
        
        return smoothed
    
    def _extract_features(self, pts: np.ndarray) -> Dict:
        """Extract shape features from points."""
        # Convert to integer for cv2 contour functions
        pts_int = pts.astype(np.int32).reshape((-1, 1, 2))
        
        # 1. Polygon approximation (Douglas-Peucker)
        perimeter = cv2.arcLength(pts_int, closed=True)
        epsilon = 0.02 * perimeter  # Approximation accuracy
        approx = cv2.approxPolyDP(pts_int, epsilon, closed=True)
        corners = len(approx)
        
        # Also try with different epsilon for triangle detection
        epsilon_triangle = 0.04 * perimeter
        approx_triangle = cv2.approxPolyDP(pts_int, epsilon_triangle, closed=True)
        corners_loose = len(approx_triangle)
        
        # 2. Circularity (4π × area / perimeter²) - 1.0 for perfect circle
        area = cv2.contourArea(pts_int)
        if perimeter > 0:
            circularity = 4 * math.pi * area / (perimeter * perimeter)
        else:
            circularity = 0
        
        # 3. Bounding box and aspect ratio
        x, y, w, h = cv2.boundingRect(pts_int)
        aspect_ratio = min(w, h) / max(w, h) if max(w, h) > 0 else 1
        
        # 4. Direction changes (for zigzag detection)
        direction_changes = self._count_direction_changes(pts)
        
        # 5. Convexity
        hull = cv2.convexHull(pts_int)
        hull_area = cv2.contourArea(hull)
        convexity = area / hull_area if hull_area > 0 else 0
        
        # 6. Check if shape is closed (start near end)
        start_end_dist = np.linalg.norm(pts[0] - pts[-1])
        is_closed = start_end_dist < perimeter * 0.15
        
        # 7. Centroid and orientation
        M = cv2.moments(pts_int)
        if M['m00'] > 0:
            cx = M['m10'] / M['m00']
            cy = M['m01'] / M['m00']
        else:
            cx, cy = pts.mean(axis=0)
        
        # 8. Check if triangle points up or down
        # Find the vertex farthest from the centroid
        distances = np.linalg.norm(pts - np.array([cx, cy]), axis=1)
        farthest_idx = np.argmax(distances)
        farthest_point = pts[farthest_idx]
        
        # If farthest point is above centroid, triangle points up
        points_up = farthest_point[1] < cy
        
        return {
            'corners': corners,
            'corners_loose': corners_loose,
            'circularity': circularity,
            'aspect_ratio': aspect_ratio,
            'direction_changes': direction_changes,
            'convexity': convexity,
            'is_closed': is_closed,
            'perimeter': perimeter,
            'area': area,
            'centroid': (cx, cy),
            'points_up': points_up,
            'approx_vertices': approx.reshape(-1, 2) if len(approx) > 0 else []
        }
    
    def _count_direction_changes(self, pts: np.ndarray) -> int:
        """Count significant direction changes in the stroke (for zigzag detection)."""
        if len(pts) < 3:
            return 0
        
        # Calculate direction vectors
        directions = np.diff(pts, axis=0)
        
        # Calculate angles
        angles = np.arctan2(directions[:, 1], directions[:, 0])
        
        # Smooth angles
        if len(angles) > 5:
            kernel = np.ones(5) / 5
            angles = np.convolve(angles, kernel, mode='valid')
        
        if len(angles) < 2:
            return 0
        
        # Count significant angle changes (> 60 degrees)
        angle_diffs = np.abs(np.diff(angles))
        # Handle wraparound
        angle_diffs = np.minimum(angle_diffs, 2 * np.pi - angle_diffs)
        
        significant_changes = np.sum(angle_diffs > math.radians(60))
        
        return significant_changes
    
    def _classify_shape(self, features: Dict, pts: np.ndarray) -> Optional[ShapeResult]:
        """Classify the shape based on extracted features."""
        
        scores = {}
        
        # === CIRCLE / SHIELD ===
        # High circularity, roughly equal aspect ratio, closed
        circle_score = 0.0
        if features['circularity'] > 0.5:
            circle_score = features['circularity']
            # Bonus for being closed
            if features['is_closed']:
                circle_score += 0.1
            # Bonus for good aspect ratio (not too elongated)
            if features['aspect_ratio'] > 0.7:
                circle_score += 0.1
        scores['shield'] = min(circle_score, 1.0)
        
        # === TRIANGLE (Fire/Water) ===
        # 3-4 corners when approximated, lower circularity
        triangle_score = 0.0
        if features['corners_loose'] in [3, 4] and features['circularity'] < 0.7:
            # Base score from corner count
            triangle_score = 0.7 if features['corners_loose'] == 3 else 0.5
            
            # Check convexity (triangles are convex)
            if features['convexity'] > 0.7:
                triangle_score += 0.2
            
            # Bonus for being closed
            if features['is_closed']:
                triangle_score += 0.1
        
        # Determine if fire (up) or water (down)
        if triangle_score > 0.5:
            if features['points_up']:
                scores['fire'] = triangle_score
                scores['water'] = triangle_score * 0.3  # Low score for wrong direction
            else:
                scores['water'] = triangle_score
                scores['fire'] = triangle_score * 0.3
        else:
            scores['fire'] = triangle_score
            scores['water'] = triangle_score
        
        # === ZIGZAG / LIGHTNING ===
        # Multiple direction changes, not circular, not closed
        zigzag_score = 0.0
        if features['direction_changes'] >= 2:
            # Base score from direction changes
            zigzag_score = min(0.5 + features['direction_changes'] * 0.15, 0.95)
            
            # Penalty for being too circular
            if features['circularity'] > 0.6:
                zigzag_score *= 0.5
            
            # Slight penalty for being closed (zigzags usually aren't)
            if features['is_closed']:
                zigzag_score *= 0.8
        scores['lightning'] = zigzag_score
        
        # === SELECT BEST MATCH ===
        if not scores:
            return None
        
        best_shape = max(scores, key=scores.get)
        best_score = scores[best_shape]
        
        # Require minimum confidence
        if best_score < 0.55:
            return None
        
        return ShapeResult(
            name=best_shape,
            confidence=best_score,
            details={
                'all_scores': scores,
                'features': features
            }
        )
    
    def visualize_on_image(self, image: np.ndarray, points: List[Tuple[float, float]], 
                          result: Optional[ShapeResult] = None) -> np.ndarray:
        """Draw the stroke and recognition result on an image for debugging."""
        if len(points) < 2:
            return image
        
        h, w = image.shape[:2]
        
        # Convert points to image coordinates (assuming -1 to 1 range)
        img_points = []
        for x, y in points:
            px = int((x / 2 + 0.5) * w)
            py = int((y / 2 + 0.5) * h)
            img_points.append((px, py))
        
        # Draw the stroke
        for i in range(1, len(img_points)):
            cv2.line(image, img_points[i-1], img_points[i], (0, 255, 255), 2)
        
        # Draw result text if recognized
        if result:
            text = f"{result.name.upper()} ({result.confidence:.0%})"
            cv2.putText(image, text, (10, h - 40), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
        
        return image


class GestureTracker:
    """
    Tracks drawing gestures and recognizes cipher shapes.
    Uses the improved ShapeRecognizer for better accuracy.
    """
    
    def __init__(self):
        self.recognizer = ShapeRecognizer()
        self.current_stroke: List[Tuple[float, float]] = []
        self.is_drawing = False
        self.min_points = 15
        self.point_distance_threshold = 0.008  # Minimum distance between points
        self.last_point: Optional[Tuple[float, float]] = None
        
        # Last recognition result
        self.last_result: Optional[ShapeResult] = None
    
    def start_drawing(self):
        """Begin a new gesture stroke."""
        self.current_stroke = []
        self.is_drawing = True
        self.last_point = None
        self.last_result = None
        print("[GestureTracker] Started drawing")
    
    def add_point(self, x: float, y: float):
        """Add a point to the current stroke."""
        if not self.is_drawing:
            return
        
        # Filter points that are too close together
        if self.last_point is not None:
            dist = math.sqrt((x - self.last_point[0])**2 + (y - self.last_point[1])**2)
            if dist < self.point_distance_threshold:
                return
        
        self.current_stroke.append((x, y))
        self.last_point = (x, y)
    
    def end_drawing(self) -> Optional[ShapeResult]:
        """End the current stroke and attempt recognition."""
        if not self.is_drawing:
            return None
        
        self.is_drawing = False
        print(f"[GestureTracker] Ended drawing with {len(self.current_stroke)} points")
        
        if len(self.current_stroke) < self.min_points:
            print(f"[GestureTracker] Not enough points: {len(self.current_stroke)}")
            self.last_result = None
            return None
        
        # Attempt recognition
        result = self.recognizer.recognize(self.current_stroke)
        self.last_result = result
        
        return result
    
    def cancel_drawing(self):
        """Cancel the current drawing without recognition."""
        print("[GestureTracker] Cancelled drawing")
        self.current_stroke = []
        self.is_drawing = False
        self.last_point = None
        self.last_result = None
    
    def get_stroke_for_display(self) -> List[Tuple[float, float]]:
        """Get the current stroke points for visualization."""
        return self.current_stroke.copy()
