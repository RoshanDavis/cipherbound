"""
Gesture recognition using the $1 Unistroke Recognizer algorithm.

This is a well-established algorithm for single-stroke gesture recognition that is:
- Rotation invariant (can draw shapes at any angle)
- Scale invariant (any size works)
- Fast and simple

Reference: Wobbrock, J.O., Wilson, A.D. and Li, Y. (2007) 
"Gestures without libraries, toolkits or training"
"""
import math
from typing import List, Tuple, Optional, Dict
from dataclasses import dataclass


@dataclass
class Point:
    x: float
    y: float


@dataclass 
class RecognitionResult:
    name: str
    score: float  # 0-1, higher is better


class DollarRecognizer:
    """
    $1 Unistroke Recognizer for cipher gesture detection.
    """
    
    def __init__(self):
        self.num_points = 64  # Resample to this many points
        self.square_size = 250.0  # Scale to this size
        self.origin = Point(0, 0)
        self.diagonal = math.sqrt(self.square_size**2 + self.square_size**2)
        self.half_diagonal = self.diagonal / 2.0
        self.angle_range = math.radians(45.0)
        self.angle_precision = math.radians(2.0)
        
        # Templates for each cipher shape
        self.templates: Dict[str, List[Point]] = {}
        self._init_templates()
    
    def _init_templates(self):
        """Initialize the cipher shape templates."""
        # Fire: Triangle pointing up (^) - multiple starting points and directions
        self.templates["fire"] = self._create_template([
            (0.5, 1.0),    # Bottom center
            (0.0, 0.0),    # Top left
            (1.0, 0.0),    # Top right  
            (0.5, 1.0),    # Close
        ])
        
        self.templates["fire_cw"] = self._create_template([
            (0.5, 1.0),    # Bottom center
            (1.0, 0.0),    # Top right
            (0.0, 0.0),    # Top left
            (0.5, 1.0),    # Close
        ])
        
        self.templates["fire_v1"] = self._create_template([
            (0.0, 1.0),    # Bottom left
            (0.5, 0.0),    # Top center
            (1.0, 1.0),    # Bottom right
            (0.0, 1.0),    # Close
        ])
        
        self.templates["fire_v2"] = self._create_template([
            (1.0, 1.0),    # Bottom right
            (0.5, 0.0),    # Top center
            (0.0, 1.0),    # Bottom left
            (1.0, 1.0),    # Close
        ])
        
        # Water: Triangle pointing down (v) - multiple directions
        self.templates["water"] = self._create_template([
            (0.5, 0.0),    # Top center
            (0.0, 1.0),    # Bottom left
            (1.0, 1.0),    # Bottom right
            (0.5, 0.0),    # Close
        ])
        
        self.templates["water_cw"] = self._create_template([
            (0.5, 0.0),    # Top center
            (1.0, 1.0),    # Bottom right
            (0.0, 1.0),    # Bottom left
            (0.5, 0.0),    # Close
        ])
        
        self.templates["water_v1"] = self._create_template([
            (0.0, 0.0),    # Top left
            (0.5, 1.0),    # Bottom center
            (1.0, 0.0),    # Top right
            (0.0, 0.0),    # Close
        ])
        
        self.templates["water_v2"] = self._create_template([
            (1.0, 0.0),    # Top right
            (0.5, 1.0),    # Bottom center
            (0.0, 0.0),    # Top left
            (1.0, 0.0),    # Close
        ])
        
        # Shield: Circle - both directions
        self.templates["shield"] = self._create_circle_template(clockwise=True)
        self.templates["shield_ccw"] = self._create_circle_template(clockwise=False)
        
        # Lightning: Zigzag patterns (Z, N, and bolt shapes)
        self.templates["lightning"] = self._create_template([
            (0.0, 0.0),    # Top left
            (1.0, 0.0),    # Top right
            (0.0, 1.0),    # Bottom left
            (1.0, 1.0),    # Bottom right
        ])
        
        self.templates["lightning_rev"] = self._create_template([
            (1.0, 0.0),    # Top right
            (0.0, 0.0),    # Top left
            (1.0, 1.0),    # Bottom right
            (0.0, 1.0),    # Bottom left
        ])
        
        # N-shape
        self.templates["lightning_n"] = self._create_template([
            (0.0, 1.0),    # Bottom left
            (0.0, 0.0),    # Top left
            (1.0, 1.0),    # Bottom right
            (1.0, 0.0),    # Top right
        ])
        
        # Vertical zigzag (like a lightning bolt)
        self.templates["lightning_bolt"] = self._create_template([
            (0.4, 0.0),    # Top
            (0.6, 0.35),   # Upper middle
            (0.3, 0.5),    # Middle
            (0.6, 0.85),   # Lower middle
            (0.4, 1.0),    # Bottom
        ])
    
    def _create_template(self, points: List[Tuple[float, float]]) -> List[Point]:
        """Create a template from normalized (0-1) coordinates."""
        # Scale to square_size
        scaled = [Point(p[0] * self.square_size, p[1] * self.square_size) for p in points]
        # Process through the normalization pipeline
        return self._normalize_points(scaled)
    
    def _create_circle_template(self, clockwise: bool = True) -> List[Point]:
        """Create a circle template."""
        points = []
        num_circle_points = 32
        for i in range(num_circle_points + 1):  # +1 to close the circle
            angle = (i / num_circle_points) * 2 * math.pi
            if not clockwise:
                angle = -angle
            x = 0.5 + 0.4 * math.cos(angle)
            y = 0.5 + 0.4 * math.sin(angle)
            points.append((x, y))
        return self._create_template(points)
    
    def _normalize_points(self, points: List[Point]) -> List[Point]:
        """Apply full normalization pipeline to points."""
        points = self._resample(points, self.num_points)
        radians = self._indicative_angle(points)
        points = self._rotate_by(points, -radians)
        points = self._scale_to(points, self.square_size)
        points = self._translate_to(points, self.origin)
        return points
    
    def recognize(self, points: List[Tuple[float, float]], min_score: float = 0.7) -> Optional[RecognitionResult]:
        """
        Recognize a gesture from a list of points.
        
        Args:
            points: List of (x, y) tuples in any coordinate system
            min_score: Minimum score threshold (0-1)
            
        Returns:
            RecognitionResult if recognized, None if no match
        """
        if len(points) < 10:
            print(f"[Gesture] Not enough points: {len(points)}")
            return None
        
        # Convert to Point objects
        point_list = [Point(p[0], p[1]) for p in points]
        
        # Normalize the input
        point_list = self._normalize_points(point_list)
        
        best_score = 0.0
        best_template = ""
        scores = {}  # Track all scores for debugging
        
        for name, template in self.templates.items():
            # Use golden section search for optimal angle
            distance = self._distance_at_best_angle(point_list, template)
            score = 1.0 - distance / self.half_diagonal
            scores[name] = score
            
            if score > best_score:
                best_score = score
                best_template = name
        
        # Debug output
        print(f"[Gesture] {len(points)} points, Best: {best_template} ({best_score:.2f})")
        top_scores = sorted(scores.items(), key=lambda x: -x[1])[:3]
        for name, score in top_scores:
            print(f"  - {name}: {score:.2f}")
        
        if best_score >= min_score:
            # Map alternative templates to main names (remove _cw, _ccw, _v1, _v2, _alt, _bolt, _rev, _n suffixes)
            final_name = best_template.split("_")[0]  # Just take the first part
            return RecognitionResult(name=final_name, score=best_score)
        
        return None
    
    def _resample(self, points: List[Point], n: int) -> List[Point]:
        """Resample points to have exactly n evenly-spaced points."""
        if len(points) < 2:
            return points + [points[-1]] * (n - len(points)) if len(points) > 0 else [Point(0, 0)] * n
            
        path_length = self._path_length(points)
        if path_length == 0:
            return [points[0]] * n
            
        interval = path_length / (n - 1)
        new_points = [points[0]]
        accumulated = 0.0
        j = 0  # Index into original points
        
        for _ in range(n - 1):
            target_dist = interval
            
            while j < len(points) - 1:
                segment_len = self._distance(points[j], points[j + 1])
                
                if accumulated + segment_len >= target_dist:
                    # Interpolate point on this segment
                    t = (target_dist - accumulated) / segment_len if segment_len > 0 else 0
                    t = max(0, min(1, t))  # Clamp t to [0, 1]
                    new_point = Point(
                        points[j].x + t * (points[j + 1].x - points[j].x),
                        points[j].y + t * (points[j + 1].y - points[j].y)
                    )
                    new_points.append(new_point)
                    # Update accumulated for next iteration (remaining distance on this segment)
                    accumulated = accumulated + segment_len - target_dist
                    break
                else:
                    accumulated += segment_len
                    j += 1
            else:
                # Ran out of points, add last point
                new_points.append(points[-1])
        
        # Ensure we have exactly n points
        while len(new_points) < n:
            new_points.append(points[-1])
            new_points.append(points[-1])
        
        return new_points[:n]
    
    def _indicative_angle(self, points: List[Point]) -> float:
        """Calculate the indicative angle (angle from centroid to first point)."""
        centroid = self._centroid(points)
        return math.atan2(centroid.y - points[0].y, centroid.x - points[0].x)
    
    def _rotate_by(self, points: List[Point], radians: float) -> List[Point]:
        """Rotate points around centroid by given angle."""
        centroid = self._centroid(points)
        cos_val = math.cos(radians)
        sin_val = math.sin(radians)
        
        new_points = []
        for p in points:
            dx = p.x - centroid.x
            dy = p.y - centroid.y
            new_points.append(Point(
                dx * cos_val - dy * sin_val + centroid.x,
                dx * sin_val + dy * cos_val + centroid.y
            ))
        return new_points
    
    def _scale_to(self, points: List[Point], size: float) -> List[Point]:
        """Scale points to fit in a square of given size."""
        bbox = self._bounding_box(points)
        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        
        # Avoid division by zero
        width = max(width, 0.01)
        height = max(height, 0.01)
        
        new_points = []
        for p in points:
            new_points.append(Point(
                p.x * (size / width),
                p.y * (size / height)
            ))
        return new_points
    
    def _translate_to(self, points: List[Point], target: Point) -> List[Point]:
        """Translate points so centroid is at target."""
        centroid = self._centroid(points)
        new_points = []
        for p in points:
            new_points.append(Point(
                p.x + target.x - centroid.x,
                p.y + target.y - centroid.y
            ))
        return new_points
    
    def _distance_at_best_angle(self, points: List[Point], template: List[Point]) -> float:
        """Find the best angle using golden section search."""
        phi = 0.5 * (-1.0 + math.sqrt(5.0))  # Golden ratio
        
        a = -self.angle_range
        b = self.angle_range
        
        x1 = phi * a + (1.0 - phi) * b
        f1 = self._distance_at_angle(points, template, x1)
        
        x2 = (1.0 - phi) * a + phi * b
        f2 = self._distance_at_angle(points, template, x2)
        
        while abs(b - a) > self.angle_precision:
            if f1 < f2:
                b = x2
                x2 = x1
                f2 = f1
                x1 = phi * a + (1.0 - phi) * b
                f1 = self._distance_at_angle(points, template, x1)
            else:
                a = x1
                x1 = x2
                f1 = f2
                x2 = (1.0 - phi) * a + phi * b
                f2 = self._distance_at_angle(points, template, x2)
        
        return min(f1, f2)
    
    def _distance_at_angle(self, points: List[Point], template: List[Point], radians: float) -> float:
        """Calculate path distance after rotating by given angle."""
        rotated = self._rotate_by(points, radians)
        return self._path_distance(rotated, template)
    
    def _path_distance(self, pts1: List[Point], pts2: List[Point]) -> float:
        """Calculate average distance between corresponding points."""
        if len(pts1) != len(pts2):
            return float('inf')
        
        total = 0.0
        for p1, p2 in zip(pts1, pts2):
            total += self._distance(p1, p2)
        return total / len(pts1)
    
    def _path_length(self, points: List[Point]) -> float:
        """Calculate total path length."""
        length = 0.0
        for i in range(1, len(points)):
            length += self._distance(points[i-1], points[i])
        return length
    
    def _centroid(self, points: List[Point]) -> Point:
        """Calculate centroid of points."""
        x_sum = sum(p.x for p in points)
        y_sum = sum(p.y for p in points)
        n = len(points)
        return Point(x_sum / n, y_sum / n)
    
    def _bounding_box(self, points: List[Point]) -> Tuple[float, float, float, float]:
        """Get bounding box as (min_x, min_y, max_x, max_y)."""
        min_x = min(p.x for p in points)
        min_y = min(p.y for p in points)
        max_x = max(p.x for p in points)
        max_y = max(p.y for p in points)
        return (min_x, min_y, max_x, max_y)
    
    def _distance(self, p1: Point, p2: Point) -> float:
        """Euclidean distance between two points."""
        return math.sqrt((p2.x - p1.x)**2 + (p2.y - p1.y)**2)


class GestureTracker:
    """
    Tracks drawing gestures and recognizes cipher shapes.
    Integrates with the vision system to capture finger movements.
    """
    
    def __init__(self):
        self.recognizer = DollarRecognizer()
        self.current_stroke: List[Tuple[float, float]] = []
        self.is_drawing = False
        self.min_points = 15
        self.point_distance_threshold = 0.01  # Minimum distance between points
        self.last_point: Optional[Tuple[float, float]] = None
        
        # Last recognition result (for sending to Godot)
        self.last_result: Optional[RecognitionResult] = None
    
    def start_drawing(self):
        """Begin a new gesture stroke."""
        self.current_stroke = []
        self.is_drawing = True
        self.last_point = None
        self.last_result = None
    
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
    
    def end_drawing(self) -> Optional[RecognitionResult]:
        """
        End the current stroke and attempt recognition.
        
        Returns:
            RecognitionResult if recognized, None otherwise
        """
        if not self.is_drawing:
            return None
        
        self.is_drawing = False
        
        if len(self.current_stroke) < self.min_points:
            self.last_result = None
            return None
        
        # Attempt recognition with lower threshold for testing
        result = self.recognizer.recognize(self.current_stroke, min_score=0.60)
        self.last_result = result
        
        return result
    
    def cancel_drawing(self):
        """Cancel the current drawing without recognition."""
        self.current_stroke = []
        self.is_drawing = False
        self.last_point = None
        self.last_result = None
    
    def get_stroke_for_display(self) -> List[Tuple[float, float]]:
        """Get the current stroke points for visualization."""
        return self.current_stroke.copy()
    
    def get_beautified_stroke(self) -> List[Tuple[float, float]]:
        """
        Get the beautified (template) version of the recognized shape.
        Returns empty list if no recognition.
        """
        if self.last_result is None:
            return []
        
        # Get the template and transform it to match the user's stroke bounds
        template_name = self.last_result.name
        
        # Find matching template (check main and alternates)
        template = None
        for name, tmpl in self.recognizer.templates.items():
            if name.startswith(template_name):
                template = tmpl
                break
        
        if template is None:
            return []
        
        # Get user stroke bounds
        if len(self.current_stroke) == 0:
            return []
        
        user_min_x = min(p[0] for p in self.current_stroke)
        user_max_x = max(p[0] for p in self.current_stroke)
        user_min_y = min(p[1] for p in self.current_stroke)
        user_max_y = max(p[1] for p in self.current_stroke)
        
        user_width = max(user_max_x - user_min_x, 0.05)
        user_height = max(user_max_y - user_min_y, 0.05)
        user_center_x = (user_min_x + user_max_x) / 2
        user_center_y = (user_min_y + user_max_y) / 2
        
        # Get template bounds
        tmpl_min_x = min(p.x for p in template)
        tmpl_max_x = max(p.x for p in template)
        tmpl_min_y = min(p.y for p in template)
        tmpl_max_y = max(p.y for p in template)
        
        tmpl_width = max(tmpl_max_x - tmpl_min_x, 0.01)
        tmpl_height = max(tmpl_max_y - tmpl_min_y, 0.01)
        tmpl_center_x = (tmpl_min_x + tmpl_max_x) / 2
        tmpl_center_y = (tmpl_min_y + tmpl_max_y) / 2
        
        # Scale to fit user's bounds (uniform scale to preserve aspect ratio)
        scale = min(user_width / tmpl_width, user_height / tmpl_height)
        
        # Transform template points
        beautified = []
        for p in template:
            x = (p.x - tmpl_center_x) * scale + user_center_x
            y = (p.y - tmpl_center_y) * scale + user_center_y
            beautified.append((x, y))
        
        return beautified
