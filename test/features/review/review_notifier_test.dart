import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mind_vault/core/database/app_database.dart';
import 'package:mind_vault/features/review/presentation/providers/review_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(DatabaseConnection(NativeDatabase.memory()));
    AppDatabase.instance = db;
  });

  tearDown(() async {
    await db.close();
  });

  group('ReviewSessionNotifier FSRS Tests', () {
    test('startFreshSession initializes cards, session, and FSRS metrics', () async {
      final deckId = const Uuid().v4();
      
      // Create deck and flashcards
      await db.createDeck(DecksCompanion.insert(id: deckId, title: 'Flutter FSRS Deck'));
      await db.createCard(FlashCardsCompanion.insert(
        id: const Uuid().v4(),
        deckId: deckId,
        front: 'Front 1',
        back: 'Back 1',
        cardType: const Value('basic'),
      ));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reviewSessionProvider(ReviewSessionParams(deckId: deckId, mode: 'review')).notifier);
      await notifier.startFreshSession();

      final state = container.read(reviewSessionProvider(ReviewSessionParams(deckId: deckId, mode: 'review')));

      expect(state.isLoading, false);
      expect(state.cards.length, 1);
      expect(state.currentIndex, 0);
      expect(state.sessionId, isNotNull);
      expect(state.nextIntervals[3], isNotNull); // Good interval calculated
    });

    test('rateCurrentCard applies FSRS scheduling stability updates', () async {
      final deckId = const Uuid().v4();
      final cardId = const Uuid().v4();

      await db.createDeck(DecksCompanion.insert(id: deckId, title: 'Flutter FSRS Deck'));
      await db.createCard(FlashCardsCompanion.insert(
        id: cardId,
        deckId: deckId,
        front: 'MCQ Question',
        back: '*Option A\nOption B',
        cardType: const Value('mcq'),
      ));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reviewSessionProvider(ReviewSessionParams(deckId: deckId, mode: 'review')).notifier);
      await notifier.startFreshSession();

      // Rate card as Good (3)
      await notifier.rateCurrentCard(3);

      final updatedCard = await db.getCardById(cardId);
      expect(updatedCard, isNotNull);
      expect(updatedCard!.stability, isNot(0.0)); // Stability updated by FSRS
      expect(updatedCard.difficulty, isNot(0.0)); // Difficulty updated by FSRS
      expect(updatedCard.reps, 1);
    });

    test('resumeSession restores cardIds and index correctly', () async {
      final deckId = const Uuid().v4();
      final card1Id = const Uuid().v4();
      final sessionId = const Uuid().v4();

      await db.createDeck(DecksCompanion.insert(id: deckId, title: 'Flutter FSRS Deck'));
      await db.createCard(FlashCardsCompanion.insert(id: card1Id, deckId: deckId, front: 'F1', back: 'B1'));

      // Create incomplete study session
      await db.createStudySession(StudySessionsCompanion.insert(
        id: sessionId,
        deckId: deckId,
        mode: const Value('review'),
        cardsStudied: const Value(0),
        correctCount: const Value(0),
        durationSeconds: const Value(12),
        startedAt: Value(DateTime.now()),
        currentCardIndex: const Value(0),
        cardsReviewed: const Value(0),
        totalCards: const Value(1),
        isCompleted: const Value(false),
        cardIds: Value(card1Id),
      ));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reviewSessionProvider(ReviewSessionParams(deckId: deckId, mode: 'review')).notifier);
      
      final session = await db.getLatestIncompleteSession(deckId);
      expect(session, isNotNull);
      await notifier.resumeSession(session!);

      final state = container.read(reviewSessionProvider(ReviewSessionParams(deckId: deckId, mode: 'review')));

      expect(state.isLoading, false);
      expect(state.cards.length, 1);
      expect(state.cards[0].id, card1Id);
      expect(state.currentIndex, 0);
    });
  });
}
