import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';

class GraphViewScreen extends ConsumerStatefulWidget {
  const GraphViewScreen({super.key});

  @override
  ConsumerState<GraphViewScreen> createState() => _GraphViewScreenState();
}

class _GraphViewScreenState extends ConsumerState<GraphViewScreen>
    with TickerProviderStateMixin {
  List<Note> _notes = [];
  List<_GraphNode> _nodes = [];
  List<_GraphEdge> _edges = [];
  bool _isLoading = true;
  late AnimationController _animController;
  final TransformationController _transformController = TransformationController();
  _GraphNode? _selectedNode;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    final db = AppDatabase.instance;
    final allNotes = await (db.select(db.notes)
      ..where((n) => n.isArchived.equals(false)))
        .get();
    final allLinks = await db.getAllNoteLinks();

    final random = Random(42);
    final center = const Offset(400, 400);

    // Create nodes in circular layout
    final nodes = <_GraphNode>[];
    for (int i = 0; i < allNotes.length; i++) {
      final angle = (2 * pi * i) / allNotes.length;
      final radius = 150.0 + random.nextDouble() * 200;
      nodes.add(_GraphNode(
        id: allNotes[i].id,
        label: allNotes[i].title,
        position: Offset(
          center.dx + radius * cos(angle),
          center.dy + radius * sin(angle),
        ),
        connectionCount: 0,
      ));
    }

    // Create edges and count connections
    final edges = <_GraphEdge>[];
    for (final link in allLinks) {
      final source = nodes.indexWhere((n) => n.id == link.sourceNoteId);
      final target = nodes.indexWhere((n) => n.id == link.targetNoteId);
      if (source != -1 && target != -1) {
        edges.add(_GraphEdge(sourceIndex: source, targetIndex: target));
        nodes[source] = nodes[source]
            .copyWith(connectionCount: nodes[source].connectionCount + 1);
        nodes[target] = nodes[target]
            .copyWith(connectionCount: nodes[target].connectionCount + 1);
      }
    }

    if (mounted) {
      setState(() {
        _notes = allNotes;
        _nodes = nodes;
        _edges = edges;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Graph'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGraph,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hub_outlined,
                          size: 64, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('No notes to graph',
                          style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Create notes and link them with [[wiki links]]',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // Graph canvas
                    InteractiveViewer(
                      transformationController: _transformController,
                      boundaryMargin: const EdgeInsets.all(500),
                      minScale: 0.1,
                      maxScale: 3.0,
                      child: SizedBox(
                        width: 800,
                        height: 800,
                        child: CustomPaint(
                          painter: _GraphPainter(
                            nodes: _nodes,
                            edges: _edges,
                            selectedNode: _selectedNode,
                            colorScheme: colorScheme,
                          ),
                          child: GestureDetector(
                            onTapDown: (details) {
                              _handleTap(details.localPosition);
                            },
                          ),
                        ),
                      ),
                    ),
                    // Search overlay
                    Positioned(
                      top: 8,
                      left: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search nodes...',
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              if (value.isNotEmpty) {
                                final match = _nodes.indexWhere((n) =>
                                    n.label
                                        .toLowerCase()
                                        .contains(value.toLowerCase()));
                                if (match != -1) {
                                  _selectedNode = _nodes[match];
                                }
                              } else {
                                _selectedNode = null;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    // Node info panel
                    if (_selectedNode != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.description,
                                      color: colorScheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _selectedNode!.label,
                                        style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${_selectedNode!.connectionCount} connections',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: () => context.push(
                                      '/notes/detail/${_selectedNode!.id}'),
                                  child: const Text('Open'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Legend
                    Positioned(
                      bottom: _selectedNode != null ? 100 : 16,
                      right: 16,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_nodes.length} notes',
                                  style: textTheme.labelSmall),
                              Text('${_edges.length} links',
                                  style: textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _handleTap(Offset position) {
    for (final node in _nodes) {
      final nodeRadius = 8.0 + node.connectionCount * 2.0;
      if ((position - node.position).distance < nodeRadius + 10) {
        setState(() => _selectedNode = node);
        return;
      }
    }
    setState(() => _selectedNode = null);
  }
}

class _GraphNode {
  final String id;
  final String label;
  final Offset position;
  final int connectionCount;

  _GraphNode({
    required this.id,
    required this.label,
    required this.position,
    required this.connectionCount,
  });

  _GraphNode copyWith({int? connectionCount}) {
    return _GraphNode(
      id: id,
      label: label,
      position: position,
      connectionCount: connectionCount ?? this.connectionCount,
    );
  }
}

class _GraphEdge {
  final int sourceIndex;
  final int targetIndex;

  _GraphEdge({required this.sourceIndex, required this.targetIndex});
}

class _GraphPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final _GraphNode? selectedNode;
  final ColorScheme colorScheme;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw edges
    final edgePaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      if (edge.sourceIndex < nodes.length && edge.targetIndex < nodes.length) {
        canvas.drawLine(
          nodes[edge.sourceIndex].position,
          nodes[edge.targetIndex].position,
          edgePaint,
        );
      }
    }

    // Draw nodes
    for (final node in nodes) {
      final radius = 8.0 + node.connectionCount * 2.0;
      final isSelected = selectedNode?.id == node.id;

      // Node circle
      final nodePaint = Paint()
        ..color = isSelected
            ? AppColors.graphNodeActive
            : colorScheme.primary.withValues(alpha: 0.7 + node.connectionCount * 0.05)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(node.position, radius, nodePaint);

      // Glow for selected
      if (isSelected) {
        final glowPaint = Paint()
          ..color = AppColors.graphNodeActive.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(node.position, radius + 6, glowPaint);
      }

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label.length > 15
              ? '${node.label.substring(0, 15)}...'
              : node.label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          node.position.dx - textPainter.width / 2,
          node.position.dy + radius + 4,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
