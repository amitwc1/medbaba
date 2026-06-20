import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../domain/models/drawing_tool.dart';
import '../../utils/shape_recognizer.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart'; // Drift models

class DrawingCanvas extends StatefulWidget {
  final String pageId;
  final List<DrawingStroke> strokes;
  final DrawingToolType activeTool;
  final Color activeColor;
  final double activeThickness;
  final double activeOpacity;
  final String backgroundType; // blank, ruled, grid
  final String? pdfPath;
  final int pageNumber;
  final bool penOnlyMode;
  final Function(DrawingStroke) onStrokeCompleted;
  final Function(String) onStrokeErased;
  final Function(List<String>) onStrokesSelected;

  const DrawingCanvas({
    super.key,
    required this.pageId,
    required this.strokes,
    required this.activeTool,
    required this.activeColor,
    required this.activeThickness,
    required this.activeOpacity,
    required this.backgroundType,
    this.pdfPath,
    required this.pageNumber,
    required this.penOnlyMode,
    required this.onStrokeCompleted,
    required this.onStrokeErased,
    required this.onStrokesSelected,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  // Transformations (Zoom & Pan)
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  // Active stroke drawing points
  final List<DrawingPoint> _activePoints = [];

  // Pointer tracking for multi-touch
  final Map<int, Offset> _activePointers = {};
  double _initialPinchDistance = 0.0;
  double _initialScale = 1.0;
  Offset _initialPinchCenter = Offset.zero;
  Offset _initialOffset = Offset.zero;

  // Caching variables
  ui.Picture? _cachedPicture;
  Size? _cachedSize;
  ui.Image? _pdfImage;
  bool _isLoadingPdf = false;
  String? _loadedPdfPath;
  int? _loadedPageNumber;

  // Selection variables (Lasso)
  List<String> _selectedStrokeIds = [];
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _loadPdfBackground();
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath || oldWidget.pageNumber != widget.pageNumber) {
      _loadPdfBackground();
    } else if (oldWidget.strokes != widget.strokes || oldWidget.backgroundType != widget.backgroundType) {
      _invalidateCache();
    }
  }

  Future<void> _loadPdfBackground() async {
    if (widget.pdfPath == null) {
      if (_pdfImage != null) {
        setState(() {
          _pdfImage = null;
          _invalidateCache();
        });
      }
      return;
    }

    if (widget.pdfPath == _loadedPdfPath && widget.pageNumber == _loadedPageNumber) {
      return;
    }

    setState(() {
      _isLoadingPdf = true;
    });

    try {
      final document = await PdfDocument.openFile(widget.pdfPath!);
      final page = await document.getPage(widget.pageNumber);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await document.close();

      if (pageImage != null && mounted) {
        final codec = await ui.instantiateImageCodec(pageImage.bytes);
        final frame = await codec.getNextFrame();
        setState(() {
          _pdfImage = frame.image;
          _loadedPdfPath = widget.pdfPath;
          _loadedPageNumber = widget.pageNumber;
          _isLoadingPdf = false;
          _invalidateCache();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error rendering PDF background: $e');
      }
      setState(() {
        _isLoadingPdf = false;
      });
    }
  }

  void _invalidateCache() {
    _cachedPicture = null;
  }

  void _buildCache(Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw Page Background
    _drawPageBackground(canvas, size);

    // 2. Draw completed strokes
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in widget.strokes) {
      if (stroke.isDeleted) continue;

      // Check if selected to give it a glowing outline or blue hue
      final isSelected = _selectedStrokeIds.contains(stroke.id);
      final points = _deserializePoints(stroke.pointsJson, stroke.pressureJson, stroke.tiltJson);

      if (isSelected) {
        // Draw blue outline/halo for selection visual feedback
        final selectPaint = Paint()
          ..color = Colors.blue.withOpacity(0.3)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke.thickness + 6.0
          ..style = PaintingStyle.stroke;
        
        final selectPath = Path();
        if (points.isNotEmpty) {
          selectPath.moveTo(points.first.x, points.first.y);
          for (int i = 1; i < points.length; i++) {
            selectPath.lineTo(points[i].x, points[i].y);
          }
          canvas.drawPath(selectPath, selectPaint);
        }
      }

      _drawStroke(canvas, stroke, points, paint);
    }

    _cachedPicture = recorder.endRecording();
    _cachedSize = size;
  }

  void _drawPageBackground(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white;
    double bgWidth = size.width;
    double bgHeight = size.height;

    // Use a large canvas size if PDF is loaded to prevent clipping
    if (_pdfImage != null) {
      bgWidth = _pdfImage!.width.toDouble();
      bgHeight = _pdfImage!.height.toDouble();
    } else {
      bgWidth = math.max(2000.0, size.width);
      bgHeight = math.max(3000.0, size.height);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, bgWidth, bgHeight), bgPaint);

    if (_pdfImage != null) {
      canvas.drawImage(_pdfImage!, Offset.zero, Paint());
      return;
    }

    // Grid Background
    if (widget.backgroundType == 'grid') {
      final linePaint = Paint()
        ..color = Colors.grey.withOpacity(0.2)
        ..strokeWidth = 0.5;
      const double spacing = 30.0;
      for (double x = 0; x < bgWidth; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, bgHeight), linePaint);
      }
      for (double y = 0; y < bgHeight; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(bgWidth, y), linePaint);
      }
    }
    // Ruled Notebook Background
    else if (widget.backgroundType == 'ruled') {
      final linePaint = Paint()
        ..color = Colors.blue.withOpacity(0.15)
        ..strokeWidth = 0.8;
      final marginPaint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..strokeWidth = 1.2;

      const double spacing = 25.0;
      for (double y = 80.0; y < bgHeight; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(bgWidth, y), linePaint);
      }
      // Margin line
      canvas.drawLine(const Offset(70, 0), Offset(70, bgHeight), marginPaint);
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke, List<DrawingPoint> points, Paint paint) {
    if (points.isEmpty) return;

    paint.color = Color(int.parse(stroke.color.replaceAll('#', '0xff'))).withOpacity(stroke.opacity);

    if (stroke.toolType == 'highlighter') {
      paint.blendMode = BlendMode.multiply;
    } else {
      paint.blendMode = BlendMode.srcOver;
    }

    if (points.length == 1) {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(points.first.toOffset, stroke.thickness / 2, paint);
      return;
    }

    paint.style = PaintingStyle.stroke;

    if (stroke.toolType == 'pen' || stroke.toolType == 'pencil') {
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final avgPressure = (p1.pressure + p2.pressure) / 2;
        paint.strokeWidth = stroke.thickness * (0.35 + 0.65 * avgPressure);

        if (stroke.toolType == 'pencil') {
          // Pencil feels soft and textured
          paint.color = paint.color.withOpacity(stroke.opacity * 0.65);
        }

        canvas.drawLine(p1.toOffset, p2.toOffset, paint);
      }
    } else {
      paint.strokeWidth = stroke.thickness;
      final path = Path();
      path.moveTo(points.first.x, points.first.y);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].x, points[i].y);
      }
      canvas.drawPath(path, paint);
    }
  }

  List<DrawingPoint> _deserializePoints(String pointsJson, String? pressureJson, String? tiltJson) {
    final List<dynamic> pts = jsonDecode(pointsJson);
    final List<dynamic> press = pressureJson != null ? jsonDecode(pressureJson) : [];
    final List<dynamic> tilts = tiltJson != null ? jsonDecode(tiltJson) : [];

    final List<DrawingPoint> points = [];
    for (int i = 0; i < pts.length; i += 2) {
      if (i + 1 >= pts.length) break;
      final double x = (pts[i] as num).toDouble();
      final double y = (pts[i + 1] as num).toDouble();
      final int ptIdx = i ~/ 2;
      final double p = ptIdx < press.length ? (press[ptIdx] as num).toDouble() : 1.0;
      final double t = ptIdx < tilts.length ? (tilts[ptIdx] as num).toDouble() : 0.0;
      points.add(DrawingPoint(x: x, y: y, pressure: p, tilt: t));
    }
    return points;
  }

  // ─────────────────────────── TOUCH AND STYLUS EVENT HANDLERS ───────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;

    // Check if it is a stylus or if finger drawing is allowed
    final isStylus = event.kind == ui.PointerDeviceKind.stylus || event.kind == ui.PointerDeviceKind.invertedStylus;
    final canDraw = isStylus || !widget.penOnlyMode;

    if (_activePointers.length == 1 && canDraw && widget.activeTool != DrawingToolType.lasso) {
      // Start Drawing
      _isSelecting = false;
      final localPoint = event.localPosition;
      final canvasPoint = (localPoint - _offset) / _scale;

      setState(() {
        _activePoints.clear();
        _activePoints.add(DrawingPoint(
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          pressure: isStylus ? event.pressure : 1.0,
          tilt: isStylus ? event.tilt : 0.0,
        ));
      });
    } else if (widget.activeTool == DrawingToolType.lasso && _activePointers.length == 1) {
      // Start Lasso selection
      _isSelecting = true;
      _selectedStrokeIds.clear();
      final localPoint = event.localPosition;
      final canvasPoint = (localPoint - _offset) / _scale;
      setState(() {
        _activePoints.clear();
        _activePoints.add(DrawingPoint(x: canvasPoint.dx, y: canvasPoint.dy));
      });
    } else if (_activePointers.length == 2) {
      // Two-finger Pinch to Zoom & Pan
      _activePoints.clear(); // Discard active drawing to prevent stray marks
      final keys = _activePointers.keys.toList();
      final p1 = _activePointers[keys[0]]!;
      final p2 = _activePointers[keys[1]]!;

      _initialPinchDistance = (p1 - p2).distance;
      _initialScale = _scale;
      _initialPinchCenter = (p1 + p2) / 2;
      _initialOffset = _offset;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.position;

    final isStylus = event.kind == ui.PointerDeviceKind.stylus || event.kind == ui.PointerDeviceKind.invertedStylus;
    final canDraw = isStylus || !widget.penOnlyMode;

    if (_activePointers.length == 1 && canDraw && _activePoints.isNotEmpty && widget.activeTool != DrawingToolType.lasso) {
      final localPoint = event.localPosition;
      final canvasPoint = (localPoint - _offset) / _scale;

      setState(() {
        _activePoints.add(DrawingPoint(
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          pressure: isStylus ? event.pressure : 1.0,
          tilt: isStylus ? event.tilt : 0.0,
        ));
      });

      // Eraser check
      if (widget.activeTool == DrawingToolType.eraser) {
        _performErase(canvasPoint);
      }
    } else if (widget.activeTool == DrawingToolType.lasso && _isSelecting && _activePoints.isNotEmpty) {
      final localPoint = event.localPosition;
      final canvasPoint = (localPoint - _offset) / _scale;
      setState(() {
        _activePoints.add(DrawingPoint(x: canvasPoint.dx, y: canvasPoint.dy));
      });
    } else if (_activePointers.length == 2) {
      // Two-finger Pinch / Pan update
      final keys = _activePointers.keys.toList();
      final p1 = _activePointers[keys[0]]!;
      final p2 = _activePointers[keys[1]]!;

      final currentDistance = (p1 - p2).distance;
      final currentCenter = (p1 + p2) / 2;

      setState(() {
        if (_initialPinchDistance > 0) {
          _scale = (_initialScale * (currentDistance / _initialPinchDistance)).clamp(0.15, 10.0);
        }
        // Pan tracking relative to focal center
        _offset = currentCenter - (_initialPinchCenter - _initialOffset) * (_scale / _initialScale);
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty) {
      if (widget.activeTool == DrawingToolType.lasso && _isSelecting) {
        _isSelecting = false;
        _performLassoSelect();
        setState(() {
          _activePoints.clear();
          _invalidateCache();
        });
      } else if (_activePoints.isNotEmpty && widget.activeTool != DrawingToolType.eraser) {
        // Complete Drawing Stroke
        List<DrawingPoint> strokePoints = List.from(_activePoints);

        // Rectify shapes if Shape Recognizer tool is active
        if (widget.activeTool == DrawingToolType.shape) {
          strokePoints = ShapeRecognizer.recognizeAndRectify(strokePoints);
        }

        final hexColor = '#${widget.activeColor.value.toRadixString(16).substring(2)}';

        // Create the stroke payload
        final String ptsJson = jsonEncode(strokePoints.expand((p) => [p.x, p.y]).toList());
        final String pressJson = jsonEncode(strokePoints.map((p) => p.pressure).toList());
        final String tiltsJson = jsonEncode(strokePoints.map((p) => p.tilt).toList());

        final stroke = DrawingStroke(
          id: const Uuid().v4(),
          pageId: widget.pageId,
          pointsJson: ptsJson,
          pressureJson: pressJson,
          tiltJson: tiltsJson,
          color: hexColor,
          thickness: widget.activeThickness,
          opacity: widget.activeOpacity,
          toolType: widget.activeTool.name,
          isDeleted: false,
          syncStatus: 'pending',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        widget.onStrokeCompleted(stroke);

        setState(() {
          _activePoints.clear();
          _invalidateCache();
        });
      } else {
        setState(() {
          _activePoints.clear();
        });
      }
    }
  }

  void _performErase(Offset canvasPoint) {
    // Check which strokes are intersected by the eraser point
    final eraserRadius = widget.activeThickness;
    for (final stroke in widget.strokes) {
      if (stroke.isDeleted) continue;

      final points = _deserializePoints(stroke.pointsJson, stroke.pressureJson, stroke.tiltJson);
      for (final p in points) {
        final dist = (p.toOffset - canvasPoint).distance;
        if (dist <= eraserRadius) {
          // Erase this stroke!
          widget.onStrokeErased(stroke.id);
          _invalidateCache();
          break; // Stop checking points for this stroke
        }
      }
    }
  }

  void _performLassoSelect() {
    if (_activePoints.length < 3) return;

    final polygon = _activePoints.map((p) => p.toOffset).toList();
    final List<String> selectedIds = [];

    for (final stroke in widget.strokes) {
      if (stroke.isDeleted) continue;

      final points = _deserializePoints(stroke.pointsJson, stroke.pressureJson, stroke.tiltJson);
      if (points.isEmpty) continue;

      // Calculate centroid of the stroke
      double sumX = 0;
      double sumY = 0;
      for (final p in points) {
        sumX += p.x;
        sumY += p.y;
      }
      final centroid = Offset(sumX / points.length, sumY / points.length);

      if (_isPointInPolygon(centroid, polygon)) {
        selectedIds.add(stroke.id);
      }
    }

    setState(() {
      _selectedStrokeIds = selectedIds;
    });
    widget.onStrokesSelected(selectedIds);
  }

  bool _isPointInPolygon(Offset p, List<Offset> polygon) {
    bool isInside = false;
    final double px = p.dx;
    final double py = p.dy;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final double ix = polygon[i].dx;
      final double iy = polygon[i].dy;
      final double jx = polygon[j].dx;
      final double jy = polygon[j].dy;

      if (((iy > py) != (jy > py)) && (px < (jx - ix) * (py - iy) / (jy - iy) + ix)) {
        isInside = !isInside;
      }
    }
    return isInside;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (_cachedPicture == null || _cachedSize != canvasSize) {
          _buildCache(canvasSize);
        }

        return Stack(
          children: [
            Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: CustomPaint(
                size: Size.infinite,
                painter: DrawingCanvasPainter(
                  cachedPicture: _cachedPicture,
                  activePoints: List.from(_activePoints),
                  activeTool: widget.activeTool,
                  activeColor: widget.activeColor,
                  activeThickness: widget.activeThickness,
                  activeOpacity: widget.activeOpacity,
                  offset: _offset,
                  scale: _scale,
                ),
              ),
            ),
            if (_isLoadingPdf)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class DrawingCanvasPainter extends CustomPainter {
  final ui.Picture? cachedPicture;
  final List<DrawingPoint> activePoints;
  final DrawingToolType activeTool;
  final Color activeColor;
  final double activeThickness;
  final double activeOpacity;
  final Offset offset;
  final double scale;

  DrawingCanvasPainter({
    required this.cachedPicture,
    required this.activePoints,
    required this.activeTool,
    required this.activeColor,
    required this.activeThickness,
    required this.activeOpacity,
    required this.offset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // 1. Draw cached layer
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture!);
    }

    // 2. Draw active points
    if (activePoints.isNotEmpty) {
      final paint = Paint()
        ..color = activeColor.withOpacity(activeOpacity)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (activeTool == DrawingToolType.eraser) {
        final lastPoint = activePoints.last;
        final previewPaint = Paint()
          ..color = Colors.red.withOpacity(0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(lastPoint.toOffset, activeThickness / 2, previewPaint);
      } else if (activeTool == DrawingToolType.lasso) {
        paint.color = Colors.blue.withOpacity(0.6);
        paint.strokeWidth = 1.5;
        // Dotted lasso line effect
        final path = Path();
        path.moveTo(activePoints.first.x, activePoints.first.y);
        for (int i = 1; i < activePoints.length; i++) {
          path.lineTo(activePoints[i].x, activePoints[i].y);
        }
        canvas.drawPath(path, paint);
      } else {
        paint.strokeWidth = activeThickness;
        final path = Path();
        path.moveTo(activePoints.first.x, activePoints.first.y);
        for (int i = 1; i < activePoints.length; i++) {
          path.lineTo(activePoints[i].x, activePoints[i].y);
        }
        canvas.drawPath(path, paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return oldDelegate.cachedPicture != cachedPicture ||
        oldDelegate.activePoints.length != activePoints.length ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.activeTool != activeTool ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeThickness != activeThickness ||
        oldDelegate.activeOpacity != activeOpacity;
  }
}
