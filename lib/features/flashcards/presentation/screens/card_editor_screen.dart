import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';

class CardEditorScreen extends ConsumerStatefulWidget {
  final String deckId;
  final String? cardId;
  const CardEditorScreen({super.key, required this.deckId, this.cardId});

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  String _cardType = 'basic';
  bool _isLoading = false;
  FlashCard? _existingCard;

  final _cardTypes = [
    ('basic', 'Basic Q&A', Icons.quiz),
    ('reverse', 'Reverse', Icons.swap_horiz),
    ('cloze', 'Cloze', Icons.text_fields),
    ('mcq', 'Multiple Choice', Icons.checklist),
    ('true_false', 'True/False', Icons.toggle_on),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.cardId != null) _loadCard();
  }

  Future<void> _loadCard() async {
    setState(() => _isLoading = true);
    final card = await AppDatabase.instance.getCardById(widget.cardId!);
    if (card != null && mounted) {
      setState(() {
        _existingCard = card;
        _frontController.text = card.front;
        _backController.text = card.back;
        _cardType = card.cardType;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCard() async {
    if (_frontController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Front side cannot be empty')),
      );
      return;
    }

    if (_existingCard != null) {
      await AppDatabase.instance.updateCard(FlashCardsCompanion(
        id: drift.Value(_existingCard!.id),
        front: drift.Value(_frontController.text.trim()),
        back: drift.Value(_backController.text.trim()),
        cardType: drift.Value(_cardType),
        updatedAt: drift.Value(DateTime.now()),
      ));
    } else {
      await AppDatabase.instance.createCard(FlashCardsCompanion.insert(
        id: const Uuid().v4(),
        deckId: widget.deckId,
        front: _frontController.text.trim(),
        back: _backController.text.trim(),
        cardType: drift.Value(_cardType),
        dueDate: drift.Value(DateTime.now()),
      ));
    }

    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cardId != null ? 'Edit Card' : 'New Card'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _saveCard),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card type selector
                  Text('Card Type', style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _cardTypes.map((type) {
                        final isSelected = _cardType == type.$1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: isSelected,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(type.$3, size: 16),
                                const SizedBox(width: 6),
                                Text(type.$2),
                              ],
                            ),
                            onSelected: (_) => setState(() => _cardType = type.$1),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Front
                  Text(_getFrontLabel(), style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _frontController,
                      decoration: InputDecoration(
                        hintText: _getFrontHint(),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      maxLines: 5,
                      minLines: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Back
                  Text(_getBackLabel(), style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _backController,
                      decoration: InputDecoration(
                        hintText: _getBackHint(),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      maxLines: 5,
                      minLines: 3,
                    ),
                  ),
                  if (_cardType == 'cloze') ...[
                    const SizedBox(height: 12),
                    Card(
                      color: colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Use {{c1::text}} to create cloze deletions',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  // Preview
                  Text('Preview', style: textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _CardPreview(
                    front: _frontController.text,
                    back: _backController.text,
                    cardType: _cardType,
                  ),
                ],
              ),
            ),
    );
  }

  String _getFrontLabel() => switch (_cardType) {
    'cloze' => 'Text (with cloze)',
    'true_false' => 'Statement',
    'mcq' => 'Question',
    _ => 'Front',
  };

  String _getBackLabel() => switch (_cardType) {
    'cloze' => 'Extra info (optional)',
    'true_false' => 'Answer (True/False)',
    'mcq' => 'Options (one per line, * for correct)',
    _ => 'Back',
  };

  String _getFrontHint() => switch (_cardType) {
    'cloze' => 'The capital of France is {{c1::Paris}}.',
    'true_false' => 'Flutter uses Dart as its programming language.',
    'mcq' => 'What is the default state management in Flutter?',
    _ => 'Question or concept...',
  };

  String _getBackHint() => switch (_cardType) {
    'cloze' => 'Additional context...',
    'true_false' => 'True',
    'mcq' => '*setState\nProvider\nGetX\nMobX',
    _ => 'Answer or explanation...',
  };
}

class _CardPreview extends StatefulWidget {
  final String front;
  final String back;
  final String cardType;

  const _CardPreview({required this.front, required this.back, required this.cardType});

  @override
  State<_CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends State<_CardPreview> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => setState(() => _showBack = !_showBack),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _showBack
                ? [colorScheme.tertiaryContainer, colorScheme.surfaceContainerHighest]
                : [colorScheme.primaryContainer, colorScheme.surfaceContainerHighest],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              _showBack ? 'Back' : 'Front',
              style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              _showBack
                  ? (widget.back.isEmpty ? 'Tap to flip' : widget.back)
                  : (widget.front.isEmpty ? 'Enter text above' : widget.front),
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text('Tap to flip', style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
