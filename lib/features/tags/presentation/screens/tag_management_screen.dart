import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/empty_state_widget.dart';

final tagsStreamProvider = StreamProvider<List<Tag>>((ref) {
  return AppDatabase.instance.watchAllTags();
});

class TagManagementScreen extends ConsumerWidget {
  const TagManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagsAsync = ref.watch(tagsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: tagsAsync.when(
        data: (tags) {
          if (tags.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.label_outlined,
              title: 'No tags yet',
              subtitle: 'Create tags to organize your notes',
              actionLabel: 'Create Tag',
              onAction: () => _showCreateTagDialog(context),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tags.length} tags', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags.map((tag) {
                      final tagColor = _parseColor(tag.color);
                      return GestureDetector(
                        onLongPress: () => _showTagOptions(context, tag),
                        child: Chip(
                          avatar: CircleAvatar(backgroundColor: tagColor, radius: 10),
                          label: Text(tag.name),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () async {
                            await AppDatabase.instance.deleteTag(tag.id);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateTagDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF6750A4);
    }
  }

  void _showCreateTagDialog(BuildContext context) {
    final controller = TextEditingController();
    Color selectedColor = const Color(0xFF6750A4);
    final colors = [
      const Color(0xFF6750A4),
      const Color(0xFF00BFA5),
      const Color(0xFFFF6D00),
      const Color(0xFF0288D1),
      const Color(0xFFD32F2F),
      const Color(0xFF2E7D32),
      const Color(0xFF7B1FA2),
      const Color(0xFFF9A825),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Tag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Tag Name', hintText: 'e.g., flutter'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: colors.map((c) => GestureDetector(
                  onTap: () => setDialogState(() => selectedColor = c),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selectedColor == c
                          ? Border.all(color: Theme.of(ctx).colorScheme.onSurface, width: 3)
                          : null,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  final hex = '#${selectedColor.toARGB32().toRadixString(16).substring(2)}';
                  await AppDatabase.instance.createTag(TagsCompanion.insert(
                    id: const Uuid().v4(),
                    name: controller.text.trim(),
                    color: drift.Value(hex),
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagOptions(BuildContext context, Tag tag) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete Tag'),
              onTap: () async {
                await AppDatabase.instance.deleteTag(tag.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}
