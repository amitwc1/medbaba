import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import '../../../../core/database/app_database.dart';

class ReviewSessionState {
  final List<FlashCard> cards;
  final String deckName;
  final int currentIndex;
  final Set<String> revealedCardIds;
  final Map<String, int> cardRatings;
  final bool isLoading;
  final bool sessionComplete;
  final int correctCount;
  final int totalReviewed;
  final DateTime? sessionStart;
  final String? sessionId;
  final Map<int, String> nextIntervals;

  const ReviewSessionState({
    required this.cards,
    required this.deckName,
    this.currentIndex = 0,
    required this.revealedCardIds,
    required this.cardRatings,
    this.isLoading = true,
    this.sessionComplete = false,
    this.correctCount = 0,
    this.totalReviewed = 0,
    this.sessionStart,
    this.sessionId,
    this.nextIntervals = const {},
  });

  ReviewSessionState copyWith({
    List<FlashCard>? cards,
    String? deckName,
    int? currentIndex,
    Set<String>? revealedCardIds,
    Map<String, int>? cardRatings,
    bool? isLoading,
    bool? sessionComplete,
    int? correctCount,
    int? totalReviewed,
    DateTime? sessionStart,
    String? sessionId,
    Map<int, String>? nextIntervals,
  }) {
    return ReviewSessionState(
      cards: cards ?? this.cards,
      deckName: deckName ?? this.deckName,
      currentIndex: currentIndex ?? this.currentIndex,
      revealedCardIds: revealedCardIds ?? this.revealedCardIds,
      cardRatings: cardRatings ?? this.cardRatings,
      isLoading: isLoading ?? this.isLoading,
      sessionComplete: sessionComplete ?? this.sessionComplete,
      correctCount: correctCount ?? this.correctCount,
      totalReviewed: totalReviewed ?? this.totalReviewed,
      sessionStart: sessionStart ?? this.sessionStart,
      sessionId: sessionId ?? this.sessionId,
      nextIntervals: nextIntervals ?? this.nextIntervals,
    );
  }
}

class ReviewSessionNotifier extends StateNotifier<ReviewSessionState> {
  final String deckId;
  final String mode;
  DateTime? _cardStartTime;

  ReviewSessionNotifier({
    required this.deckId,
    required this.mode,
  }) : super(const ReviewSessionState(
          cards: [],
          deckName: 'Loading...',
          revealedCardIds: {},
          cardRatings: {},
          isLoading: true,
        )) {
    _loadDeckName();
  }

  Future<void> _loadDeckName() async {
    final db = AppDatabase.instance;
    final deck = await db.getDeckById(deckId);
    if (deck != null) {
      state = state.copyWith(
        deckName: deck.title,
      );
    }
  }

  /// Start a completely fresh session.
  Future<void> startFreshSession() async {
    state = state.copyWith(isLoading: true);
    final db = AppDatabase.instance;
    final currentUser = await db.getCurrentUser();

    List<FlashCard> cards = [];
    if (mode == 'review') {
      cards = await db.getDueCards(deckId);
      if (cards.isEmpty) {
        cards = await db.getCardsInDeck(deckId);
      }
    } else if (mode == 'learn') {
      cards = await db.getNewCards(deckId);
      if (cards.isEmpty) {
        cards = await db.getCardsInDeck(deckId);
      }
    } else {
      cards = await db.getCardsInDeck(deckId);
    }

    final sessionId = const Uuid().v4();
    final cardIds = cards.map((c) => c.id).join(',');

    if (cards.isNotEmpty) {
      await db.createStudySession(StudySessionsCompanion.insert(
        id: sessionId,
        deckId: deckId,
        userId: Value(currentUser?.firebaseUid),
        mode: Value(mode),
        cardsStudied: const Value(0),
        correctCount: const Value(0),
        durationSeconds: const Value(0),
        startedAt: Value(DateTime.now()),
        currentCardIndex: const Value(0),
        cardsReviewed: const Value(0),
        totalCards: Value(cards.length),
        isCompleted: const Value(false),
        cardIds: Value(cardIds),
        syncStatus: const Value('pending'),
      ));
    }

    state = ReviewSessionState(
      cards: cards,
      deckName: state.deckName,
      currentIndex: 0,
      revealedCardIds: {},
      cardRatings: {},
      isLoading: false,
      sessionComplete: cards.isEmpty,
      correctCount: 0,
      totalReviewed: 0,
      sessionStart: DateTime.now(),
      sessionId: sessionId,
    );

    _cardStartTime = DateTime.now();
    _updateNextIntervals();
  }

  /// Resume an existing incomplete session.
  Future<void> resumeSession(StudySession session) async {
    state = state.copyWith(isLoading: true);
    final db = AppDatabase.instance;

    List<FlashCard> cards = [];
    if (session.cardIds.isNotEmpty) {
      final ids = session.cardIds.split(',').where((id) => id.isNotEmpty).toList();
      final fetchedCards = await db.getCardsByIds(ids);
      final Map<String, FlashCard> cardMap = {for (var c in fetchedCards) c.id: c};
      cards = ids.map((id) => cardMap[id]).whereType<FlashCard>().toList();
    }

    if (cards.isEmpty) {
      if (mode == 'review') {
        cards = await db.getDueCards(deckId);
        if (cards.isEmpty) {
          cards = await db.getCardsInDeck(deckId);
        }
      } else if (mode == 'learn') {
        cards = await db.getNewCards(deckId);
        if (cards.isEmpty) {
          cards = await db.getCardsInDeck(deckId);
        }
      } else {
        cards = await db.getCardsInDeck(deckId);
      }
    }

    state = ReviewSessionState(
      cards: cards,
      deckName: state.deckName,
      currentIndex: session.currentCardIndex,
      revealedCardIds: {},
      cardRatings: {},
      isLoading: false,
      sessionComplete: session.isCompleted || cards.isEmpty || session.currentCardIndex >= cards.length,
      correctCount: session.correctCount,
      totalReviewed: session.cardsReviewed,
      sessionStart: session.startedAt,
      sessionId: session.id,
    );

    _cardStartTime = DateTime.now();
    _updateNextIntervals();
  }

  /// Restart session.
  Future<void> restartSession({StudySession? sessionToCancel}) async {
    if (sessionToCancel != null) {
      final db = AppDatabase.instance;
      await db.updateStudySession(StudySessionsCompanion(
        id: Value(sessionToCancel.id),
        isCompleted: const Value(true),
        completedAt: Value(DateTime.now()),
        endedAt: Value(DateTime.now()),
      ));
    }
    await startFreshSession();
  }

  void revealCurrentCard() {
    if (state.currentIndex >= state.cards.length) return;
    final cardId = state.cards[state.currentIndex].id;
    final newRevealed = Set<String>.from(state.revealedCardIds)..add(cardId);
    state = state.copyWith(revealedCardIds: newRevealed);
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < state.cards.length) {
      state = state.copyWith(currentIndex: index);
      _cardStartTime = DateTime.now();
      _updateNextIntervals();

      if (state.sessionId != null) {
        AppDatabase.instance.updateStudySession(StudySessionsCompanion(
          id: Value(state.sessionId!),
          currentCardIndex: Value(index),
        ));
      }
    }
  }

  Future<void> rateCurrentCard(int rating) async {
    if (state.currentIndex >= state.cards.length) return;
    final card = state.cards[state.currentIndex];
    
    final newRatings = Map<String, int>.from(state.cardRatings)..[card.id] = rating;

    // FSRS Scheduler Integration
    final fsrsCard = _toFsrsCard(card);
    final scheduler = fsrs.Scheduler();
    
    fsrs.Rating fsrsRating;
    switch (rating) {
      case 1:
        fsrsRating = fsrs.Rating.again;
        break;
      case 2:
        fsrsRating = fsrs.Rating.hard;
        break;
      case 3:
        fsrsRating = fsrs.Rating.good;
        break;
      case 4:
      default:
        fsrsRating = fsrs.Rating.easy;
        break;
    }

    final responseTimeMs = _cardStartTime != null
        ? DateTime.now().difference(_cardStartTime!).inMilliseconds
        : 0;

    final result = scheduler.reviewCard(
      fsrsCard,
      fsrsRating,
      reviewDateTime: DateTime.now().toUtc(),
      reviewDuration: responseTimeMs,
    );

    final updatedFsrsCard = result.card;
    final log = result.reviewLog;

    String dbState;
    switch (updatedFsrsCard.state) {
      case fsrs.State.learning:
        dbState = 'learning';
        break;
      case fsrs.State.review:
        dbState = 'review';
        break;
      case fsrs.State.relearning:
        dbState = 'relearning';
        break;
    }

    final db = AppDatabase.instance;

    await db.updateCard(FlashCardsCompanion(
      id: Value(card.id),
      difficulty: Value(updatedFsrsCard.difficulty ?? 0.0),
      stability: Value(updatedFsrsCard.stability ?? 0.0),
      dueDate: Value(updatedFsrsCard.due.toLocal()),
      state: Value(dbState),
      step: Value(updatedFsrsCard.step),
      lastReview: Value(updatedFsrsCard.lastReview?.toLocal()),
      reps: Value(card.reps + 1),
      lapses: Value(rating == 1 ? card.lapses + 1 : card.lapses),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));

    await db.createReview(ReviewHistoryCompanion.insert(
      id: const Uuid().v4(),
      cardId: card.id,
      rating: rating,
      timeTakenMs: Value(responseTimeMs),
      scheduledDays: Value(updatedFsrsCard.stability ?? 0.0),
      reviewedAt: Value(DateTime.now()),
      nextReviewDate: Value(updatedFsrsCard.due.toLocal()),
      responseTime: Value(responseTimeMs),
      syncStatus: const Value('pending'),
    ));

    final correct = rating >= 3 ? 1 : 0;
    final total = state.totalReviewed + 1;
    final correctCount = state.correctCount + correct;

    final duration = state.sessionStart != null
        ? DateTime.now().difference(state.sessionStart!).inSeconds
        : 0;

    if (state.sessionId != null) {
      await db.updateStudySession(StudySessionsCompanion(
        id: Value(state.sessionId!),
        currentCardIndex: Value(state.currentIndex + 1),
        cardsReviewed: Value(total),
        correctCount: Value(correctCount),
        durationSeconds: Value(duration),
      ));
    }

    state = state.copyWith(
      cardRatings: newRatings,
      totalReviewed: total,
      correctCount: correctCount,
    );

    if (state.currentIndex >= state.cards.length - 1) {
      await endSession();
    }
  }

  Future<void> endSession() async {
    if (state.sessionStart == null || state.sessionComplete) return;

    final duration = DateTime.now().difference(state.sessionStart!).inSeconds;
    final db = AppDatabase.instance;

    if (state.sessionId != null) {
      await db.updateStudySession(StudySessionsCompanion(
        id: Value(state.sessionId!),
        cardsReviewed: Value(state.totalReviewed),
        correctCount: Value(state.correctCount),
        durationSeconds: Value(duration),
        isCompleted: const Value(true),
        completedAt: Value(DateTime.now()),
        endedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));
    }

    state = state.copyWith(sessionComplete: true);
  }

  void _updateNextIntervals() {
    if (state.cards.isEmpty || state.currentIndex >= state.cards.length) {
      state = state.copyWith(nextIntervals: const {});
      return;
    }
    final card = state.cards[state.currentIndex];
    state = state.copyWith(nextIntervals: _calculateNextIntervals(card));
  }

  Map<int, String> _calculateNextIntervals(FlashCard card) {
    final fsrsCard = _toFsrsCard(card);
    final scheduler = fsrs.Scheduler();

    final again = scheduler.reviewCard(fsrsCard, fsrs.Rating.again);
    final hard = scheduler.reviewCard(fsrsCard, fsrs.Rating.hard);
    final good = scheduler.reviewCard(fsrsCard, fsrs.Rating.good);
    final easy = scheduler.reviewCard(fsrsCard, fsrs.Rating.easy);

    return {
      1: _formatInterval(again.card.due),
      2: _formatInterval(hard.card.due),
      3: _formatInterval(good.card.due),
      4: _formatInterval(easy.card.due),
    };
  }

  String _formatInterval(DateTime due) {
    final diff = due.difference(DateTime.now().toUtc());
    if (diff.inDays >= 1) {
      return '${diff.inDays}d';
    } else if (diff.inHours >= 1) {
      return '${diff.inHours}h';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes}m';
    } else {
      return '1m';
    }
  }

  fsrs.Card _toFsrsCard(FlashCard card) {
    fsrs.State state;
    switch (card.state) {
      case 'learning':
        state = fsrs.State.learning;
        break;
      case 'review':
        state = fsrs.State.review;
        break;
      case 'relearning':
        state = fsrs.State.relearning;
        break;
      case 'new':
      default:
        state = fsrs.State.learning;
        break;
    }

    final stability = (card.stability == 0.0) ? null : card.stability;
    final difficulty = (card.difficulty == 0.0) ? null : card.difficulty;

    return fsrs.Card(
      cardId: card.id.hashCode,
      state: state,
      step: card.step,
      stability: stability,
      difficulty: difficulty,
      due: card.dueDate?.toUtc() ?? DateTime.now().toUtc(),
      lastReview: card.lastReview?.toUtc(),
    );
  }
}

// Param class for family provider
class ReviewSessionParams {
  final String deckId;
  final String mode;

  const ReviewSessionParams({required this.deckId, required this.mode});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewSessionParams &&
          runtimeType == other.runtimeType &&
          deckId == other.deckId &&
          mode == other.mode;

  @override
  int get hashCode => deckId.hashCode ^ mode.hashCode;
}

final reviewSessionProvider = StateNotifierProvider.family<
    ReviewSessionNotifier, ReviewSessionState, ReviewSessionParams>((ref, params) {
  return ReviewSessionNotifier(deckId: params.deckId, mode: params.mode);
});
