import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/utils/result.dart';
import '../services/gemini_service.dart';
import 'ai_settings_repository.dart';

/// Repository that handles AI settings database updates and coordinates secure API key extraction for AI feature requests.
class AiRepository {
  final SecureStorageService _secureStorage;
  final GeminiService _geminiService;
  final AiSettingsRepository _settingsRepository;

  static const _apiKeyStorageKey = 'gemini_api_key_secure';

  AiRepository({
    required SecureStorageService secureStorage,
    required GeminiService geminiService,
    required AiSettingsRepository settingsRepository,
  })  : _secureStorage = secureStorage,
        _geminiService = geminiService,
        _settingsRepository = settingsRepository;

  // ────────────────────────── API KEY MANAGEMENT ──────────────────────────

  /// Saves the Gemini API key locally in secure storage.
  Future<void> saveApiKey(String apiKey) async {
    await _secureStorage.write(_apiKeyStorageKey, apiKey);
  }

  /// Reads the Gemini API key from secure storage.
  Future<String?> getApiKey() async {
    return await _secureStorage.read(_apiKeyStorageKey);
  }

  /// Deletes the Gemini API key from secure storage.
  Future<void> deleteApiKey() async {
    await _secureStorage.delete(_apiKeyStorageKey);
  }

  /// Checks if the provided API key is valid using the Gemini service.
  Future<Result<bool>> validateApiKey(String apiKey, String model) async {
    return await _geminiService.validateApiKey(apiKey, model);
  }

  // ────────────────────────── AI CORE FEATURES ──────────────────────────

  /// Generates a structured response with query classification and quality checks.
  Future<Result<AiResponse>> generateAiResponse({
    required String query,
    String? contextText,
    List<Map<String, String>>? chatHistory,
  }) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.generateResponse(
      apiKey: apiKey,
      modelName: model,
      query: query,
      contextText: contextText,
      chatHistory: chatHistory,
    );
  }

  /// Summarizes the text content.
  Future<Result<String>> generateSummary(String text) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.generateSummary(apiKey, model, text);
  }

  /// Generates a list of flashcards from the text content.
  Future<Result<String>> generateFlashcards(String text) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.generateFlashcards(apiKey, model, text);
  }

  /// Generates a multiple-choice quiz from the text content.
  Future<Result<String>> generateQuiz(String text) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.generateQuiz(apiKey, model, text);
  }

  /// Explains a concept or topic simply.
  Future<Result<String>> explainConcept(String concept) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.explainConcept(apiKey, model, concept);
  }

  /// Generates a structured study plan for a topic.
  Future<Result<String>> generateStudyPlan(String topic) async {
    final keyResult = await _getApiKeyAndModel();
    if (!keyResult.isSuccess) {
      return Result.failure(keyResult.error!);
    }
    final (apiKey, model) = keyResult.data!;
    return await _geminiService.generateStudyPlan(apiKey, model, topic);
  }

  // ────────────────────────── PRIVATE HELPERS ──────────────────────────

  /// Fetches the secure API key and configured model if AI features are enabled.
  Future<Result<(String, String)>> _getApiKeyAndModel() async {
    final settings = _settingsRepository.loadSettings();
    if (!settings.isEnabled) {
      return Result.failure('AI features are disabled in Settings. Please enable them first.');
    }
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return Result.failure('Add your Gemini API key in Settings to use AI features.');
    }
    return Result.success((apiKey, settings.model));
  }
}
