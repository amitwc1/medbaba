import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/constants/route_constants.dart';

class DeckDetailScreen extends ConsumerStatefulWidget {
  final String deckId;
  const DeckDetailScreen({super.key, required this.deckId});

  @override
  ConsumerState<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends ConsumerState<DeckDetailScreen> {
  Deck? _deck;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeck();
  }

  Future<void> _loadDeck() async {
    final deck = await AppDatabase.instance.getDeckById(widget.deckId);
    if (mounted) setState(() { _deck = deck; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (_deck == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Deck not found')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_deck!.title),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Deck')),
              const PopupMenuItem(value: 'delete', child: Text('Delete Deck')),
            ],
            onSelected: (v) async {
              if (v == 'delete') {
                await AppDatabase.instance.deleteDeck(widget.deckId);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Deck stats
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _StatChip(label: 'Study', icon: Icons.play_arrow, color: colorScheme.primary,
                  onTap: () => context.push('/review/${widget.deckId}')),
                const SizedBox(width: 8),
                _StatChip(label: 'Cram', icon: Icons.flash_on, color: Colors.orange,
                  onTap: () => context.push('/review/${widget.deckId}?mode=cram')),
                const SizedBox(width: 8),
                _StatChip(label: 'Learn', icon: Icons.school, color: Colors.blue,
                  onTap: () => context.push('/review/${widget.deckId}?mode=learn')),
              ],
            ),
          ),
          const Divider(height: 0),
          // Cards list
          Expanded(
            child: StreamBuilder<List<FlashCard>>(
              stream: AppDatabase.instance.watchCardsInDeck(widget.deckId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final cards = snapshot.data!;
                if (cards.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.style_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('No cards in this deck', style: textTheme.bodyLarge),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => context.push('${RouteConstants.cardEditor}?deckId=${widget.deckId}'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Card'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(card.front, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(card.back, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        trailing: Chip(
                          label: Text(card.state, style: textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                        ),
                        onTap: () => context.push('${RouteConstants.cardEditor}?deckId=${widget.deckId}&cardId=${card.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('${RouteConstants.cardEditor}?deckId=${widget.deckId}'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatChip({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
