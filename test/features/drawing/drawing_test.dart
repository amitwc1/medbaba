import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_vault/features/drawing/domain/models/drawing_tool.dart';
import 'package:mind_vault/features/drawing/utils/shape_recognizer.dart';
import 'package:mind_vault/core/services/sync_service.dart';

void main() {
  group('ShapeRecognizer Tests', () {
    test('Line Recognition - Straight Stroke', () {
      // Generate points on a straight line from (0,0) to (100,100)
      final List<DrawingPoint> points = [];
      for (int i = 0; i <= 10; i++) {
        points.add(DrawingPoint(x: i * 10.0, y: i * 10.0));
      }

      final rectified = ShapeRecognizer.recognizeAndRectify(points);

      // Line should rectify to exactly 2 points: start and end
      expect(rectified.length, equals(2));
      expect(rectified.first.x, equals(0.0));
      expect(rectified.first.y, equals(0.0));
      expect(rectified.last.x, equals(100.0));
      expect(rectified.last.y, equals(100.0));
    });

    test('Circle Recognition - Radial Stroke', () {
      // Generate points around a circle of radius 50 centered at (100,100)
      final List<DrawingPoint> points = [];
      const int steps = 20;
      for (int i = 0; i < steps; i++) {
        final double theta = (i * 2 * math.pi) / steps;
        // Introduce small noise to test recognizer tolerance
        final double noise = (i % 2 == 0) ? 0.5 : -0.5;
        points.add(DrawingPoint(
          x: 100.0 + (50.0 + noise) * math.cos(theta),
          y: 100.0 + (50.0 + noise) * math.sin(theta),
        ));
      }
      // Add closing point
      points.add(points.first);

      final rectified = ShapeRecognizer.recognizeAndRectify(points);

      // Ellipse points generator produces 41 points
      expect(rectified.length, equals(41));
    });

    test('Rectangle Recognition - Orthogonal Box Stroke', () {
      // Draw a box: (10,10) -> (100,10) -> (100,100) -> (10,100) -> (10,10)
      final List<DrawingPoint> points = [
        const DrawingPoint(x: 10, y: 10),
        const DrawingPoint(x: 50, y: 11), // small noise
        const DrawingPoint(x: 100, y: 10),
        const DrawingPoint(x: 100, y: 50),
        const DrawingPoint(x: 101, y: 100),
        const DrawingPoint(x: 50, y: 100),
        const DrawingPoint(x: 10, y: 99),
        const DrawingPoint(x: 10, y: 50),
        const DrawingPoint(x: 10, y: 10),
      ];

      final rectified = ShapeRecognizer.recognizeAndRectify(points);

      // Rectangle should rectify to 5 perfect bounding box corner points
      expect(rectified.length, equals(5));
      expect(rectified[0].x, equals(10.0));
      expect(rectified[0].y, equals(10.0));
      expect(rectified[1].x, equals(101.0));
      expect(rectified[1].y, equals(10.0));
      expect(rectified[2].x, equals(101.0));
      expect(rectified[2].y, equals(100.0));
      expect(rectified[3].x, equals(10.0));
      expect(rectified[3].y, equals(100.0));
      expect(rectified[4].x, equals(10.0));
      expect(rectified[4].y, equals(10.0));
    });
  });

  group('SyncService Coordinate Compression Tests', () {
    test('Gzip Compression & Decompression Roundtrip', () {
      final List<double> coordinateDataset = [];
      for (int i = 0; i < 500; i++) {
        coordinateDataset.add(i * 1.5);
        coordinateDataset.add(i * 2.25);
      }
      final rawJson = jsonEncode(coordinateDataset);

      // Compress
      final compressed = SyncService.compressString(rawJson);
      expect(compressed.startsWith('gz:'), isTrue);
      expect(compressed.length, lessThan(rawJson.length)); // Ensure it is indeed smaller!

      // Decompress
      final decompressed = SyncService.decompressString(compressed);
      expect(decompressed, equals(rawJson));

      // Test parsing back
      final List<dynamic> parsed = jsonDecode(decompressed);
      expect(parsed.length, equals(1000));
      expect(parsed[0], equals(0.0));
      expect(parsed.last, equals(499 * 2.25));
    });

    test('Passes raw JSON through if not compressed', () {
      const rawJson = '[1.0, 2.0, 3.0]';
      final decompressed = SyncService.decompressString(rawJson);
      expect(decompressed, equals(rawJson));
    });
  });
}
