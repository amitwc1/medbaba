import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mind_vault/core/services/secure_storage_service.dart';
import 'package:mind_vault/features/ai/domain/models/ai_settings.dart';
import 'package:mind_vault/features/ai/data/repositories/ai_settings_repository.dart';
import 'package:mind_vault/features/ai/data/repositories/ai_repository.dart';
import 'package:mind_vault/features/ai/data/services/gemini_service.dart';

// ────────────────────────── FAKE SECURE STORAGE ──────────────────────────

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.clear();
  }
}

// ────────────────────────── TEST SUITE ──────────────────────────

void main() {
  group('SecureStorageService Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService secureStorage;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      secureStorage = SecureStorageService(storage: fakeStorage);
    });

    test('Should write and read key successfully', () async {
      await secureStorage.write('api_key', 'AIzaSyTest');
      final val = await secureStorage.read('api_key');
      expect(val, 'AIzaSyTest');
    });

    test('Should delete key successfully', () async {
      await secureStorage.write('api_key', 'AIzaSyTest');
      await secureStorage.delete('api_key');
      final val = await secureStorage.read('api_key');
      expect(val, null);
    });

    test('Should clear all keys successfully', () async {
      await secureStorage.write('key1', 'val1');
      await secureStorage.write('key2', 'val2');
      await secureStorage.clear();

      expect(await secureStorage.read('key1'), null);
      expect(await secureStorage.read('key2'), null);
    });
  });

  group('AiSettingsRepository Tests', () {
    late AiSettingsRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = AiSettingsRepository(prefs);
    });

    test('Should load default settings when none exist', () {
      final settings = repo.loadSettings();
      expect(settings.isEnabled, false);
      expect(settings.model, 'gemini-2.5-flash');
      expect(settings.apiKeyExists, false);
    });

    test('Should save and load updated settings successfully', () async {
      final updated = AiSettings(
        isEnabled: true,
        provider: 'gemini',
        model: 'gemini-2.5-pro',
        apiKeyExists: true,
        lastValidatedAt: DateTime(2026, 6, 20),
      );

      await repo.saveSettings(updated);
      final loaded = repo.loadSettings();

      expect(loaded.isEnabled, true);
      expect(loaded.model, 'gemini-2.5-pro');
      expect(loaded.apiKeyExists, true);
      expect(loaded.lastValidatedAt, DateTime(2026, 6, 20));
    });
  });

  group('AiRepository Tests', () {
    late AiRepository aiRepo;
    late SecureStorageService secureStorage;
    late AiSettingsRepository settingsRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = AiSettingsRepository(prefs);
      secureStorage = SecureStorageService(storage: FakeFlutterSecureStorage());

      aiRepo = AiRepository(
        secureStorage: secureStorage,
        geminiService: GeminiService(),
        settingsRepository: settingsRepo,
      );
    });

    test('Should return failure when AI features are disabled', () async {
      final result = await aiRepo.generateSummary('Hello world');
      expect(result.isSuccess, false);
      expect(result.error, contains('disabled in Settings'));
    });

    test('Should return failure when API key is missing even if enabled', () async {
      await settingsRepo.saveSettings(
        AiSettings.defaultSettings().copyWith(isEnabled: true),
      );

      final result = await aiRepo.generateSummary('Hello world');
      expect(result.isSuccess, false);
      expect(result.error, contains('Add your Gemini API key'));
    });

    test('Should successfully write and retrieve API key', () async {
      await aiRepo.saveApiKey('AIzaSyCustom');
      final key = await aiRepo.getApiKey();
      expect(key, 'AIzaSyCustom');

      await aiRepo.deleteApiKey();
      expect(await aiRepo.getApiKey(), null);
    });
  });

  group('AiResponseParser Tests', () {
    test('Should parse raw flashcards with Q: and A: correctly', () {
      const text = '''
Introductory text before flashcards.

Q: What is the primary goal of Anki?
A: To assist memorization using spaced repetition and active recall.

Q: What is the default learning algorithm of Anki?
A: SM-2, which computes ease factor.
''';

      final cards = AiResponseParser.parseFlashcards(text);
      expect(cards.length, 2);
      expect(cards[0].$1, 'What is the primary goal of Anki?');
      expect(cards[0].$2, 'To assist memorization using spaced repetition and active recall.');
      expect(cards[1].$1, 'What is the default learning algorithm of Anki?');
      expect(cards[1].$2, 'SM-2, which computes ease factor.');
    });

    test('Should parse MCQs from markdown output correctly', () {
      const text = '''
### Question 1: What is the time complexity of binary search?
- A) O(N)
- B) O(log N)
- C) O(1)
- D) O(N log N)

**Correct Answer:** B
**Explanation:** Binary search repeatedly divides the search interval in half, resulting in logarithmic time complexity.

### Question 2: Which database is used for offline-first local storage in MindVault?
- A) Firestore
- B) Isar
- C) Hive
- D) SQLite (Drift)

**Correct Answer:** D
**Explanation:** MindVault utilizes SQLite compiled via Drift as its local database engine.
''';

      final mcqs = AiResponseParser.parseMcqs(text);
      expect(mcqs.length, 2);
      expect(mcqs[0].question, 'What is the time complexity of binary search?');
      expect(mcqs[0].options[0], 'A) O(N)');
      expect(mcqs[0].options[1], 'B) O(log N)');
      expect(mcqs[0].correctAnswer, 'B');
      expect(mcqs[0].explanation, 'Binary search repeatedly divides the search interval in half, resulting in logarithmic time complexity.');

      expect(mcqs[1].question, 'Which database is used for offline-first local storage in MindVault?');
      expect(mcqs[1].options[3], 'D) SQLite (Drift)');
      expect(mcqs[1].correctAnswer, 'D');
      expect(mcqs[1].explanation, 'MindVault utilizes SQLite compiled via Drift as its local database engine.');
    });
  });
}
