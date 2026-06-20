import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';

final decksStreamProvider = StreamProvider<List<Deck>>((ref) {
  return AppDatabase.instance.watchRootDecks();
});

class DeckListScreen extends ConsumerWidget {
  const DeckListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(decksStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Decks'),
      ),
      body: decksAsync.when(
        data: (decks) {
          if (decks.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.style_outlined,
              title: 'No decks yet',
              subtitle: 'Create your first deck to start learning',
              actionLabel: 'Create Deck',
              onAction: () => _showCreateDeckDialog(context),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: decks.length,
            itemBuilder: (context, index) {
              final deck = decks[index];
              return FadeInUp(
                duration: const Duration(milliseconds: 300),
                delay: Duration(milliseconds: 50 * index),
                child: _DeckCard(deck: deck),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDeckDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Deck'),
      ),
    );
  }

  void _showCreateDeckDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Deck'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Deck Title',
                hintText: 'e.g., Flutter Basics',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this deck about?',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleController.text.trim().isNotEmpty) {
                await AppDatabase.instance.createDeck(
                  DecksCompanion.insert(
                    id: const Uuid().v4(),
                    title: titleController.text.trim(),
                    description: drift.Value(descController.text.trim()),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _DeckCard extends StatefulWidget {
  final Deck deck;
  const _DeckCard({required this.deck});

  @override
  State<_DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<_DeckCard> {
  int _totalCards = 0;
  int _dueCards = 0;
  DateTime? _lastStudied;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final total = await AppDatabase.instance.countCardsInDeck(widget.deck.id);
    final due = await AppDatabase.instance.countDueCardsInDeck(widget.deck.id);
    final latestSession = await AppDatabase.instance.getLatestSessionForDeck(widget.deck.id);
    if (mounted) {
      setState(() {
        _totalCards = total;
        _dueCards = due;
        if (latestSession != null) {
          _lastStudied = latestSession.startedAt;
          if (latestSession.totalCards > 0) {
            _progress = latestSession.cardsReviewed / latestSession.totalCards;
          }
        }
      });
    }
  }

  String _formatLastStudied(DateTime? date) {
    if (date == null) return 'Never studied';
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) {
      return 'Last studied: ${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return 'Last studied: ${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return 'Last studied: ${diff.inMinutes}m ago';
    } else {
      return 'Last studied: Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/decks/detail/${widget.deck.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Color indicator
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.style, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.deck.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.deck.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.deck.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '$_totalCards cards',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_dueCards > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.reviewHard.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$_dueCards due',
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.reviewHard,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatLastStudied(_lastStudied),
                          style: textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        if (_progress > 0)
                          Text(
                            'Session: ${(_progress * 100).round()}%',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    if (_progress > 0 && _progress < 1.0) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 3,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Study button (always enabled and visible)
              FilledButton.tonal(
                onPressed: () =>
                    context.push('/review/${widget.deck.id}'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Study'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
