/// Route path constants for GoRouter
class RouteConstants {
  RouteConstants._();

  // Auth
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String restore = '/restore';

  // Main Shell
  static const String dashboard = '/dashboard';
  static const String notes = '/notes';
  static const String decks = '/decks';
  static const String search = '/search';
  static const String settings = '/settings';
  static const String aiSettings = '/settings/ai';

  // Notes
  static const String noteEditor = '/notes/editor';
  static const String noteDetail = '/notes/detail/:id';
  static const String noteGraph = '/notes/graph';

  // Drawing
  static const String drawingEditor = '/drawing/editor';

  // Folders
  static const String folders = '/folders';
  static const String folderDetail = '/folders/:id';

  // Tags
  static const String tags = '/tags';
  static const String tagDetail = '/tags/:id';

  // Decks
  static const String deckDetail = '/decks/detail/:id';
  static const String deckEditor = '/decks/editor';

  // Flashcards
  static const String cardEditor = '/flashcards/editor';
  static const String cardDetail = '/flashcards/detail/:id';

  // Review
  static const String reviewSession = '/review/:deckId';
  static const String studyModes = '/study-modes/:deckId';

  // Daily Notes
  static const String dailyNotes = '/daily-notes';
  static const String dailyNoteDetail = '/daily-notes/:date';

  // AI
  static const String aiAssistant = '/ai';

  // Statistics
  static const String statistics = '/statistics';

  // Profile
  static const String profile = '/profile';

  // Named routes
  static const String dashboardName = 'dashboard';
  static const String notesName = 'notes';
  static const String decksName = 'decks';
  static const String searchName = 'search';
  static const String settingsName = 'settings';
}
