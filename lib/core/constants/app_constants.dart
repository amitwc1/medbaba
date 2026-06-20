/// App-wide constants for MindVault
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'MindVault';
  static const String appTagline = 'Think. Connect. Learn. Remember.';
  static const String appVersion = '1.0.0';

  // Database
  static const String databaseName = 'mind_vault_db';
  static const int databaseVersion = 1;

  // Spaced Repetition
  static const double defaultDesiredRetention = 0.9;
  static const int maxInterval = 36500; // 100 years in days
  static const double defaultEaseFactor = 2.5;
  static const int defaultInterval = 1;

  // Editor
  static const int maxTitleLength = 500;
  static const int maxTagLength = 50;
  static const int wordsPerMinute = 200;

  // Search
  static const int searchDebounceMs = 300;
  static const int maxSearchHistory = 20;
  static const int maxSearchResults = 50;

  // Sync
  static const int syncBatchSize = 50;
  static const int syncRetryDelaySeconds = 30;
  static const int maxSyncRetries = 3;

  // UI
  static const double cardBorderRadius = 16.0;
  static const double pagePadding = 16.0;
  static const double iconSize = 24.0;
  static const int animationDurationMs = 300;
  static const int splashDurationMs = 2500;

  // Onboarding
  static const String onboardingCompletedKey = 'onboarding_completed';
  static const String themeKey = 'theme_mode';
  static const String geminiApiKeyKey = 'gemini_api_key';

  // Notifications
  static const String dailyReminderChannelId = 'daily_reminder';
  static const String reviewReminderChannelId = 'review_reminder';
  static const String streakReminderChannelId = 'streak_reminder';

  // SharedPreferences keys
  static const String prefThemeMode = 'pref_theme_mode';
  static const String prefFontFamily = 'pref_font_family';
  static const String prefFontSize = 'pref_font_size';
  static const String prefAppLockEnabled = 'pref_app_lock_enabled';
  static const String prefBiometricsEnabled = 'pref_biometrics_enabled';
  static const String prefDailyReminder = 'pref_daily_reminder';
  static const String prefDailyReminderTime = 'pref_daily_reminder_time';
  static const String prefStudyStreak = 'pref_study_streak';
  static const String prefLastStudyDate = 'pref_last_study_date';
}
