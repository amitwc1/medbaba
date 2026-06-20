import 'package:drift/drift.dart';

// ─────────────────────────── USERS TABLE ───────────────────────────
class Users extends Table {
  TextColumn get firebaseUid => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get avatarPath => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {firebaseUid};
}

// ─────────────────────────── FOLDERS TABLE ───────────────────────────
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get parentId => text().nullable().references(Folders, #id)();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get color => text().withDefault(const Constant(''))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))(); // pending, syncing, synced, failed
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── NOTES TABLE ───────────────────────────
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('Untitled'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get plainText => text().withDefault(const Constant(''))();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get wordCount => integer().withDefault(const Constant(0))();
  IntColumn get readingTimeSeconds => integer().withDefault(const Constant(0))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── TAGS TABLE ───────────────────────────
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 50).unique()();
  TextColumn get color => text().withDefault(const Constant('#6750A4'))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── NOTE_TAGS TABLE ───────────────────────────
class NoteTags extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {noteId, tagId}
      ];
}

// ─────────────────────────── NOTE_LINKS TABLE ───────────────────────────
class NoteLinks extends Table {
  TextColumn get id => text()();
  @ReferenceName('sourceLinks')
  TextColumn get sourceNoteId => text().references(Notes, #id)();
  @ReferenceName('targetLinks')
  TextColumn get targetNoteId => text().references(Notes, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {sourceNoteId, targetNoteId}
      ];
}

// ─────────────────────────── DECKS TABLE ───────────────────────────
class Decks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get parentDeckId => text().nullable().references(Decks, #id)();
  BoolColumn get isPublic => boolean().withDefault(const Constant(false))();
  TextColumn get color => text().withDefault(const Constant('#6750A4'))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── FLASH_CARDS TABLE ───────────────────────────
class FlashCards extends Table {
  TextColumn get id => text()();
  TextColumn get deckId => text().references(Decks, #id)();
  TextColumn get front => text()();
  TextColumn get back => text()();
  TextColumn get cardType =>
      text().withDefault(const Constant('basic'))(); // basic, reverse, cloze, image_occlusion, mcq, true_false
  RealColumn get difficulty => real().withDefault(const Constant(0.0))();
  RealColumn get stability => real().withDefault(const Constant(0.0))();
  RealColumn get retrievability => real().withDefault(const Constant(0.0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get interval => integer().withDefault(const Constant(0))();
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  TextColumn get state =>
      text().withDefault(const Constant('new'))(); // new, learning, review, relearning
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  BoolColumn get isDifficult => boolean().withDefault(const Constant(false))();
  TextColumn get tags => text().withDefault(const Constant(''))(); // comma-separated
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get step => integer().nullable()();
  DateTimeColumn get lastReview => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── REVIEW_HISTORY TABLE ───────────────────────────
class ReviewHistory extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text().references(FlashCards, #id)();
  IntColumn get rating => integer()(); // 1=Again, 2=Hard, 3=Good, 4=Easy
  IntColumn get timeTakenMs => integer().withDefault(const Constant(0))();
  RealColumn get scheduledDays => real().withDefault(const Constant(0.0))();
  RealColumn get elapsedDays => real().withDefault(const Constant(0.0))();
  TextColumn get state => text().withDefault(const Constant(''))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reviewedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get nextReviewDate => dateTime().nullable()();
  IntColumn get responseTime => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── ATTACHMENTS TABLE ───────────────────────────
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── DAILY_NOTES TABLE ───────────────────────────
class DailyNotes extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime().unique()();
  TextColumn get tasks => text().withDefault(const Constant(''))();
  TextColumn get meetings => text().withDefault(const Constant(''))();
  TextColumn get learnings => text().withDefault(const Constant(''))();
  TextColumn get reflections => text().withDefault(const Constant(''))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── STUDY_SESSIONS TABLE ───────────────────────────
class StudySessions extends Table {
  TextColumn get id => text()();
  TextColumn get deckId => text().references(Decks, #id)();
  TextColumn get userId => text().nullable()();
  TextColumn get mode =>
      text().withDefault(const Constant('review'))(); // learn, review, cram, weak, random, custom
  IntColumn get cardsStudied => integer().withDefault(const Constant(0))();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();

  // New fields for resuming, restarting, and review progress
  IntColumn get currentCardIndex => integer().withDefault(const Constant(0))();
  IntColumn get cardsReviewed => integer().withDefault(const Constant(0))();
  IntColumn get totalCards => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get cardIds => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── SYNC_QUEUE TABLE ───────────────────────────
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()();
  TextColumn get recordId => text()();
  TextColumn get operation => text()(); // create, update, delete
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────────────────────── SEARCH_HISTORY TABLE ───────────────────────────
class SearchHistory extends Table {
  TextColumn get id => text()();
  TextColumn get query => text()();
  TextColumn get type => text().withDefault(const Constant('all'))(); // all, notes, decks, cards, tags
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── DRAWING_NOTES TABLE ───────────────────────────
class DrawingNotes extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().nullable().references(Notes, #id)();
  TextColumn get title => text().withDefault(const Constant('Handwritten Note'))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── DRAWING_PAGES TABLE ───────────────────────────
class DrawingPages extends Table {
  TextColumn get id => text()();
  TextColumn get drawingNoteId => text().references(DrawingNotes, #id)();
  IntColumn get pageNumber => integer().withDefault(const Constant(1))();
  TextColumn get backgroundType => text().withDefault(const Constant('blank'))(); // blank, ruled, grid
  TextColumn get pdfPath => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────── DRAWING_STROKES TABLE ───────────────────────────
class DrawingStrokes extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(DrawingPages, #id)();
  TextColumn get pointsJson => text()();
  TextColumn get pressureJson => text().nullable()();
  TextColumn get tiltJson => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#000000'))();
  RealColumn get thickness => real().withDefault(const Constant(2.0))();
  RealColumn get opacity => real().withDefault(const Constant(1.0))();
  TextColumn get toolType => text().withDefault(const Constant('pen'))(); // pen, pencil, highlighter, marker, eraser, lasso
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
