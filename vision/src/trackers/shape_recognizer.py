"""
$1 Recognizer - Orientation-Sensitive Version

Based on the $1 Recognizer algorithm, but with ROTATION INVARIANCE DISABLED
so that orientation matters (^ is different from > is different from v).

Changes from standard $1:
- NO rotation to indicative angle (orientation matters)
- NO rotation search during matching (fixed orientation)
- Multiple templates for different stroke directions

Templates are defined in a separate method for easy customization.
"""
import math
from typing import List, Tuple, Optional, Dict
from dataclasses import dataclass


@dataclass
class ShapeResult:
    name: str
    confidence: float
    score: float  # Raw distance score


class Point:
    """Simple 2D point."""
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y


class DollarRecognizer:
    """
    $1 Recognizer - Orientation-Sensitive Version.
    
    Rotation invariance is DISABLED so that orientation matters.
    This means ^ (up) is recognized differently from > (right) or v (down).
    """
    
    # Algorithm parameters
    NUM_POINTS = 64           # Resample to this many points
    SQUARE_SIZE = 250.0       # Reference square size for scaling
    
    def __init__(self):
        self.templates: Dict[str, List[List[Point]]] = {}
        self._init_templates()
    
    def _init_templates(self):
        """
        Load gesture templates from cipher_templates.py configuration file.
        """
        from trackers.cipher_templates import CIPHER_TEMPLATES
        
        for name, template_list in CIPHER_TEMPLATES.items():
            for points in template_list:
                self.add_template(name, points)
    
    def add_template(self, name: str, points: List[Tuple[float, float]]):
        """Add a template gesture."""
        # Convert to Point objects and process
        point_list = [Point(x, y) for x, y in points]
        processed = self._process_points(point_list)
        
        if name not in self.templates:
            self.templates[name] = []
        self.templates[name].append(processed)
        print(f"[$1] Added template: {name} (total: {len(self.templates[name])})")
    
    def recognize(self, points: List[Tuple[float, float]]) -> Optional[ShapeResult]:
        """
        Recognize a gesture from a list of (x, y) points.
        
        Returns ShapeResult with name and confidence, or None if not recognized.
        """
        if len(points) < 5:
            print(f"[$1] Not enough points: {len(points)}")
            return None
        
        # Convert to Point objects and process
        input_points = [Point(x, y) for x, y in points]
        processed = self._process_points(input_points)
        
        # Find best matching template (NO rotation search - orientation matters!)
        best_distance = float('inf')
        best_name = None
        
        for name, template_list in self.templates.items():
            for template in template_list:
                # Direct path distance - no rotation
                distance = self._path_distance(processed, template)
                if distance < best_distance:
                    best_distance = distance
                    best_name = name
        
        if best_name is None:
            print("[$1] No templates matched")
            return None
        
        # Convert distance to confidence score (0-1)
        half_diagonal = 0.5 * math.sqrt(self.SQUARE_SIZE**2 + self.SQUARE_SIZE**2)
        score = 1.0 - (best_distance / half_diagonal)
        confidence = max(0.0, min(1.0, score))
        
        print(f"[$1] Best: {best_name} (dist={best_distance:.1f}, conf={confidence:.0%})")
        
        # Require minimum confidence
        if confidence < 0.65:
            print(f"[$1] Confidence too low")
            return None
        
        return ShapeResult(
            name=best_name,
            confidence=confidence,
            score=best_distance
        )
    
    def _process_points(self, points: List[Point]) -> List[Point]:
        """
        Apply preprocessing steps to normalize the gesture.
        
        NOTE: NO rotation normalization - we want orientation to matter!
        """
        # Step 1: Resample to fixed number of points
        resampled = self._resample(points, self.NUM_POINTS)
        
        # Step 2: Scale to reference square (preserves orientation)
        scaled = self._scale_to(resampled, self.SQUARE_SIZE)
        
        # Step 3: Translate centroid to origin
        translated = self._translate_to(scaled, Point(0, 0))
        
        return translated
    
    def _resample(self, points: List[Point], n: int) -> List[Point]:
        """Resample points to n equidistant points."""
        if len(points) < 2:
            return points
        
        path_length = self._path_length(points)
        if path_length < 0.001:
            return [points[0]] * n
        
        interval = path_length / (n - 1)
        
        new_points = [Point(points[0].x, points[0].y)]
        accumulated = 0.0
        i = 1
        
        while i < len(points) and len(new_points) < n:
            p1 = points[i - 1]
            p2 = points[i]
            d = self._distance(p1, p2)
            
            if d < 0.0001:
                i += 1
                continue
            
            if accumulated + d >= interval:
                t = (interval - accumulated) / d
                new_x = p1.x + t * (p2.x - p1.x)
                new_y = p1.y + t * (p2.y - p1.y)
                new_point = Point(new_x, new_y)
                new_points.append(new_point)
                
                # Continue from new point
                points = [new_point] + points[i:]
                accumulated = 0.0
                i = 1
            else:
                accumulated += d
                i += 1
        
        # Fill remaining points if needed
        while len(new_points) < n:
            new_points.append(Point(points[-1].x, points[-1].y))
        
        return new_points[:n]
    
    def _scale_to(self, points: List[Point], size: float) -> List[Point]:
        """Scale points to fit in a square of given size."""
        min_x = min(p.x for p in points)
        max_x = max(p.x for p in points)
        min_y = min(p.y for p in points)
        max_y = max(p.y for p in points)
        
        width = max_x - min_x
        height = max_y - min_y
        
        # Avoid division by zero
        if width < 0.001:
            width = 1.0
        if height < 0.001:
            height = 1.0
        
        # Use uniform scaling to preserve aspect ratio
        scale = size / max(width, height)
        
        scaled = []
        for p in points:
            new_x = (p.x - min_x) * scale
            new_y = (p.y - min_y) * scale
            scaled.append(Point(new_x, new_y))
        
        return scaled
    
    def _translate_to(self, points: List[Point], target: Point) -> List[Point]:
        """Translate points so centroid is at target."""
        c = self._centroid(points)
        translated = []
        for p in points:
            new_x = p.x + target.x - c.x
            new_y = p.y + target.y - c.y
            translated.append(Point(new_x, new_y))
        return translated
    
    def _path_distance(self, a: List[Point], b: List[Point]) -> float:
        """Calculate average distance between corresponding points."""
        if len(a) != len(b):
            return float('inf')
        
        total = sum(self._distance(a[i], b[i]) for i in range(len(a)))
        return total / len(a)
    
    def _path_length(self, points: List[Point]) -> float:
        """Calculate total path length."""
        total = 0.0
        for i in range(1, len(points)):
            total += self._distance(points[i-1], points[i])
        return total
    
    def _centroid(self, points: List[Point]) -> Point:
        """Calculate centroid of points."""
        x = sum(p.x for p in points) / len(points)
        y = sum(p.y for p in points) / len(points)
        return Point(x, y)
    
    def _distance(self, a: Point, b: Point) -> float:
        """Euclidean distance between two points."""
        return math.sqrt((a.x - b.x)**2 + (a.y - b.y)**2)


class GestureTracker:
    """Tracks drawing gestures and recognizes cipher shapes using $1 Recognizer."""
    
    def __init__(self):
        self.recognizer = DollarRecognizer()
        self.current_stroke: List[Tuple[float, float]] = []
        self.is_drawing = False
        self.min_points = 5
        self.point_distance_threshold = 0.003
        self.last_point: Optional[Tuple[float, float]] = None
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
