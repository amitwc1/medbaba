import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import 'package:drift/drift.dart' as drift;
import '../../../../core/constants/route_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';

// Notes provider
final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  return AppDatabase.instance.watchAllNotes();
});

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  bool _isGridView = false;
  String _sortBy = 'updated';

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'updated', child: Text('Last Modified')),
              const PopupMenuItem(value: 'created', child: Text('Date Created')),
              const PopupMenuItem(value: 'title', child: Text('Title')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: 'Graph View',
            onPressed: () => context.push(RouteConstants.noteGraph),
          ),
        ],
      ),
      body: notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.note_add_outlined,
              title: 'No notes yet',
              subtitle: 'Start capturing your thoughts and ideas',
              actionLabel: 'Create Note',
              onAction: () => context.push(RouteConstants.noteEditor),
            );
          }

          // Sort notes
          final sorted = List<Note>.from(notes);
          sorted.sort((a, b) {
            switch (_sortBy) {
              case 'title':
                return a.title.compareTo(b.title);
              case 'created':
                return b.createdAt.compareTo(a.createdAt);
              default:
                return b.updatedAt.compareTo(a.updatedAt);
            }
          });

          if (_isGridView) {
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                return FadeInUp(
                  duration: const Duration(milliseconds: 300),
                  delay: Duration(milliseconds: 30 * index),
                  child: _NoteGridCard(note: sorted[index]),
                );
              },
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              return FadeInUp(
                duration: const Duration(milliseconds: 300),
                delay: Duration(milliseconds: 30 * index),
                child: _NoteListTile(note: sorted[index]),
              );
            },
          );
        },
        loading: () => const LoadingWidget(useShimmer: true),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create New Note',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.note_alt, color: Colors.white),
                      ),
                      title: const Text('Standard Note', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Create a rich-text document with attachments'),
                      onTap: () {
                        Navigator.pop(context);
                        context.push(RouteConstants.noteEditor);
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.edit, color: Colors.white),
                      ),
                      title: const Text('Handwritten Note', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Write and sketch on canvas with stylus support'),
                      onTap: () {
                        Navigator.pop(context);
                        context.push(RouteConstants.drawingEditor);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  final Note note;
  const _NoteListTile({required this.note});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/notes/detail/${note.id}'),
        onLongPress: () => _showOptions(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin,
                          size: 16, color: colorScheme.primary),
                    ),
                  if (note.isFavorite)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.star,
                          size: 16, color: Colors.amber.shade600),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (note.plainText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.plainText,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time,
                      size: 12, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(note.updatedAt),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.text_fields,
                      size: 12, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${note.wordCount} words',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('${RouteConstants.noteEditor}?id=${note.id}');
              },
            ),
            ListTile(
              leading: Icon(
                  note.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(note.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                AppDatabase.instance.updateNote(
                  NotesCompanion(
                    id: drift.Value(note.id),
                    isPinned: drift.Value(!note.isPinned),
                    updatedAt: drift.Value(DateTime.now()),
                  ),
                );
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(
                  note.isFavorite ? Icons.star_outline : Icons.star),
              title: Text(note.isFavorite ? 'Unfavorite' : 'Favorite'),
              onTap: () {
                AppDatabase.instance.updateNote(
                  NotesCompanion(
                    id: drift.Value(note.id),
                    isFavorite: drift.Value(!note.isFavorite),
                    updatedAt: drift.Value(DateTime.now()),
                  ),
                );
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () {
                AppDatabase.instance.updateNote(
                  NotesCompanion(
                    id: drift.Value(note.id),
                    isArchived: const drift.Value(true),
                    updatedAt: drift.Value(DateTime.now()),
                  ),
                );
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                AppDatabase.instance.deleteNote(note.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _NoteGridCard extends StatelessWidget {
  final Note note;
  const _NoteGridCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/notes/detail/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.isPinned)
                    Icon(Icons.push_pin, size: 14, color: colorScheme.primary),
                  if (note.isFavorite)
                    Icon(Icons.star, size: 14, color: Colors.amber.shade600),
                  const Spacer(),
                  Text(
                    '${note.wordCount}w',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note.title,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  note.plainText,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
