import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../../core/database/app_database.dart';

class FlashcardWidget extends StatefulWidget {
  final FlashCard card;
  final String deckName;
  final int currentIndex;
  final int totalCards;
  final VoidCallback? onFlip;

  const FlashcardWidget({
    super.key,
    required this.card,
    required this.deckName,
    required this.currentIndex,
    required this.totalCards,
    this.onFlip,
  });

  @override
  State<FlashcardWidget> createState() => _FlashcardWidgetState();
}

class _FlashcardWidgetState extends State<FlashcardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFront = true;

  // MCQ & True/False Selection State
  int? _selectedMcqIndex;
  bool? _selectedTf;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _flipController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant FlashcardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the card changes, reset states instantly
    if (oldWidget.card.id != widget.card.id) {
      _flipController.reset();
      setState(() {
        _isFront = true;
        _selectedMcqIndex = null;
        _selectedTf = null;
      });
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_flipController.isAnimating) return;

    if (_isFront) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }

    setState(() {
      _isFront = !_isFront;
    });

    widget.onFlip?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final tags = widget.card.tags.isNotEmpty
        ? widget.card.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    return Semantics(
      label: 'Flashcard ${widget.currentIndex + 1} of ${widget.totalCards}. Tap to flip.',
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _flipAnimation,
          builder: (context, child) {
            final angle = _flipAnimation.value * pi;
            final isFrontSide = _flipAnimation.value < 0.5;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // perspective
                ..rotateY(angle),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isFrontSide
                          ? [
                              colorScheme.primaryContainer.withValues(alpha: 0.2),
                              colorScheme.surface,
                            ]
                          : [
                              colorScheme.tertiaryContainer.withValues(alpha: 0.15),
                              colorScheme.surface,
                            ],
                    ),
                  ),
                  child: isFrontSide
                      ? _buildSideContent(
                          context,
                          isFront: true,
                          title: _getSideTitle(isFront: true),
                          tags: tags,
                        )
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(pi),
                          child: _buildSideContent(
                            context,
                            isFront: false,
                            title: _getSideTitle(isFront: false),
                            tags: tags,
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getSideTitle({required bool isFront}) {
    if (isFront) {
      return switch (widget.card.cardType) {
        'cloze' => 'FILL IN THE BLANK',
        'true_false' => 'TRUE OR FALSE',
        'mcq' => 'MULTIPLE CHOICE',
        _ => 'QUESTION',
      };
    } else {
      return 'ANSWER';
    }
  }

  Widget _buildSideContent(
    BuildContext context, {
    required bool isFront,
    required String title,
    required List<String> tags,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Deck Name & Progress Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.deckName,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${widget.currentIndex + 1} / ${widget.totalCards}',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (widget.currentIndex + 1) / widget.totalCards,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 24),
          // Content Scroll Area
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      title,
                      style: textTheme.labelSmall?.copyWith(
                        color: isFront ? colorScheme.primary : colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCardBody(context, isFront),
                ],
              ),
            ),
          ),
          // Footer: Tags
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: tags.map((tag) {
                return Chip(
                  label: Text(
                    tag,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBody(BuildContext context, bool isFront) {
    final cardType = widget.card.cardType;

    switch (cardType) {
      case 'cloze':
        return _buildClozeBody(context, isFront);
      case 'mcq':
        return _buildMcqBody(context, isFront);
      case 'true_false':
        return _buildTfBody(context, isFront);
      case 'reverse':
        return _buildReverseBody(context, isFront);
      case 'basic':
      default:
        return _buildBasicBody(context, isFront);
    }
  }

  // ─────────────────────────── BASIC RENDER ───────────────────────────
  Widget _buildBasicBody(BuildContext context, bool isFront) {
    final content = isFront ? widget.card.front : widget.card.back;
    return _renderMarkdown(context, content, isFront);
  }

  // ─────────────────────────── REVERSE RENDER ───────────────────────────
  Widget _buildReverseBody(BuildContext context, bool isFront) {
    final content = isFront ? widget.card.back : widget.card.front;
    return _renderMarkdown(context, content, isFront);
  }

  // ─────────────────────────── CLOZE RENDER ───────────────────────────
  Widget _buildClozeBody(BuildContext context, bool isFront) {
    final regExp = RegExp(r'\{\{c\d+::(.*?)\}\}');
    String displayContent;

    if (isFront) {
      // Replace clozes with [...]
      displayContent = widget.card.front.replaceAllMapped(regExp, (m) => '**[...]**');
    } else {
      // Replace clozes with highlighted text
      displayContent = widget.card.front.replaceAllMapped(regExp, (m) => '**${m[1]}**');
      if (widget.card.back.trim().isNotEmpty) {
        displayContent += '\n\n---\n\n${widget.card.back}';
      }
    }

    return _renderMarkdown(context, displayContent, isFront);
  }

  // ─────────────────────────── MCQ RENDER ───────────────────────────
  Widget _buildMcqBody(BuildContext context, bool isFront) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Split options
    final lines = widget.card.back.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final options = lines.map((l) => l.startsWith('*') ? l.substring(1).trim() : l).toList();
    final correctIndex = lines.indexWhere((l) => l.startsWith('*'));

    if (isFront) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renderMarkdown(context, widget.card.front, true),
          const SizedBox(height: 20),
          ...options.asMap().entries.map((entry) {
            final idx = entry.key;
            final optionText = entry.value;
            final isSelected = _selectedMcqIndex == idx;

            return Card(
              color: isSelected ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                ),
              ),
              child: ListTile(
                title: Text(optionText, style: textTheme.bodyMedium),
                leading: Radio<int>(
                  value: idx,
                  groupValue: _selectedMcqIndex,
                  onChanged: (val) {
                    setState(() {
                      _selectedMcqIndex = val;
                    });
                  },
                ),
                onTap: () {
                  setState(() {
                    _selectedMcqIndex = idx;
                  });
                },
              ),
            );
          }),
        ],
      );
    } else {
      // Back side: show correct vs incorrect
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renderMarkdown(context, widget.card.front, false),
          const SizedBox(height: 20),
          ...options.asMap().entries.map((entry) {
            final idx = entry.key;
            final optionText = entry.value;
            final isCorrect = idx == correctIndex;
            final isSelected = _selectedMcqIndex == idx;

            Color bgColor = colorScheme.surfaceContainerLow;
            BorderSide border = BorderSide(color: colorScheme.outlineVariant);
            Widget? trailing;

            if (isCorrect) {
              bgColor = Colors.green.withValues(alpha: 0.15);
              border = const BorderSide(color: Colors.green, width: 1.5);
              trailing = const Icon(Icons.check_circle, color: Colors.green);
            } else if (isSelected) {
              bgColor = Colors.red.withValues(alpha: 0.15);
              border = const BorderSide(color: Colors.red, width: 1.5);
              trailing = const Icon(Icons.cancel, color: Colors.red);
            }

            return Card(
              color: bgColor,
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: border,
              ),
              child: ListTile(
                title: Text(
                  optionText,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: isCorrect ? FontWeight.bold : null,
                  ),
                ),
                trailing: trailing,
              ),
            );
          }),
        ],
      );
    }
  }

  // ─────────────────────────── TRUE / FALSE RENDER ───────────────────────────
  Widget _buildTfBody(BuildContext context, bool isFront) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final correctTf = widget.card.back.trim().toLowerCase() == 'true';

    if (isFront) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renderMarkdown(context, widget.card.front, true),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: _selectedTf == true ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedTf == true ? colorScheme.primary : colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selectedTf = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 28),
                          const SizedBox(height: 8),
                          Text('True', style: textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  color: _selectedTf == false ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _selectedTf == false ? colorScheme.primary : colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selectedTf = false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(Icons.cancel_outlined, color: colorScheme.primary, size: 28),
                          const SizedBox(height: 8),
                          Text('False', style: textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // Back side: show correct vs incorrect
      final userCorrect = _selectedTf == correctTf;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renderMarkdown(context, widget.card.front, false),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: correctTf
                      ? Colors.green.withValues(alpha: 0.15)
                      : (_selectedTf == true ? Colors.red.withValues(alpha: 0.15) : colorScheme.surfaceContainerLow),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: correctTf
                          ? Colors.green
                          : (_selectedTf == true ? Colors.red : colorScheme.outlineVariant),
                      width: correctTf || _selectedTf == true ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Icon(
                          correctTf ? Icons.check_circle : Icons.check_circle_outline,
                          color: correctTf ? Colors.green : colorScheme.onSurfaceVariant,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text('True', style: textTheme.labelLarge),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  color: !correctTf
                      ? Colors.green.withValues(alpha: 0.15)
                      : (_selectedTf == false ? Colors.red.withValues(alpha: 0.15) : colorScheme.surfaceContainerLow),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: !correctTf
                          ? Colors.green
                          : (_selectedTf == false ? Colors.red : colorScheme.outlineVariant),
                      width: !correctTf || _selectedTf == false ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Icon(
                          !correctTf ? Icons.check_circle : Icons.cancel_outlined,
                          color: !correctTf ? Colors.green : colorScheme.onSurfaceVariant,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text('False', style: textTheme.labelLarge),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              userCorrect ? '🎉 Correct!' : '❌ Incorrect',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: userCorrect ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      );
    }
  }

  // ─────────────────────────── MARKDOWN RENDERER ───────────────────────────
  Widget _renderMarkdown(BuildContext context, String content, bool isFront) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: textTheme.bodyLarge?.copyWith(
          fontSize: isFront ? 24 : 18,
          fontWeight: isFront ? FontWeight.w600 : FontWeight.w500,
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        listBullet: textTheme.bodyLarge?.copyWith(
          fontSize: isFront ? 24 : 18,
          color: colorScheme.onSurface,
        ),
        code: textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: colorScheme.surfaceContainerHighest,
          color: colorScheme.primary,
        ),
        codeblockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
