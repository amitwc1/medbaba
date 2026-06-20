import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/extensions.dart';
import '../../../notes/presentation/screens/notes_list_screen.dart';
import '../../../decks/presentation/screens/deck_list_screen.dart';
import '../../data/services/gemini_service.dart';
import '../providers/ai_provider.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(aiStatusProvider);
    final chatState = ref.watch(aiChatProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Scroll listener on updates
    ref.listen<AiChatState>(aiChatProvider, (prev, next) {
      if (next.streamingText != null && next.streamingText!.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 50), _scrollToBottom);
      }
      if (prev?.messages.length != next.messages.length) {
        Future.delayed(const Duration(milliseconds: 50), _scrollToBottom);
      }
    });

    if (!status.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Assistant')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Bring Your Own Key AI',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'MindVault does not provide direct AI credits or API keys. To access Note Summarization, Flashcard Generation, AI Chat, and other features, get your own Gemini API key from Google AI Studio and configure it in settings.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: () {
                    context.push(RouteConstants.aiSettings);
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to AI Settings'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('MindVault AI'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Chat',
            onPressed: () {
              ref.read(aiChatProvider.notifier).clearChat();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'AI Settings',
            onPressed: () {
              context.push(RouteConstants.aiSettings);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Context settings panel
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ContextSelectorPanel(),
            ),
            
            // Chat history list
            Expanded(
              child: chatState.messages.isEmpty && (chatState.streamingText == null || chatState.streamingText!.isEmpty)
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: chatState.messages.length + (chatState.streamingText != null && chatState.streamingText!.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == chatState.messages.length) {
                          // Render the actively streaming text bubble
                          return _buildMessageBubble(
                            context,
                            ref,
                            ChatMessage(
                              id: 'streaming',
                              content: chatState.streamingText!,
                              isUser: false,
                              timestamp: DateTime.now(),
                            ),
                            isStreaming: true,
                          );
                        }
                        return _buildMessageBubble(context, ref, chatState.messages[index]);
                      },
                    ),
            ),

            if (chatState.error != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          chatState.error!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (chatState.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('AI is thinking & running Quality Checks...', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ),

            // Prompt Template Bar
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: PromptTemplatesRow(),
            ),

            // Input field bar
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              maxLines: 4,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText: 'Ask MindVault AI or type concept...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onSubmitted: (_) => _handleSend(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: chatState.isLoading ? null : _handleSend,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSend() {
    final queryText = _textController.text.trim();
    if (queryText.isEmpty) return;

    ref.read(aiChatProvider.notifier).sendMessage(queryText);
    _textController.clear();
    FocusScope.of(context).unfocus();
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.auto_awesome, size: 64, color: colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'How can I help you learn today?',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a note context above to summarize, generate study plans, flashcards, or ask custom questions.',
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    WidgetRef ref,
    ChatMessage message, {
    bool isStreaming = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Category tag if present
          if (!isUser && message.category != null && message.category!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message.category!,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            decoration: BoxDecoration(
              color: isUser
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: isUser
                ? Text(
                    message.content,
                    style: TextStyle(color: colorScheme.onPrimary, fontSize: 16),
                  )
                : MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        color: colorScheme.onSurface,
                        height: 1.5,
                      ),
                      h2: textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        height: 2.0,
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
                      tableBorder: TableBorder.all(color: colorScheme.outlineVariant),
                    ),
                  ),
          ),
          if (!isUser && !isStreaming) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: 'Copy Response',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Response copied to clipboard.')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    tooltip: 'Share Response',
                    onPressed: () {
                      Share.share(message.content);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    tooltip: 'Save to Notes',
                    onPressed: () => _saveAsNote(context, message.content),
                  ),
                  IconButton(
                    icon: const Icon(Icons.style_outlined, size: 18),
                    tooltip: 'Create Flashcards',
                    onPressed: () => _saveFlashcards(context, ref, message.content),
                  ),
                  IconButton(
                    icon: const Icon(Icons.quiz_outlined, size: 18),
                    tooltip: 'Create Quiz',
                    onPressed: () => _saveQuiz(context, ref, message.content),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined, size: 18),
                    tooltip: 'Regenerate',
                    onPressed: () {
                      ref.read(aiChatProvider.notifier).regenerateLastMessage();
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _saveAsNote(BuildContext context, String content) async {
    final title = 'AI Note - ${DateTime.now().toString().substring(0, 16)}';
    final id = const Uuid().v4();

    await AppDatabase.instance.createNote(NotesCompanion.insert(
      id: id,
      title: drift.Value(title),
      content: drift.Value(content),
      plainText: drift.Value(content.stripMarkdown),
    ));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved AI response as a new Note!')),
      );
    }
  }

  Future<void> _saveFlashcards(BuildContext context, WidgetRef ref, String content) async {
    final cards = AiResponseParser.parseFlashcards(content);
    if (cards.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Flashcards Found'),
          content: const Text(
            'This response does not contain raw flashcards (Q: and A: style). Would you like to ask the AI to generate flashcards from this text first?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Generate')),
          ],
        ),
      );
      if (confirm == true) {
        ref.read(aiChatProvider.notifier).sendMessage(
          'Generate high-quality flashcards using active recall principles based on your previous response.'
        );
      }
      return;
    }

    if (!context.mounted) return;
    final selectedDeckId = await _showDeckSelectorSheet(context, ref);
    if (selectedDeckId == null) return;

    final db = AppDatabase.instance;
    for (final card in cards) {
      await db.createCard(FlashCardsCompanion.insert(
        id: const Uuid().v4(),
        deckId: selectedDeckId,
        front: card.$1,
        back: card.$2,
        cardType: const drift.Value('basic'),
      ));
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully created ${cards.length} flashcards in the selected deck!')),
      );
    }
  }

  Future<void> _saveQuiz(BuildContext context, WidgetRef ref, String content) async {
    final mcqs = AiResponseParser.parseMcqs(content);
    if (mcqs.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Quiz Found'),
          content: const Text(
            'This response does not contain a raw quiz (Multiple Choice format). Would you like to ask the AI to generate a quiz from this text first?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Generate')),
          ],
        ),
      );
      if (confirm == true) {
        ref.read(aiChatProvider.notifier).sendMessage(
          'Generate MCQs with explanations and answers based on your previous response.'
        );
      }
      return;
    }

    if (!context.mounted) return;
    final selectedDeckId = await _showDeckSelectorSheet(context, ref);
    if (selectedDeckId == null) return;

    final db = AppDatabase.instance;
    for (final mcq in mcqs) {
      final backLines = <String>[];
      for (final opt in mcq.options) {
        final isCorrect = opt.trim().toUpperCase().startsWith(mcq.correctAnswer);
        String lineText = opt;
        if (isCorrect) {
          lineText = '* $lineText';
          if (mcq.explanation.isNotEmpty) {
            lineText += ' (Explanation: ${mcq.explanation})';
          }
        }
        backLines.add(lineText);
      }

      await db.createCard(FlashCardsCompanion.insert(
        id: const Uuid().v4(),
        deckId: selectedDeckId,
        front: mcq.question,
        back: backLines.join('\n'),
        cardType: const drift.Value('mcq'),
      ));
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully created ${mcqs.length} multiple choice questions in the selected deck!')),
      );
    }
  }

  Future<String?> _showDeckSelectorSheet(BuildContext context, WidgetRef ref) async {
    final decksAsync = ref.read(decksStreamProvider);
    final decks = decksAsync.value ?? [];
    String? selectedDeckId;
    final newDeckController = TextEditingController();

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select Destination Deck',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (decks.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Choose Existing Deck',
                        border: OutlineInputBorder(),
                      ),
                      items: decks.map((d) {
                        return DropdownMenuItem<String>(
                          value: d.id,
                          child: Text(d.title),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedDeckId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Center(child: Text('OR', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: newDeckController,
                    decoration: const InputDecoration(
                      labelText: 'Create New Deck Name',
                      hintText: 'Enter new deck name...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      if (val.trim().isNotEmpty) {
                        setState(() {
                          selectedDeckId = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      if (newDeckController.text.trim().isNotEmpty) {
                        final newId = const Uuid().v4();
                        await AppDatabase.instance.createDeck(DecksCompanion.insert(
                          id: newId,
                          title: newDeckController.text.trim(),
                          description: const drift.Value('AI Generated deck'),
                        ));
                        Navigator.pop(ctx, newId);
                      } else if (selectedDeckId != null) {
                        Navigator.pop(ctx, selectedDeckId);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select or create a deck.')),
                        );
                      }
                    },
                    child: const Text('Confirm'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }}

// ─────────────────────────── Sub Widgets ───────────────────────────

class ContextSelectorPanel extends ConsumerWidget {
  const ContextSelectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(aiChatProvider);
    final notesAsync = ref.watch(notesStreamProvider);
    final decksAsync = ref.watch(decksStreamProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.layers_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Context Settings',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
            ),
          ],
        ),
        subtitle: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (chatState.selectedNote != null)
                _buildContextBadge(context, 'Note: ${chatState.selectedNote!.title}', () {
                  ref.read(aiChatProvider.notifier).selectNote(null);
                }),
              if (chatState.selectedDeck != null)
                _buildContextBadge(context, 'Deck: ${chatState.selectedDeck!.title}', () {
                  ref.read(aiChatProvider.notifier).selectDeck(null);
                }),
              if (chatState.selectedText != null)
                _buildContextBadge(context, 'Text Context', () {
                  ref.read(aiChatProvider.notifier).selectText(null);
                }),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                notesAsync.when(
                  data: (notes) => DropdownButtonFormField<Note>(
                    value: chatState.selectedNote,
                    decoration: const InputDecoration(
                      labelText: 'Attach Note Context',
                      prefixIcon: Icon(Icons.description_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: notes.map((note) {
                      return DropdownMenuItem<Note>(
                        value: note,
                        child: Text(
                          note.title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      ref.read(aiChatProvider.notifier).selectNote(val);
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading notes: $e'),
                ),
                const SizedBox(height: 12),
                decksAsync.when(
                  data: (decks) => DropdownButtonFormField<Deck>(
                    value: chatState.selectedDeck,
                    decoration: const InputDecoration(
                      labelText: 'Attach Deck Context',
                      prefixIcon: Icon(Icons.style_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: decks.map((deck) {
                      return DropdownMenuItem<Deck>(
                        value: deck,
                        child: Text(
                          deck.title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      ref.read(aiChatProvider.notifier).selectDeck(val);
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading decks: $e'),
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Selected/Custom Text Context',
                    hintText: 'Paste custom text context here...',
                    prefixIcon: Icon(Icons.text_fields),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    ref.read(aiChatProvider.notifier).selectText(val.trim().isEmpty ? null : val);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextBadge(BuildContext context, String label, VoidCallback onClear) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close, size: 10),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: colorScheme.secondaryContainer,
      ),
    );
  }
}

class PromptTemplatesRow extends ConsumerWidget {
  const PromptTemplatesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final templates = [
      ('Summarize Note', 'Summarize this in simple language with key points.', Icons.summarize_outlined),
      ('Explain Simply', 'Explain this topic to a beginner using examples.', Icons.lightbulb_outline),
      ('Study Plan', 'Generate a step-by-step study plan.', Icons.calendar_month_outlined),
      ('Generate Cards', 'Generate high-quality flashcards using active recall principles.', Icons.style_outlined),
      ('Create Quiz', 'Generate MCQs with explanations and answers.', Icons.quiz_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: templates.map((t) {
          final label = t.$1;
          final prompt = t.$2;
          final icon = t.$3;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: Icon(icon, size: 16, color: colorScheme.primary),
              label: Text(label),
              onPressed: () {
                ref.read(aiChatProvider.notifier).sendMessage(prompt);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
