import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../providers/review_providers.dart';
import '../widgets/flashcard_widget.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  final String deckId;
  final String mode;
  const ReviewSessionScreen({
    super.key,
    required this.deckId,
    this.mode = 'review',
  });

  @override
  ConsumerState<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  late PageController _pageController;
  bool _sessionChecked = false;
  
  // Timer State
  Timer? _timer;
  int _elapsedSeconds = 0;
  
  // Due Tomorrow State
  int _dueTomorrow = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkActiveSession();
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  ReviewSessionParams get _params => ReviewSessionParams(
        deckId: widget.deckId,
        mode: widget.mode,
      );

  Future<void> _checkActiveSession() async {
    if (_sessionChecked) return;
    _sessionChecked = true;

    final db = AppDatabase.instance;
    final session = await db.getLatestIncompleteSession(widget.deckId, mode: widget.mode);

    if (!mounted) return;

    if (session != null) {
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Continue where you left off?'),
          content: const Text('An incomplete study session was found for this deck. Would you like to resume it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false), // Restart
              child: const Text('Restart'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true), // Resume
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final notifier = ref.read(reviewSessionProvider(_params).notifier);
      if (resume == true) {
        await notifier.resumeSession(session);
        final updatedState = ref.read(reviewSessionProvider(_params));
        if (updatedState.currentIndex > 0 && updatedState.currentIndex < updatedState.cards.length) {
          _pageController.jumpToPage(updatedState.currentIndex);
        }
        setState(() {
          _elapsedSeconds = session.durationSeconds;
        });
      } else {
        await notifier.restartSession(sessionToCancel: session);
      }
    } else {
      await ref.read(reviewSessionProvider(_params).notifier).startFreshSession();
    }
  }

  String _formatTimer(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor();
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadDueTomorrowCount() async {
    final db = AppDatabase.instance;
    final cards = await db.getCardsInDeck(widget.deckId);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final count = cards.where((c) => c.dueDate != null && c.dueDate!.isBefore(tomorrow)).length;
    if (mounted) {
      setState(() {
        _dueTomorrow = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewSessionProvider(_params));
    final notifier = ref.read(reviewSessionProvider(_params).notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.sessionComplete || state.cards.isEmpty) {
      // Load tomorrow's due cards once completed
      _timer?.cancel();
      _loadDueTomorrowCount();
      return _buildSessionSummary(context, state);
    }

    final currentCard = state.cards[state.currentIndex];
    final isAnswerRevealed = state.revealedCardIds.contains(currentCard.id);

    // Remaining & Est Time Left
    final remaining = state.cards.length - state.currentIndex;
    final estMinutesLeft = (remaining * 30 / 60).ceil(); // Average 30 sec per card

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.deckName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              'Est. time left: $estMinutesLeft min',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await notifier.endSession();
            if (context.mounted) context.pop();
          },
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _formatTimer(_elapsedSeconds),
                    style: textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'End Session',
            onPressed: () async {
              final end = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('End Review?'),
                  content: const Text('Do you want to end this study session? Your progress will be saved.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('End'),
                    ),
                  ],
                ),
              );
              if (end == true) {
                await notifier.endSession();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Linear Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: state.cards.isNotEmpty
                      ? (state.currentIndex + 1) / state.cards.length
                      : 0,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
            ),

            // Jump to Card Link
            GestureDetector(
              onTap: () async {
                final targetIndex = await showDialog<int>(
                  context: context,
                  builder: (ctx) {
                    final controller = TextEditingController();
                    return AlertDialog(
                      title: const Text('Jump to Card'),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Enter card number (1-${state.cards.length})',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final val = int.tryParse(controller.text);
                            if (val != null && val >= 1 && val <= state.cards.length) {
                              Navigator.pop(ctx, val - 1);
                            }
                          },
                          child: const Text('Jump'),
                        ),
                      ],
                    );
                  },
                );
                if (targetIndex != null && targetIndex != state.currentIndex) {
                  _pageController.animateToPage(
                    targetIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Card ${state.currentIndex + 1} of ${state.cards.length} ($remaining left)',
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_road_rounded, size: 16, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
            
            // Flashcard Area
            Expanded(
              child: Row(
                children: [
                  // Previous Card Button
                  if (state.currentIndex > 0)
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 36),
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    )
                  else
                    const SizedBox(width: 48),

                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: state.cards.length,
                      onPageChanged: (index) {
                        notifier.setCurrentIndex(index);
                      },
                      itemBuilder: (context, index) {
                        final card = state.cards[index];
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: FlashcardWidget(
                            card: card,
                            deckName: state.deckName,
                            currentIndex: index,
                            totalCards: state.cards.length,
                            onFlip: () {
                              notifier.revealCurrentCard();
                            },
                          ),
                        );
                      },
                    ),
                  ),

                  // Next Card Button
                  if (state.currentIndex < state.cards.length - 1)
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 36),
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            // Tip
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Tip: Tap the card to flip back and forth',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),

            // Footer Control Panel with FSRS Intervals
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isAnswerRevealed
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'How well did you remember?',
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _RatingButton(
                                label: 'Again',
                                color: AppColors.reviewAgain,
                                description: state.nextIntervals[1] ?? '1m',
                                onTap: () => _rateAndAdvance(notifier, 1),
                              ),
                              const SizedBox(width: 8),
                              _RatingButton(
                                label: 'Hard',
                                color: AppColors.reviewHard,
                                description: state.nextIntervals[2] ?? '12h',
                                onTap: () => _rateAndAdvance(notifier, 2),
                              ),
                              const SizedBox(width: 8),
                              _RatingButton(
                                label: 'Good',
                                color: AppColors.reviewGood,
                                description: state.nextIntervals[3] ?? '4d',
                                onTap: () => _rateAndAdvance(notifier, 3),
                              ),
                              const SizedBox(width: 8),
                              _RatingButton(
                                label: 'Easy',
                                color: AppColors.reviewEasy,
                                description: state.nextIntervals[4] ?? '7d',
                                onTap: () => _rateAndAdvance(notifier, 4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () {
                            notifier.revealCurrentCard();
                          },
                          icon: const Icon(Icons.flip_to_back_rounded),
                          label: const Text('Show Answer & Rate'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rateAndAdvance(ReviewSessionNotifier notifier, int rating) async {
    final state = ref.read(reviewSessionProvider(_params));
    await notifier.rateCurrentCard(rating);

    if (state.currentIndex < state.cards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildSessionSummary(BuildContext context, ReviewSessionState state) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final durationSeconds = _elapsedSeconds;
    String timeStr;
    if (durationSeconds < 60) {
      timeStr = '$durationSeconds sec';
    } else {
      timeStr = '${(durationSeconds / 60).floor()} min ${durationSeconds % 60} sec';
    }

    final accuracy = state.totalReviewed > 0
        ? (state.correctCount / state.totalReviewed * 100).round()
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        leading: Container(),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.reviewGood.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  size: 80,
                  color: AppColors.reviewGood,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '🎉 Session Completed',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Great work! You have finished studying this deck.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              
              // Statistics Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _SummaryItem(value: '${state.totalReviewed}', label: 'Reviewed'),
                          Container(width: 1, height: 40, color: colorScheme.outlineVariant),
                          _SummaryItem(value: '$accuracy%', label: 'Accuracy'),
                          Container(width: 1, height: 40, color: colorScheme.outlineVariant),
                          _SummaryItem(value: timeStr, label: 'Study Time'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Retention Rate', style: textTheme.bodyMedium),
                          Text('$accuracy%', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cards Due Tomorrow', style: textTheme.bodyMedium),
                          Text('$_dueTomorrow', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.secondary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // Review Again
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    setState(() {
                      _elapsedSeconds = 0;
                      _sessionChecked = false;
                    });
                    _startTimer();
                    final notifier = ref.read(reviewSessionProvider(_params).notifier);
                    await notifier.startFreshSession();
                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(0);
                    }
                  },
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Review Again'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Restart Session
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _elapsedSeconds = 0;
                      _sessionChecked = false;
                    });
                    _startTimer();
                    final notifier = ref.read(reviewSessionProvider(_params).notifier);
                    await notifier.restartSession();
                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(0);
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Restart Session'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Back to Deck
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    context.pop();
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Back to Deck'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final Color color;
  final String description;
  final VoidCallback onTap;

  const _RatingButton({
    required this.label,
    required this.color,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: SizedBox(
        height: 64,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: BorderSide(color: color.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          value,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
