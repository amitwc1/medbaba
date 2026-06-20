import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'tables/all_tables.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Users,
  Folders,
  Notes,
  Tags,
  NoteTags,
  NoteLinks,
  Decks,
  FlashCards,
  ReviewHistory,
  Attachments,
  DailyNotes,
  StudySessions,
  SyncQueue,
  SearchHistory,
  DrawingNotes,
  DrawingPages,
  DrawingStrokes,
])
class AppDatabase extends _$AppDatabase {
  static VoidCallback? onDatabaseModified;

  AppDatabase._() : super(_openConnection());

  static AppDatabase? _instance;

  /// Singleton instance of the database
  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  /// Setter for testing
  static set instance(AppDatabase db) => _instance = db;

  /// For testing: create with a custom executor
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Future migrations: since we migrated to UUIDs, drop and recreate
          for (final entity in m.database.allSchemaEntities) {
            await m.drop(entity);
          }
          await m.createAll();
        },
        beforeOpen: (details) async {
          // Enable foreign keys
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mind_vault_db',
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
      ),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }

  // ─────────────────────────── NOTES DAO METHODS ───────────────────────────

  /// Get all notes (non-archived by default)
  Stream<List<Note>> watchAllNotes({bool includeArchived = false}) {
    final query = select(notes)..where((n) => n.isDeleted.equals(false));
    if (!includeArchived) {
      query.where((n) => n.isArchived.equals(false));
    }
    query.orderBy([
      (n) => OrderingTerm(expression: n.isPinned, mode: OrderingMode.desc),
      (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// Get a single note by ID
  Future<Note?> getNoteById(String id) {
    return (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  /// Create a new note
  Future<int> createNote(NotesCompanion note) async {
    final id = note.id.present ? note.id.value : const Uuid().v4();
    final companion = note.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: note.createdAt.present ? note.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(notes).insert(companion);
    final inserted = await getNoteById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'notes',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  /// Update a note
  Future<bool> updateNote(NotesCompanion note) async {
    final id = note.id.value;
    final companion = note.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(notes)..where((n) => n.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getNoteById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'notes',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  /// Delete a note
  Future<int> deleteNote(String id) async {
    final companion = NotesCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(notes)..where((n) => n.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'notes',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );

      final linkedDrawingNote = await (select(drawingNotes)
            ..where((dn) => dn.noteId.equals(id)))
          .getSingleOrNull();
      if (linkedDrawingNote != null) {
        await deleteDrawingNote(linkedDrawingNote.id);
      }
    }
    return rowsUpdated;
  }

  /// Search notes by title or content
  Stream<List<Note>> searchNotes(String query) {
    final pattern = '%$query%';
    return (select(notes)
          ..where((n) =>
              (n.title.like(pattern) | n.plainText.like(pattern)) &
              n.isDeleted.equals(false))
          ..orderBy([
            (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Get notes in a folder
  Stream<List<Note>> watchNotesInFolder(String folderId) {
    return (select(notes)
          ..where((n) =>
              n.folderId.equals(folderId) &
              n.isArchived.equals(false) &
              n.isDeleted.equals(false))
          ..orderBy([
            (n) => OrderingTerm(expression: n.isPinned, mode: OrderingMode.desc),
            (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Get favorite notes
  Stream<List<Note>> watchFavoriteNotes() {
    return (select(notes)
          ..where((n) =>
              n.isFavorite.equals(true) &
              n.isArchived.equals(false) &
              n.isDeleted.equals(false))
          ..orderBy([
            (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Get recent notes
  Future<List<Note>> getRecentNotes({int limit = 10}) {
    return (select(notes)
          ..where((n) => n.isArchived.equals(false) & n.isDeleted.equals(false))
          ..orderBy([
            (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// Count all notes
  Future<int> countNotes() async {
    final count = countAll();
    final query = selectOnly(notes)
      ..addColumns([count])
      ..where(notes.isDeleted.equals(false));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ─────────────────────────── FOLDERS DAO METHODS ───────────────────────────

  Stream<List<Folder>> watchAllFolders() {
    return (select(folders)
          ..where((f) => f.isArchived.equals(false) & f.isDeleted.equals(false))
          ..orderBy([
            (f) => OrderingTerm(expression: f.isPinned, mode: OrderingMode.desc),
            (f) => OrderingTerm(expression: f.sortOrder, mode: OrderingMode.asc),
            (f) => OrderingTerm(expression: f.name, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Stream<List<Folder>> watchRootFolders() {
    return (select(folders)
          ..where((f) =>
              f.parentId.isNull() &
              f.isArchived.equals(false) &
              f.isDeleted.equals(false))
          ..orderBy([
            (f) => OrderingTerm(expression: f.isPinned, mode: OrderingMode.desc),
            (f) => OrderingTerm(expression: f.sortOrder, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Stream<List<Folder>> watchSubFolders(String parentId) {
    return (select(folders)
          ..where((f) =>
              f.parentId.equals(parentId) &
              f.isArchived.equals(false) &
              f.isDeleted.equals(false))
          ..orderBy([
            (f) => OrderingTerm(expression: f.sortOrder, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<int> createFolder(FoldersCompanion folder) async {
    final id = folder.id.present ? folder.id.value : const Uuid().v4();
    final companion = folder.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: folder.createdAt.present ? folder.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(folders).insert(companion);
    final inserted = await getFolderById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'folders',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateFolder(FoldersCompanion folder) async {
    final id = folder.id.value;
    final companion = folder.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(folders)..where((f) => f.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getFolderById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'folders',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteFolder(String id) async {
    final companion = FoldersCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(folders)..where((f) => f.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'folders',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  Future<Folder?> getFolderById(String id) {
    return (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  // ─────────────────────────── TAGS DAO METHODS ───────────────────────────

  Stream<List<Tag>> watchAllTags() {
    return (select(tags)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)]))
        .watch();
  }

  Future<int> createTag(TagsCompanion tag) async {
    final id = tag.id.present ? tag.id.value : const Uuid().v4();
    final companion = tag.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: tag.createdAt.present ? tag.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(tags).insert(companion);
    final inserted = await getTagById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'tags',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<int> deleteTag(String id) async {
    final companion = TagsCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(tags)..where((t) => t.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'tags',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  Future<Tag?> getTagById(String id) {
    return (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<Tag>> getTagsForNote(String noteId) async {
    final query = select(tags).join([
      innerJoin(noteTags, noteTags.tagId.equalsExp(tags.id)),
    ])
      ..where(noteTags.noteId.equals(noteId) & tags.isDeleted.equals(false));
    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }

  Future<void> setTagsForNote(String noteId, List<String> tagIds) async {
    await (delete(noteTags)..where((nt) => nt.noteId.equals(noteId))).go();
    for (final tagId in tagIds) {
      await into(noteTags).insert(
        NoteTagsCompanion.insert(
          id: generateNoteTagId(noteId, tagId),
          noteId: noteId,
          tagId: tagId,
        ),
      );
    }
  }

  // Helper to generate a unique key for junction note tags
  static String generateNoteTagId(String noteId, String tagId) {
    return '${noteId}_${tagId}';
  }

  // ─────────────────────────── NOTE LINKS DAO METHODS ───────────────────────────

  Future<List<Note>> getBacklinks(String noteId) async {
    final query = select(notes).join([
      innerJoin(noteLinks, noteLinks.sourceNoteId.equalsExp(notes.id)),
    ])
      ..where(noteLinks.targetNoteId.equals(noteId) & notes.isDeleted.equals(false));
    final rows = await query.get();
    return rows.map((row) => row.readTable(notes)).toList();
  }

  Future<List<Note>> getForwardLinks(String noteId) async {
    final query = select(notes).join([
      innerJoin(noteLinks, noteLinks.targetNoteId.equalsExp(notes.id)),
    ])
      ..where(noteLinks.sourceNoteId.equals(noteId) & notes.isDeleted.equals(false));
    final rows = await query.get();
    return rows.map((row) => row.readTable(notes)).toList();
  }

  Future<void> setNoteLinks(String sourceNoteId, List<String> targetNoteIds) async {
    await (delete(noteLinks)..where((nl) => nl.sourceNoteId.equals(sourceNoteId))).go();
    for (final targetId in targetNoteIds) {
      await into(noteLinks).insert(
        NoteLinksCompanion.insert(
          id: '${sourceNoteId}_$targetId',
          sourceNoteId: sourceNoteId,
          targetNoteId: targetId,
        ),
      );
    }
  }

  Future<List<NoteLink>> getAllNoteLinks() {
    return select(noteLinks).get();
  }

  // ─────────────────────────── DECKS DAO METHODS ───────────────────────────

  Stream<List<Deck>> watchAllDecks() {
    return (select(decks)
          ..where((d) => d.isDeleted.equals(false))
          ..orderBy([
            (d) => OrderingTerm(expression: d.title, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Stream<List<Deck>> watchRootDecks() {
    return (select(decks)
          ..where((d) => d.parentDeckId.isNull() & d.isDeleted.equals(false))
          ..orderBy([
            (d) => OrderingTerm(expression: d.title, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<Deck?> getDeckById(String id) {
    return (select(decks)..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  Future<int> createDeck(DecksCompanion deck) async {
    final id = deck.id.present ? deck.id.value : const Uuid().v4();
    final companion = deck.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: deck.createdAt.present ? deck.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(decks).insert(companion);
    final inserted = await getDeckById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'decks',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateDeck(DecksCompanion deck) async {
    final id = deck.id.value;
    final companion = deck.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(decks)..where((d) => d.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getDeckById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'decks',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteDeck(String id) async {
    final companion = DecksCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(decks)..where((d) => d.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'decks',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  // ─────────────────────────── FLASHCARDS DAO METHODS ───────────────────────────

  Stream<List<FlashCard>> watchCardsInDeck(String deckId) {
    return (select(flashCards)
          ..where((c) =>
              c.deckId.equals(deckId) &
              c.isSuspended.equals(false) &
              c.isDeleted.equals(false))
          ..orderBy([
            (c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<List<FlashCard>> getCardsInDeck(String deckId) {
    return (select(flashCards)
          ..where((c) =>
              c.deckId.equals(deckId) &
              c.isSuspended.equals(false) &
              c.isDeleted.equals(false))
          ..orderBy([
            (c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<List<FlashCard>> getCardsByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(flashCards)
          ..where((c) => c.id.isIn(ids) & c.isDeleted.equals(false)))
        .get();
  }

  Future<List<FlashCard>> getNewCards(String deckId) {
    return (select(flashCards)
          ..where((c) =>
              c.deckId.equals(deckId) &
              c.isSuspended.equals(false) &
              c.isDeleted.equals(false) &
              (c.state.equals('new') | c.state.equals('learning'))))
        .get();
  }

  Future<List<FlashCard>> getDueCards(String deckId, {int? limit}) {
    final now = DateTime.now();
    final query = select(flashCards)
      ..where((c) =>
          c.deckId.equals(deckId) &
          c.isSuspended.equals(false) &
          c.isDeleted.equals(false) &
          (c.dueDate.isSmallerOrEqualValue(now) | c.dueDate.isNull()))
      ..orderBy([
        (c) => OrderingTerm(expression: c.dueDate, mode: OrderingMode.asc),
      ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<List<FlashCard>> getAllDueCards({int? limit}) {
    final now = DateTime.now();
    final query = select(flashCards)
      ..where((c) =>
          c.isSuspended.equals(false) &
          c.isDeleted.equals(false) &
          (c.dueDate.isSmallerOrEqualValue(now) | c.dueDate.isNull()))
      ..orderBy([
        (c) => OrderingTerm(expression: c.dueDate, mode: OrderingMode.asc),
      ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<FlashCard?> getCardById(String id) {
    return (select(flashCards)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<int> createCard(FlashCardsCompanion card) async {
    final id = card.id.present ? card.id.value : const Uuid().v4();
    final companion = card.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: card.createdAt.present ? card.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(flashCards).insert(companion);
    final inserted = await getCardById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'flashCards',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateCard(FlashCardsCompanion card) async {
    final id = card.id.value;
    final companion = card.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(flashCards)..where((c) => c.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getCardById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'flashCards',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteCard(String id) async {
    final companion = FlashCardsCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(flashCards)..where((c) => c.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'flashCards',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  Future<int> countCardsInDeck(String deckId) async {
    final count = countAll();
    final query = selectOnly(flashCards)
      ..addColumns([count])
      ..where(flashCards.deckId.equals(deckId) & flashCards.isDeleted.equals(false));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<int> countDueCardsInDeck(String deckId) async {
    final now = DateTime.now();
    final count = countAll();
    final query = selectOnly(flashCards)
      ..addColumns([count])
      ..where(flashCards.deckId.equals(deckId) &
          flashCards.isSuspended.equals(false) &
          flashCards.isDeleted.equals(false) &
          (flashCards.dueDate.isSmallerOrEqualValue(now) |
              flashCards.dueDate.isNull()));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<int> countAllCards() async {
    final count = countAll();
    final query = selectOnly(flashCards)
      ..addColumns([count])
      ..where(flashCards.isDeleted.equals(false));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ─────────────────────────── REVIEW HISTORY DAO METHODS ───────────────────────────

  Future<int> createReview(ReviewHistoryCompanion review) async {
    final id = review.id.present ? review.id.value : const Uuid().v4();
    final companion = review.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      isDeleted: const Value(false),
    );
    final rowId = await into(reviewHistory).insert(companion);
    final reviews = await getReviewsForCard(review.cardId.value);
    final inserted = reviews.firstWhere((r) => r.id == id);
    await _queueSync(
      targetTable: 'reviewHistory',
      recordId: id,
      operation: 'create',
      payload: jsonEncode(inserted.toJson()),
    );
    return rowId;
  }

  Future<List<ReviewHistoryData>> getReviewsForCard(String cardId) {
    return (select(reviewHistory)
          ..where((r) => r.cardId.equals(cardId) & r.isDeleted.equals(false))
          ..orderBy([
            (r) => OrderingTerm(expression: r.reviewedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<List<ReviewHistoryData>> getReviewsToday() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(reviewHistory)
          ..where((r) =>
              r.reviewedAt.isBiggerOrEqualValue(startOfDay) &
              r.reviewedAt.isSmallerThanValue(endOfDay) &
              r.isDeleted.equals(false)))
        .get();
  }

  Future<int> countReviewsToday() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final count = countAll();
    final query = selectOnly(reviewHistory)
      ..addColumns([count])
      ..where(reviewHistory.reviewedAt.isBiggerOrEqualValue(startOfDay) &
          reviewHistory.reviewedAt.isSmallerThanValue(endOfDay) &
          reviewHistory.isDeleted.equals(false));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ─────────────────────────── DAILY NOTES DAO METHODS ───────────────────────────

  Future<DailyNote?> getDailyNote(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    return (select(dailyNotes)
          ..where((dn) => dn.date.equals(startOfDay) & dn.isDeleted.equals(false)))
        .getSingleOrNull();
  }

  Future<int> createDailyNote(DailyNotesCompanion dailyNote) async {
    final id = dailyNote.id.present ? dailyNote.id.value : const Uuid().v4();
    final companion = dailyNote.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: dailyNote.createdAt.present ? dailyNote.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(dailyNotes).insert(companion);
    final inserted = await getDailyNote(companion.date.value);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'dailyNotes',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateDailyNote(DailyNotesCompanion dailyNote) async {
    final id = dailyNote.id.value;
    final companion = dailyNote.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(dailyNotes)..where((dn) => dn.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getDailyNote(dailyNote.date.value);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'dailyNotes',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Stream<List<DailyNote>> watchDailyNotes() {
    return (select(dailyNotes)
          ..where((dn) => dn.isDeleted.equals(false))
          ..orderBy([
            (dn) => OrderingTerm(expression: dn.date, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  // ─────────────────────────── STUDY SESSIONS DAO METHODS ───────────────────────────

  Future<int> createStudySession(StudySessionsCompanion session) async {
    final id = session.id.present ? session.id.value : const Uuid().v4();
    final companion = session.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      startedAt: session.startedAt.present ? session.startedAt : Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(studySessions).insert(companion);
    final inserted = await (select(studySessions)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (inserted != null) {
      await _queueSync(
        targetTable: 'studySessions',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateStudySession(StudySessionsCompanion session) async {
    final id = session.id.value;
    final companion = session.copyWith(
      syncStatus: const Value('pending'),
    );
    final updated = await (update(studySessions)..where((s) => s.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await (select(studySessions)..where((s) => s.id.equals(id))).getSingleOrNull();
      if (inserted != null) {
        await _queueSync(
          targetTable: 'studySessions',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<List<StudySession>> getStudySessionsToday() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(studySessions)
          ..where((s) =>
              s.startedAt.isBiggerOrEqualValue(startOfDay) &
              s.startedAt.isSmallerThanValue(endOfDay) &
              s.isDeleted.equals(false)))
        .get();
  }

  Future<StudySession?> getLatestIncompleteSession(String deckId, {String? mode}) {
    final query = select(studySessions)
      ..where((s) =>
          s.deckId.equals(deckId) &
          s.isCompleted.equals(true).not() &
          s.isDeleted.equals(false));
    if (mode != null) {
      query.where((s) => s.mode.equals(mode));
    }
    query.orderBy([
      (s) => OrderingTerm(expression: s.startedAt, mode: OrderingMode.desc),
    ]);
    query.limit(1);
    return query.getSingleOrNull();
  }

  Future<StudySession?> getLatestSessionForDeck(String deckId) {
    return (select(studySessions)
          ..where((s) => s.deckId.equals(deckId) & s.isDeleted.equals(false))
          ..orderBy([
            (s) => OrderingTerm(expression: s.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  // ─────────────────────────── ATTACHMENTS DAO METHODS ───────────────────────────

  Stream<List<Attachment>> watchAttachmentsForNote(String noteId) {
    return (select(attachments)
          ..where((a) => a.noteId.equals(noteId) & a.isDeleted.equals(false))
          ..orderBy([
            (a) => OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<int> createAttachment(AttachmentsCompanion attachment) async {
    final id = attachment.id.present ? attachment.id.value : const Uuid().v4();
    final companion = attachment.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: attachment.createdAt.present ? attachment.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(attachments).insert(companion);
    final inserted = await getAttachmentById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'attachments',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<int> deleteAttachment(String id) async {
    final companion = AttachmentsCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(attachments)..where((a) => a.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'attachments',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  Future<Attachment?> getAttachmentById(String id) {
    return (select(attachments)..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  // ─────────────────────────── SYNC QUEUE DAO METHODS ───────────────────────────

  Future<int> addToSyncQueue(SyncQueueCompanion entry) {
    return into(syncQueue).insert(entry);
  }

  Future<List<SyncQueueData>> getPendingSyncItems({int? limit}) {
    final query = select(syncQueue)
      ..where((s) => s.isSynced.equals(false))
      ..orderBy([
        (s) => OrderingTerm(expression: s.createdAt, mode: OrderingMode.asc),
      ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<void> markSynced(int id) {
    return (update(syncQueue)..where((s) => s.id.equals(id)))
        .write(const SyncQueueCompanion(isSynced: Value(true)));
  }

  Future<int> clearSyncedItems() {
    return (delete(syncQueue)..where((s) => s.isSynced.equals(true))).go();
  }

  // ─────────────────────────── SEARCH HISTORY DAO METHODS ───────────────────────────

  Future<int> addSearchHistory(String query, {String type = 'all'}) {
    return into(searchHistory).insert(
      SearchHistoryCompanion.insert(
        id: const Uuid().v4(),
        query: query,
        type: Value(type),
      ),
    );
  }

  Future<List<SearchHistoryData>> getSearchHistory({int limit = 20}) {
    return (select(searchHistory)
          ..where((s) => s.isDeleted.equals(false))
          ..orderBy([
            (s) => OrderingTerm(expression: s.searchedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> clearSearchHistory() {
    return delete(searchHistory).go();
  }

  // ─────────────────────────── USERS DAO METHODS ───────────────────────────

  Future<User?> getCurrentUser() {
    return (select(users)..limit(1)).getSingleOrNull();
  }

  Future<int> createUser(UsersCompanion user) {
    return into(users).insert(user);
  }

  Future<bool> updateUser(UsersCompanion user) {
    return (update(users)..where((u) => u.firebaseUid.equals(user.firebaseUid.value)))
        .write(user)
        .then((rows) => rows > 0);
  }

  Future<int> deleteAllUsers() {
    return delete(users).go();
  }

  Future<void> _queueSync({
    required String targetTable,
    required String recordId,
    required String operation,
    required String payload,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        targetTable: targetTable,
        recordId: recordId,
        operation: operation,
        payload: Value(payload),
        isSynced: const Value(false),
        createdAt: Value(DateTime.now()),
      ),
    );
    onDatabaseModified?.call();
  }

  // ─────────────────────────── DRAWING NOTES DAO METHODS ───────────────────────────

  Stream<List<DrawingNote>> watchAllDrawingNotes() {
    return (select(drawingNotes)
          ..where((dn) => dn.isDeleted.equals(false))
          ..orderBy([
            (dn) => OrderingTerm(expression: dn.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<DrawingNote?> getDrawingNoteById(String id) {
    return (select(drawingNotes)..where((dn) => dn.id.equals(id))).getSingleOrNull();
  }

  Future<int> createDrawingNote(DrawingNotesCompanion note) async {
    final id = note.id.present ? note.id.value : const Uuid().v4();
    final companion = note.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: note.createdAt.present ? note.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(drawingNotes).insert(companion);
    final inserted = await getDrawingNoteById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'drawingNotes',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateDrawingNote(DrawingNotesCompanion note) async {
    final id = note.id.value;
    final companion = note.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(drawingNotes)..where((dn) => dn.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getDrawingNoteById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'drawingNotes',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteDrawingNote(String id) async {
    final companion = DrawingNotesCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(drawingNotes)..where((dn) => dn.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'drawingNotes',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  // ─────────────────────────── DRAWING PAGES DAO METHODS ───────────────────────────

  Stream<List<DrawingPage>> watchPagesForDrawingNote(String drawingNoteId) {
    return (select(drawingPages)
          ..where((dp) => dp.drawingNoteId.equals(drawingNoteId) & dp.isDeleted.equals(false))
          ..orderBy([
            (dp) => OrderingTerm(expression: dp.pageNumber, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<List<DrawingPage>> getPagesForDrawingNote(String drawingNoteId) {
    return (select(drawingPages)
          ..where((dp) => dp.drawingNoteId.equals(drawingNoteId) & dp.isDeleted.equals(false))
          ..orderBy([
            (dp) => OrderingTerm(expression: dp.pageNumber, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<DrawingPage?> getDrawingPageById(String id) {
    return (select(drawingPages)..where((dp) => dp.id.equals(id))).getSingleOrNull();
  }

  Future<int> createDrawingPage(DrawingPagesCompanion page) async {
    final id = page.id.present ? page.id.value : const Uuid().v4();
    final companion = page.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: page.createdAt.present ? page.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(drawingPages).insert(companion);
    final inserted = await getDrawingPageById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'drawingPages',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateDrawingPage(DrawingPagesCompanion page) async {
    final id = page.id.value;
    final companion = page.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(drawingPages)..where((dp) => dp.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getDrawingPageById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'drawingPages',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteDrawingPage(String id) async {
    final companion = DrawingPagesCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(drawingPages)..where((dp) => dp.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'drawingPages',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }

  // ─────────────────────────── DRAWING STROKES DAO METHODS ───────────────────────────

  Stream<List<DrawingStroke>> watchStrokesForPage(String pageId) {
    return (select(drawingStrokes)
          ..where((ds) => ds.pageId.equals(pageId) & ds.isDeleted.equals(false))
          ..orderBy([
            (ds) => OrderingTerm(expression: ds.createdAt, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<List<DrawingStroke>> getStrokesForPage(String pageId) {
    return (select(drawingStrokes)
          ..where((ds) => ds.pageId.equals(pageId) & ds.isDeleted.equals(false))
          ..orderBy([
            (ds) => OrderingTerm(expression: ds.createdAt, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<DrawingStroke?> getDrawingStrokeById(String id) {
    return (select(drawingStrokes)..where((ds) => ds.id.equals(id))).getSingleOrNull();
  }

  Future<int> createDrawingStroke(DrawingStrokesCompanion stroke) async {
    final id = stroke.id.present ? stroke.id.value : const Uuid().v4();
    final companion = stroke.copyWith(
      id: Value(id),
      syncStatus: const Value('pending'),
      createdAt: stroke.createdAt.present ? stroke.createdAt : Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
    );
    final rowId = await into(drawingStrokes).insert(companion);
    final inserted = await getDrawingStrokeById(id);
    if (inserted != null) {
      await _queueSync(
        targetTable: 'drawingStrokes',
        recordId: id,
        operation: 'create',
        payload: jsonEncode(inserted.toJson()),
      );
    }
    return rowId;
  }

  Future<bool> updateDrawingStroke(DrawingStrokesCompanion stroke) async {
    final id = stroke.id.value;
    final companion = stroke.copyWith(
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final updated = await (update(drawingStrokes)..where((ds) => ds.id.equals(id)))
        .write(companion)
        .then((rows) => rows > 0);
    if (updated) {
      final inserted = await getDrawingStrokeById(id);
      if (inserted != null) {
        await _queueSync(
          targetTable: 'drawingStrokes',
          recordId: id,
          operation: 'update',
          payload: jsonEncode(inserted.toJson()),
        );
      }
    }
    return updated;
  }

  Future<int> deleteDrawingStroke(String id) async {
    final companion = DrawingStrokesCompanion(
      isDeleted: const Value(true),
      syncStatus: const Value('pending'),
      updatedAt: Value(DateTime.now()),
    );
    final rowsUpdated = await (update(drawingStrokes)..where((ds) => ds.id.equals(id))).write(companion);
    if (rowsUpdated > 0) {
      await _queueSync(
        targetTable: 'drawingStrokes',
        recordId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'isDeleted': true}),
      );
    }
    return rowsUpdated;
  }
}
