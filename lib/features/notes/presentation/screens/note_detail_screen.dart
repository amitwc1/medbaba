import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/extensions.dart';

class NoteDetailScreen extends ConsumerStatefulWidget {
  final String noteId;
  const NoteDetailScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  Note? _note;
  List<Note> _backlinks = [];
  List<Note> _forwardLinks = [];
  List<Tag> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final db = AppDatabase.instance;
    
    // Check if this is a drawing note
    final drawingNote = await (db.select(db.drawingNotes)
          ..where((dn) => dn.noteId.equals(widget.noteId)))
        .getSingleOrNull();
        
    if (drawingNote != null && mounted) {
      context.replace('${RouteConstants.drawingEditor}?id=${drawingNote.id}');
      return;
    }

    final note = await db.getNoteById(widget.noteId);
    final backlinks = await db.getBacklinks(widget.noteId);
    final forwardLinks = await db.getForwardLinks(widget.noteId);
    final tags = await db.getTagsForNote(widget.noteId);
    if (mounted) {
      setState(() {
        _note = note;
        _backlinks = backlinks;
        _forwardLinks = forwardLinks;
        _tags = tags;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_note == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Note not found')),
      );
    }

    final note = _note!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(
            icon: Icon(note.isFavorite ? Icons.star : Icons.star_border,
                color: note.isFavorite ? Colors.amber.shade600 : null),
            onPressed: () async {
              await AppDatabase.instance.updateNote(NotesCompanion(
                id: drift.Value(note.id),
                isFavorite: drift.Value(!note.isFavorite),
              ));
              _loadNote();
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push('${RouteConstants.noteEditor}?id=${note.id}'),
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'pin', child: Text('Pin/Unpin')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
              const PopupMenuItem(value: 'ai_summary', child: Text('AI Summary')),
              const PopupMenuItem(value: 'ai_cards', child: Text('Generate Flashcards')),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'pin':
                  await AppDatabase.instance.updateNote(NotesCompanion(
                    id: drift.Value(note.id),
                    isPinned: drift.Value(!note.isPinned),
                  ));
                  _loadNote();
                  break;
                case 'duplicate':
                  await AppDatabase.instance.createNote(NotesCompanion.insert(
                    id: const Uuid().v4(),
                    title: drift.Value('${note.title} (Copy)'),
                    content: drift.Value(note.content),
                    plainText: drift.Value(note.plainText),
                    wordCount: drift.Value(note.wordCount),
                    readingTimeSeconds: drift.Value(note.readingTimeSeconds),
                  ));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Note duplicated')),
                    );
                  }
                  break;
                case 'archive':
                  await AppDatabase.instance.updateNote(NotesCompanion(
                    id: drift.Value(note.id),
                    isArchived: const drift.Value(true),
                  ));
                  if (context.mounted) context.pop();
                  break;
                case 'delete':
                  await AppDatabase.instance.deleteNote(note.id);
                  if (context.mounted) context.pop();
                  break;
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              note.title,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Meta info
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  note.updatedAt.fullFormatted,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${note.wordCount} words · ${note.readingTimeSeconds.durationFormatted} read',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // Tags
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _tags
                    .map((tag) => Chip(
                          label: Text(tag.name,
                              style: textTheme.labelSmall),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
            const Divider(height: 32),
            // Content
            SelectableText(
              note.content.isEmpty ? 'No content' : note.content,
              style: textTheme.bodyLarge?.copyWith(height: 1.7),
            ),
            // Forward Links
            if (_forwardLinks.isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                'Links',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ..._forwardLinks.map((link) => ListTile(
                    leading: Icon(Icons.link, color: colorScheme.primary),
                    title: Text(link.title),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push('/notes/detail/${link.id}'),
                  )),
            ],
            // Backlinks
            if (_backlinks.isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                'Backlinks',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ..._backlinks.map((link) => ListTile(
                    leading:
                        Icon(Icons.arrow_back, color: colorScheme.tertiary),
                    title: Text(link.title),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push('/notes/detail/${link.id}'),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

