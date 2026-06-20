import 'dart:math' as math;
import '../domain/models/drawing_tool.dart';

class ShapeRecognizer {
  /// Recognizes a shape from a list of points and returns the rectified points representing that shape.
  /// If the shape is not recognized, it returns the original points (freeform).
  static List<DrawingPoint> recognizeAndRectify(List<DrawingPoint> points) {
    if (points.length < 5) return points;

    // Calculate bounding box
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final double width = maxX - minX;
    final double height = maxY - minY;
    final double diagonal = math.sqrt(width * width + height * height);

    if (diagonal < 10) return points; // Too small

    // Calculate closed-ness
    final double startEndDist = (points.first.toOffset - points.last.toOffset).distance;
    final bool isClosed = startEndDist < diagonal * 0.25;

    // Simplify path using Ramer-Douglas-Peucker
    final List<DrawingPoint> simplified = _simplifyPath(points, diagonal * 0.045);

    if (isClosed) {
      // 1. Circle / Ellipse check:
      // Normalize points and check variance of radius
      final double cx = (minX + maxX) / 2;
      final double cy = (minY + maxY) / 2;
      final double rx = width / 2;
      final double ry = height / 2;

      if (rx > 0 && ry > 0) {
        double totalDev = 0;
        for (final p in points) {
          final double dx = (p.x - cx) / rx;
          final double dy = (p.y - cy) / ry;
          final double dist = math.sqrt(dx * dx + dy * dy);
          totalDev += (dist - 1.0).abs();
        }
        final double avgDev = totalDev / points.length;

        // If average deviation from perfect ellipse unit distance (1.0) is very low, it's a circle/ellipse
        if (avgDev < 0.15) {
          return _generateEllipsePoints(cx, cy, rx, ry, points.first.pressure);
        }
      }

      // 2. Triangle check (closed path with 3 main vertices + closing)
      if (simplified.length == 4) {
        // Clean up simplified to exactly 3 vertices + closing
        final List<DrawingPoint> trianglePoints = [];
        final List<DrawingPoint> vertices = simplified.sublist(0, 3);
        trianglePoints.addAll(vertices);
        trianglePoints.add(vertices.first); // Close it
        return trianglePoints;
      }

      // 3. Rectangle check (closed path with 4 main vertices + closing)
      if (simplified.length == 5 || simplified.length == 6) {
        // Return perfect axis-aligned rectangle
        final double pressure = points.first.pressure;
        return [
          DrawingPoint(x: minX, y: minY, pressure: pressure),
          DrawingPoint(x: maxX, y: minY, pressure: pressure),
          DrawingPoint(x: maxX, y: maxY, pressure: pressure),
          DrawingPoint(x: minX, y: maxY, pressure: pressure),
          DrawingPoint(x: minX, y: minY, pressure: pressure),
        ];
      }
    } else {
      // Open path
      // 4. Arrow Check:
      // An arrow usually has a long line segment (shaft) and short segments at the end (head).
      // We look at the simplified path. If the last 2-3 segments form a sharp V shape returning to the end point
      // or if it looks like an arrow.
      // Let's implement an arrow detector.
      final bool isArrow = _detectArrow(points, simplified, diagonal);
      if (isArrow) {
        return _rectifyArrow(points, minX, maxX, minY, maxY);
      }

      // 5. Line check:
      // If the simplified path has basically 2 points (or the deviation of all points from a straight line is very low)
      double maxLineDev = 0;
      final DrawingPoint start = points.first;
      final DrawingPoint end = points.last;
      for (final p in points) {
        final double dev = _perpendicularDistance(p, start, end);
        if (dev > maxLineDev) maxLineDev = dev;
      }

      if (maxLineDev < diagonal * 0.08) {
        return [start, end];
      }
    }

    return points; // Freeform fallback
  }

  static List<DrawingPoint> _simplifyPath(List<DrawingPoint> points, double epsilon) {
    if (points.length < 3) return points;

    int index = -1;
    double maxDist = 0.0;

    for (int i = 1; i < points.length - 1; i++) {
      double dist = _perpendicularDistance(points[i], points[0], points.last);
      if (dist > maxDist) {
        index = i;
        maxDist = dist;
      }
    }

    if (maxDist > epsilon) {
      final List<DrawingPoint> results1 = _simplifyPath(points.sublist(0, index + 1), epsilon);
      final List<DrawingPoint> results2 = _simplifyPath(points.sublist(index), epsilon);
      return [...results1.sublist(0, results1.length - 1), ...results2];
    } else {
      return [points.first, points.last];
    }
  }

  static double _perpendicularDistance(DrawingPoint p, DrawingPoint lineStart, DrawingPoint lineEnd) {
    final double dx = lineEnd.x - lineStart.x;
    final double dy = lineEnd.y - lineStart.y;
    final double denom = dx * dx + dy * dy;
    if (denom == 0.0) {
      return (p.toOffset - lineStart.toOffset).distance;
    }
    double t = ((p.x - lineStart.x) * dx + (p.y - lineStart.y) * dy) / denom;
    t = t.clamp(0.0, 1.0);
    final double nearestX = lineStart.x + t * dx;
    final double nearestY = lineStart.y + t * dy;
    return math.sqrt((p.x - nearestX) * (p.x - nearestX) + (p.y - nearestY) * (p.y - nearestY));
  }

  static List<DrawingPoint> _generateEllipsePoints(double cx, double cy, double rx, double ry, double pressure) {
    final List<DrawingPoint> ellipsePoints = [];
    const int count = 40;
    for (int i = 0; i <= count; i++) {
      final double theta = (i * 2 * math.pi) / count;
      ellipsePoints.add(DrawingPoint(
        x: cx + rx * math.cos(theta),
        y: cy + ry * math.sin(theta),
        pressure: pressure,
      ));
    }
    return ellipsePoints;
  }

  static bool _detectArrow(List<DrawingPoint> points, List<DrawingPoint> simplified, double diagonal) {
    if (simplified.length < 3) return false;
    
    // Check if the path contains a sharp fold back at the end
    // E.g. the path goes to a point, then backtracks at an angle
    // Let's compute the total path length vs the direct distance
    double pathLength = 0;
    for (int i = 0; i < points.length - 1; i++) {
      pathLength += (points[i].toOffset - points[i + 1].toOffset).distance;
    }
    
    final double directDist = (points.first.toOffset - points.last.toOffset).distance;
    
    // If the path length is significantly longer than the direct distance, and the simplified path has a head-like structure at the end
    if (pathLength > directDist * 1.25) {
      // Let's check the angles between the last few segments of the simplified path
      // If there is a sharp angle (e.g. < 60 degrees) near the end, it might be an arrow tip
      for (int i = simplified.length - 2; i > 0; i--) {
        final DrawingPoint p1 = simplified[i - 1];
        final DrawingPoint p2 = simplified[i];
        final DrawingPoint p3 = simplified[i + 1];
        
        final double v1x = p1.x - p2.x;
        final double v1y = p1.y - p2.y;
        final double v2x = p3.x - p2.x;
        final double v2y = p3.y - p2.y;
        
        final double len1 = math.sqrt(v1x * v1x + v1y * v1y);
        final double len2 = math.sqrt(v2x * v2x + v2y * v2y);
        
        if (len1 > 0 && len2 > 0) {
          final double dot = (v1x * v2x + v1y * v2y) / (len1 * len2);
          final double angle = math.acos(dot.clamp(-1.0, 1.0));
          // If angle is sharp (< 60 degrees) and one of the segments is short (head wing)
          if (angle < math.pi / 3 && (len2 < diagonal * 0.3 || len1 < diagonal * 0.3)) {
            return true;
          }
        }
      }
    }
    
    return false;
  }

  static List<DrawingPoint> _rectifyArrow(List<DrawingPoint> points, double minX, double maxX, double minY, double maxY) {
    // The arrow shaft goes from the first point to the last point (or near the last point)
    final DrawingPoint start = points.first;
    final DrawingPoint end = points.last;
    
    final double dx = end.x - start.x;
    final double dy = end.y - start.y;
    final double length = math.sqrt(dx * dx + dy * dy);
    
    if (length == 0) return points;
    
    // Normalize direction vector of the shaft
    final double ux = dx / length;
    final double uy = dy / length;
    
    // Bounding box size helps determine the size of the arrowhead
    final double arrowHeadLength = math.max(15.0, length * 0.15);
    const double arrowAngle = math.pi / 6; // 30 degrees
    
    // Left wing of arrowhead
    final double cosA = math.cos(arrowAngle);
    final double sinA = math.sin(arrowAngle);
    
    // Rotate vector (-ux, -uy) by arrowAngle and -arrowAngle
    final double w1x = -ux * cosA - -uy * sinA;
    final double w1y = -uy * cosA + -ux * sinA;
    
    final double w2x = -ux * cosA - -uy * -sinA;
    final double w2y = -uy * cosA + -ux * -sinA;
    
    final double p1x = end.x + w1x * arrowHeadLength;
    final double p1y = end.y + w1y * arrowHeadLength;
    
    final double p2x = end.x + w2x * arrowHeadLength;
    final double p2y = end.y + w2y * arrowHeadLength;
    
    final double pressure = points.first.pressure;
    
    // Construct single stroke vector for arrow: shaft -> end -> left wing -> end -> right wing
    return [
      start,
      end,
      DrawingPoint(x: p1x, y: p1y, pressure: pressure),
      end,
      DrawingPoint(x: p2x, y: p2y, pressure: pressure),
    ];
  }
}
