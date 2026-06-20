import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdfx/pdfx.dart' as pdfx_render;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/drawing_tool.dart';
import '../providers/drawing_providers.dart';
import '../widgets/drawing_canvas.dart';
import '../../../../core/database/app_database.dart';

class DrawingEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;

  const DrawingEditorScreen({
    super.key,
    this.noteId,
  });

  @override
  ConsumerState<DrawingEditorScreen> createState() => _DrawingEditorScreenState();
}

class _DrawingEditorScreenState extends ConsumerState<DrawingEditorScreen> {
  // Brush Configurations
  DrawingToolType _activeTool = DrawingToolType.pen;
  Color _activeColor = Colors.black;
  double _activeThickness = 4.0;
  double _activeOpacity = 1.0;
  bool _penOnlyMode = false;
  List<String> _selectedStrokeIds = [];

  // Toolbar state
  final TextEditingController _titleController = TextEditingController();
  bool _isEditingTitle = false;

  final List<Color> _presetColors = [
    Colors.black,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.grey,
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  double _getOpacityForTool(DrawingToolType tool) {
    if (tool == DrawingToolType.highlighter) return 0.35;
    return 1.0;
  }

  double _getDefaultThickness(DrawingToolType tool) {
    switch (tool) {
      case DrawingToolType.pen:
        return 4.0;
      case DrawingToolType.pencil:
        return 3.0;
      case DrawingToolType.highlighter:
        return 18.0;
      case DrawingToolType.eraser:
        return 30.0;
      default:
        return 4.0;
    }
  }

  // ─────────────────────────── EXPORT OPERATIONS ───────────────────────────

  Future<Uint8List> _generatePagePng(DrawingPage page, List<DrawingStroke> strokes) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Get background dimensions
    double width = 800.0;
    double height = 1100.0;

    ui.Image? pdfBgImage;
    if (page.pdfPath != null) {
      try {
        final doc = await pdfx_render.PdfDocument.openFile(page.pdfPath!);
        final pdfPage = await doc.getPage(page.pageNumber);
        final pageImage = await pdfPage.render(
          width: pdfPage.width * 2,
          height: pdfPage.height * 2,
          format: pdfx_render.PdfPageImageFormat.png,
        );
        await pdfPage.close();
        await doc.close();

        if (pageImage != null) {
          final codec = await ui.instantiateImageCodec(pageImage.bytes);
          final frame = await codec.getNextFrame();
          pdfBgImage = frame.image;
          width = pdfBgImage.width.toDouble();
          height = pdfBgImage.height.toDouble();
        }
      } catch (e) {
        if (kDebugMode) print('Error rendering page background image: $e');
      }
    }

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    if (pdfBgImage != null) {
      canvas.drawImage(pdfBgImage, Offset.zero, Paint());
    } else {
      // Draw grid or ruled background
      if (page.backgroundType == 'grid') {
        final linePaint = Paint()
          ..color = Colors.grey.withOpacity(0.2)
          ..strokeWidth = 0.5;
        const double spacing = 30.0;
        for (double x = 0; x < width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, height), linePaint);
        }
        for (double y = 0; y < height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(width, y), linePaint);
        }
      } else if (page.backgroundType == 'ruled') {
        final linePaint = Paint()
          ..color = Colors.blue.withOpacity(0.15)
          ..strokeWidth = 0.8;
        final marginPaint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..strokeWidth = 1.2;

        const double spacing = 25.0;
        for (double y = 80.0; y < height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(width, y), linePaint);
        }
        canvas.drawLine(const Offset(70, 0), Offset(70, height), marginPaint);
      }
    }

    // Draw strokes
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isDeleted) continue;

      paint.color = Color(int.parse(stroke.color.replaceAll('#', '0xff'))).withOpacity(stroke.opacity);
      if (stroke.toolType == 'highlighter') {
        paint.blendMode = BlendMode.multiply;
      } else {
        paint.blendMode = BlendMode.srcOver;
      }

      final List<dynamic> pts = jsonDecode(stroke.pointsJson);
      final List<dynamic> press = stroke.pressureJson != null ? jsonDecode(stroke.pressureJson!) : [];
      final List<DrawingPoint> points = [];

      for (int i = 0; i < pts.length; i += 2) {
        if (i + 1 >= pts.length) break;
        final double x = (pts[i] as num).toDouble();
        final double y = (pts[i + 1] as num).toDouble();
        final int ptIdx = i ~/ 2;
        final double p = ptIdx < press.length ? (press[ptIdx] as num).toDouble() : 1.0;
        points.add(DrawingPoint(x: x, y: y, pressure: p));
      }

      if (points.isEmpty) continue;

      if (points.length == 1) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(points.first.toOffset, stroke.thickness / 2, paint);
        continue;
      }

      paint.style = PaintingStyle.stroke;

      if (stroke.toolType == 'pen' || stroke.toolType == 'pencil') {
        for (int i = 0; i < points.length - 1; i++) {
          final p1 = points[i];
          final p2 = points[i + 1];
          final avgPressure = (p1.pressure + p2.pressure) / 2;
          paint.strokeWidth = stroke.thickness * (0.35 + 0.65 * avgPressure);

          if (stroke.toolType == 'pencil') {
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

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }

  Future<void> _exportAsImage(DrawingPage page, List<DrawingStroke> strokes) async {
    setState(() {}); // Ensure latest state
    try {
      final pngBytes = await _generatePagePng(page, strokes);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/drawing_page_${page.pageNumber}.png');
      await tempFile.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(tempFile.path)], text: 'My Handwritten Page');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportAsPdf(List<DrawingPage> pages, DrawingEditorNotifier notifier) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF, please wait...'), duration: Duration(seconds: 2)),
    );

    try {
      final pdf = pw.Document();

      for (final page in pages) {
        final strokes = await AppDatabase.instance.getStrokesForPage(page.id);
        final pngBytes = await _generatePagePng(page, strokes);
        final pdfImage = pw.MemoryImage(pngBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
              );
            },
          ),
        );
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/handwritten_document.pdf');
      await tempFile.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(tempFile.path)], text: 'My Handwritten PDF Document');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF generation failed: $e')));
    }
  }

  // ─────────────────────────── PDF IMPORT OVERLAYS ───────────────────────────

  Future<void> _importPdf(DrawingEditorNotifier notifier) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final originalPath = result.files.single.path!;
        final appDocsDir = await getApplicationDocumentsDirectory();
        final targetDir = '${appDocsDir.path}/imported_pdfs';
        await Directory(targetDir).create(recursive: true);
        final fileName = result.files.single.name;
        final persistentPath = '$targetDir/${DateTime.now().millisecondsSinceEpoch}_$fileName';

        await File(originalPath).copy(persistentPath);

        // Render document page count
        final doc = await pdfx_render.PdfDocument.openFile(persistentPath);
        final pageCount = doc.pagesCount;
        await doc.close();

        for (int i = 1; i <= pageCount; i++) {
          await notifier.addPage(
            backgroundType: 'blank',
            pdfPath: persistentPath,
            pdfPageNumber: i,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully imported $pageCount PDF pages!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Import failed: $e')));
    }
  }

  // ─────────────────────────── RESPONSIVE LAYOUTS ───────────────────────────

  Widget _buildTopToolbar(
      BuildContext context, DrawingEditorState state, DrawingEditorNotifier notifier) {
    if (state.activeNote == null) return const SizedBox.shrink();

    if (!_isEditingTitle) {
      _titleController.text = state.activeNote!.title;
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _isEditingTitle
                ? Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) {
                        notifier.updateTitle(_titleController.text);
                        setState(() {
                          _isEditingTitle = false;
                        });
                      }
                    },
                    child: TextField(
                      controller: _titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      onSubmitted: (val) {
                        notifier.updateTitle(val);
                        setState(() {
                          _isEditingTitle = false;
                        });
                      },
                    ),
                  )
                : GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEditingTitle = true;
                      });
                    },
                    child: Row(
                      children: [
                        Text(
                          state.activeNote!.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
          ),
          // Undo & Redo
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: notifier.canUndo ? () => notifier.undo() : null,
            color: notifier.canUndo ? Colors.blue : Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: notifier.canRedo ? () => notifier.redo() : null,
            color: notifier.canRedo ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 8),
          // Pen Mode Toggle
          Tooltip(
            message: _penOnlyMode ? 'Pen Only Mode Active' : 'Touch + Stylus Mode',
            child: IconButton(
              icon: Icon(
                _penOnlyMode ? Icons.border_color : Icons.touch_app,
                color: _penOnlyMode ? Colors.blue : Colors.grey[700],
              ),
              onPressed: () {
                setState(() {
                  _penOnlyMode = !_penOnlyMode;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'pdf_import') {
                await _importPdf(notifier);
              } else if (value == 'export_image') {
                if (state.pages.isNotEmpty) {
                  await _exportAsImage(state.pages[state.currentPageIndex], state.currentStrokes);
                }
              } else if (value == 'export_pdf') {
                await _exportAsPdf(state.pages, notifier);
              } else if (value == 'bg_blank') {
                await notifier.updateBackgroundType('blank');
              } else if (value == 'bg_ruled') {
                await notifier.updateBackgroundType('ruled');
              } else if (value == 'bg_grid') {
                await notifier.updateBackgroundType('grid');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pdf_import',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Import PDF pages'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export_image',
                child: Row(
                  children: [
                    Icon(Icons.image, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Export current page (PNG)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_pdf',
                child: Row(
                  children: [
                    Icon(Icons.print, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Export full document (PDF)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'bg_blank',
                child: Text('Background: Blank'),
              ),
              const PopupMenuItem(
                value: 'bg_ruled',
                child: Text('Background: Ruled'),
              ),
              const PopupMenuItem(
                value: 'bg_grid',
                child: Text('Background: Grid'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrushOptions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tool Selection
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DrawingToolType.values.map((tool) {
                final isSelected = _activeTool == tool;
                IconData icon;
                String label;
                switch (tool) {
                  case DrawingToolType.pen:
                    icon = Icons.gesture;
                    label = 'Pen';
                    break;
                  case DrawingToolType.pencil:
                    icon = Icons.edit_outlined;
                    label = 'Pencil';
                    break;
                  case DrawingToolType.highlighter:
                    icon = Icons.highlight;
                    label = 'Marker';
                    break;
                  case DrawingToolType.eraser:
                    icon = Icons.auto_fix_normal;
                    label = 'Eraser';
                    break;
                  case DrawingToolType.lasso:
                    icon = Icons.ads_click;
                    label = 'Lasso';
                    break;
                  case DrawingToolType.shape:
                    icon = Icons.star_border;
                    label = 'Shape';
                    break;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
                        const SizedBox(width: 4),
                        Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87)),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: Colors.blue[600],
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _activeTool = tool;
                          _activeThickness = _getDefaultThickness(tool);
                          _activeOpacity = _getOpacityForTool(tool);
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Selection tools options
          if (_activeTool == DrawingToolType.lasso && _selectedStrokeIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Text('${_selectedStrokeIds.length} stroke(s) selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      final notifier = ref.read(drawingEditorProvider(widget.noteId).notifier);
                      notifier.eraseMultipleStrokes(_selectedStrokeIds);
                      setState(() {
                        _selectedStrokeIds.clear();
                      });
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Delete Selected', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          if (_activeTool != DrawingToolType.eraser && _activeTool != DrawingToolType.lasso) ...[
            // Color Presets
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _presetColors.map((color) {
                final isSelected = _activeColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeColor = color;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: isSelected ? 34 : 26,
                    height: isSelected ? 34 : 26,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey[300]!,
                        width: isSelected ? 3.0 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // Thickness Slider
            Row(
              children: [
                const Icon(Icons.line_weight, size: 18),
                Expanded(
                  child: Slider(
                    value: _activeThickness,
                    min: 1.0,
                    max: 40.0,
                    onChanged: (val) {
                      setState(() {
                        _activeThickness = val;
                      });
                    },
                  ),
                ),
                Text('${_activeThickness.toInt()}px', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageIndicatorBar(
      DrawingEditorState state, DrawingEditorNotifier notifier) {
    if (state.pages.isEmpty) return const SizedBox.shrink();

    final currentPage = state.pages[state.currentPageIndex];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: state.currentPageIndex > 0
                ? () => notifier.changePage(state.currentPageIndex - 1)
                : null,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page ${state.currentPageIndex + 1} of ${state.pages.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (currentPage.pdfPath != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.picture_as_pdf, size: 14, color: Colors.red),
                const SizedBox(width: 2),
                Text('PDF p.${currentPage.pageNumber}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => notifier.addPage(backgroundType: 'blank'),
                tooltip: 'Add Page',
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => notifier.duplicatePage(state.currentPageIndex),
                tooltip: 'Duplicate Page',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: state.pages.length > 1
                    ? () => notifier.deletePage(state.currentPageIndex)
                    : null,
                tooltip: 'Delete Page',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drawingEditorProvider(widget.noteId));
    final notifier = ref.read(drawingEditorProvider(widget.noteId).notifier);

    // Tablet layout detection (width > 800)
    final isTablet = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: Column(
          children: [
            // Top Toolbar
            _buildTopToolbar(context, state, notifier),

            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        // Tablet Left Page Thumbnails sidebar
                        if (isTablet && state.pages.isNotEmpty)
                          Container(
                            width: 140,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(right: BorderSide(color: Colors.grey[200]!)),
                            ),
                            child: ListView.builder(
                              itemCount: state.pages.length,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, idx) {
                                final isSelected = state.currentPageIndex == idx;
                                final page = state.pages[idx];
                                return GestureDetector(
                                  onTap: () => notifier.changePage(idx),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.blue[50] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? Colors.blue : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 3 / 4,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            page.pdfPath != null ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                            size: 28,
                                            color: page.pdfPath != null ? Colors.red : Colors.grey,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Page ${idx + 1}',
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Center Canvas Viewport
                        Expanded(
                          child: Column(
                            children: [
                              // Page control header for phone layout (or tablet backup)
                              if (!isTablet) _buildPageIndicatorBar(state, notifier),

                              Expanded(
                                child: state.pages.isEmpty
                                    ? const Center(child: Text('No drawing pages available.'))
                                    : DrawingCanvas(
                                        pageId: state.pages[state.currentPageIndex].id,
                                        strokes: state.currentStrokes,
                                        activeTool: _activeTool,
                                        activeColor: _activeColor,
                                        activeThickness: _activeThickness,
                                        activeOpacity: _activeOpacity,
                                        backgroundType: state.pages[state.currentPageIndex].backgroundType,
                                        pdfPath: state.pages[state.currentPageIndex].pdfPath,
                                        pageNumber: state.pages[state.currentPageIndex].pageNumber,
                                        penOnlyMode: _penOnlyMode,
                                        onStrokeCompleted: (stroke) {
                                          notifier.saveStroke(stroke);
                                        },
                                        onStrokeErased: (id) {
                                          notifier.eraseStroke(id);
                                        },
                                        onStrokesSelected: (selectedIds) {
                                          setState(() {
                                            _selectedStrokeIds = selectedIds;
                                          });
                                        },
                                      ),
                              ),

                              // Phone brush bar (docked at the bottom)
                              if (!isTablet) _buildBrushOptions(context),
                            ],
                          ),
                        ),

                        // Tablet Right Tool Customizer sidebar
                        if (isTablet)
                          Container(
                            width: 250,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(left: BorderSide(color: Colors.grey[200]!)),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Text(
                                          'Drawing Tools',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildBrushOptions(context),
                                        const Divider(height: 32),
                                        const Text(
                                          'Document Actions',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: () => _importPdf(notifier),
                                          icon: const Icon(Icons.picture_as_pdf),
                                          label: const Text('Import PDF Page overlays'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red[50],
                                            foregroundColor: Colors.red[900],
                                            elevation: 0,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ElevatedButton.icon(
                                          onPressed: () => _exportAsPdf(state.pages, notifier),
                                          icon: const Icon(Icons.print),
                                          label: const Text('Export full PDF Document'),
                                          style: ElevatedButton.styleFrom(
                                            elevation: 0,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'Page Settings',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          value: state.pages.isNotEmpty
                                              ? state.pages[state.currentPageIndex].backgroundType
                                              : 'blank',
                                          onChanged: (bg) {
                                            if (bg != null) {
                                              notifier.updateBackgroundType(bg);
                                            }
                                          },
                                          items: const [
                                            DropdownMenuItem(value: 'blank', child: Text('Blank paper')),
                                            DropdownMenuItem(value: 'ruled', child: Text('Ruled paper')),
                                            DropdownMenuItem(value: 'grid', child: Text('Grid paper')),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Paper Pattern',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Bottom page manager inside Tablet Sidebar
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  color: Colors.grey[50],
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Pages (${state.pages.length})',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add),
                                            onPressed: () => notifier.addPage(),
                                            tooltip: 'Add Page',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          ElevatedButton(
                                            onPressed: state.currentPageIndex > 0
                                                ? () => notifier.changePage(state.currentPageIndex - 1)
                                                : null,
                                            child: const Icon(Icons.chevron_left),
                                          ),
                                          Text('${state.currentPageIndex + 1}/${state.pages.length}'),
                                          ElevatedButton(
                                            onPressed: state.currentPageIndex < state.pages.length - 1
                                                ? () => notifier.changePage(state.currentPageIndex + 1)
                                                : null,
                                            child: const Icon(Icons.chevron_right),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
