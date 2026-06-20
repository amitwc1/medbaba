import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/extensions.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  const NoteEditorScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;
  bool _hasChanges = false;
  Note? _existingNote;

  @override
  void initState() {
    super.initState();
    if (widget.noteId != null) {
      _loadNote();
    }
    _titleController.addListener(() => _hasChanges = true);
    _contentController.addListener(() => _hasChanges = true);
  }

  Future<void> _loadNote() async {
    setState(() => _isLoading = true);
    final note = await AppDatabase.instance.getNoteById(widget.noteId!);
    if (note != null && mounted) {
      setState(() {
        _existingNote = note;
        _titleController.text = note.title;
        _contentController.text = note.content;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note is empty')),
      );
      return;
    }

    final plainText = content.stripMarkdown;
    final wordCount = plainText.wordCount;
    final readingTime = plainText.readingTimeSeconds;
    final wikiLinks = content.wikiLinks;

    if (_existingNote != null) {
      await AppDatabase.instance.updateNote(
        NotesCompanion(
          id: drift.Value(_existingNote!.id),
          title: drift.Value(title.isEmpty ? 'Untitled' : title),
          content: drift.Value(content),
          plainText: drift.Value(plainText),
          wordCount: drift.Value(wordCount),
          readingTimeSeconds: drift.Value(readingTime),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      // Update wiki links
      await _updateWikiLinks(_existingNote!.id, wikiLinks);
    } else {
      final noteId = const Uuid().v4();
      await AppDatabase.instance.createNote(
        NotesCompanion.insert(
          id: noteId,
          title: drift.Value(title.isEmpty ? 'Untitled' : title),
          content: drift.Value(content),
          plainText: drift.Value(plainText),
          wordCount: drift.Value(wordCount),
          readingTimeSeconds: drift.Value(readingTime),
        ),
      );
      await _updateWikiLinks(noteId, wikiLinks);
    }

    if (mounted) {
      _hasChanges = false;
      context.pop();
    }
  }

  Future<void> _updateWikiLinks(String sourceNoteId, List<String> wikiLinks) async {
    // Find matching notes for each wiki link
    final targetIds = <String>[];
    for (final linkTitle in wikiLinks) {
      // Search for existing note with that title
      final db = AppDatabase.instance;
      final allNotes = await db.select(db.notes).get();
      final match = allNotes.where(
        (n) => n.title.toLowerCase() == linkTitle.toLowerCase(),
      );
      if (match.isNotEmpty) {
        targetIds.add(match.first.id);
      } else {
        // Auto-create note for the link
        final newId = const Uuid().v4();
        await db.createNote(
          NotesCompanion.insert(
            id: newId,
            title: drift.Value(linkTitle),
          ),
        );
        targetIds.add(newId);
      }
    }
    await AppDatabase.instance.setNoteLinks(sourceNoteId, targetIds);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final content = _contentController.text;
    final wordCount = content.trim().isEmpty ? 0 : content.wordCount;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && _hasChanges) {
          final save = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('Do you want to save your changes?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (save == true) {
            await _saveNote();
          } else if (context.mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.noteId != null ? 'Edit Note' : 'New Note'),
          actions: [
            // Word count
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '$wordCount words',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'AI Assist',
              onPressed: () {
                // TODO: AI features
              },
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveNote,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    TextField(
                      controller: _titleController,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Note title...',
                        hintStyle: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const Divider(height: 24),
                    // Toolbar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolbarButton(
                            icon: Icons.format_bold,
                            onTap: () => _insertMarkdown('**', '**'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_italic,
                            onTap: () => _insertMarkdown('*', '*'),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_underlined,
                            onTap: () => _insertMarkdown('<u>', '</u>'),
                          ),
                          _ToolbarButton(
                            icon: Icons.strikethrough_s,
                            onTap: () => _insertMarkdown('~~', '~~'),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 1, height: 24, color: colorScheme.outlineVariant),
                          const SizedBox(width: 8),
                          _ToolbarButton(
                            icon: Icons.title,
                            onTap: () => _insertPrefix('# '),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_bulleted,
                            onTap: () => _insertPrefix('- '),
                          ),
                          _ToolbarButton(
                            icon: Icons.format_list_numbered,
                            onTap: () => _insertPrefix('1. '),
                          ),
                          _ToolbarButton(
                            icon: Icons.checklist,
                            onTap: () => _insertPrefix('- [ ] '),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 1, height: 24, color: colorScheme.outlineVariant),
                          const SizedBox(width: 8),
                          _ToolbarButton(
                            icon: Icons.code,
                            onTap: () => _insertMarkdown('`', '`'),
                          ),
                          _ToolbarButton(
                            icon: Icons.data_object,
                            onTap: () => _insertMarkdown('```\n', '\n```'),
                          ),
                          _ToolbarButton(
                            icon: Icons.link,
                            onTap: () => _insertMarkdown('[[', ']]'),
                            tooltip: 'Wiki Link',
                          ),
                          _ToolbarButton(
                            icon: Icons.image_outlined,
                            onTap: () {
                              // TODO: Image picker
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Content editor
                    TextField(
                      controller: _contentController,
                      style: textTheme.bodyLarge?.copyWith(height: 1.6),
                      decoration: InputDecoration(
                        hintText: 'Start writing...\n\nUse [[Note Name]] to link notes\nUse # for headings\nUse - for lists',
                        hintStyle: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          height: 1.6,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: null,
                      minLines: 20,
                      keyboardType: TextInputType.multiline,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final selectedText = selection.isValid
        ? text.substring(selection.start, selection.end)
        : '';

    final newText = '$prefix$selectedText$suffix';
    _contentController.text = text.replaceRange(
      selection.isValid ? selection.start : text.length,
      selection.isValid ? selection.end : text.length,
      newText,
    );

    // Move cursor
    final newOffset = (selection.isValid ? selection.start : text.length) +
        prefix.length +
        selectedText.length;
    _contentController.selection =
        TextSelection.collapsed(offset: newOffset);
  }

  void _insertPrefix(String prefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final insertAt = selection.isValid ? selection.start : text.length;

    // Find start of current line
    int lineStart = insertAt;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    _contentController.text =
        text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _contentController.selection =
        TextSelection.collapsed(offset: insertAt + prefix.length);
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
