import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/utils/result.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/ai_repository.dart';
import '../../data/repositories/ai_settings_repository.dart';
import '../../data/services/gemini_service.dart';
import '../../domain/models/ai_settings.dart';

// ────────────────────────── Chat Message Model ──────────────────────────

class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? category;
  final String? complexity;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.category,
    this.complexity,
  });
}

// ────────────────────────── Chat State Model ──────────────────────────

class AiChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? streamingText;
  final Note? selectedNote;
  final Deck? selectedDeck;
  final String? selectedText;
  final String? error;

  AiChatState({
    required this.messages,
    required this.isLoading,
    this.streamingText,
    this.selectedNote,
    this.selectedDeck,
    this.selectedText,
    this.error,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? streamingText,
    Note? selectedNote,
    bool clearNote = false,
    Deck? selectedDeck,
    bool clearDeck = false,
    String? selectedText,
    bool clearText = false,
    String? error,
    bool clearError = false,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      streamingText: streamingText ?? this.streamingText,
      selectedNote: clearNote ? null : (selectedNote ?? this.selectedNote),
      selectedDeck: clearDeck ? null : (selectedDeck ?? this.selectedDeck),
      selectedText: clearText ? null : (selectedText ?? this.selectedText),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ────────────────────────── CORE PROVIDERS ──────────────────────────

/// Provides the Secure Storage Service instance.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Provides the Gemini Service instance.
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

/// Provides the AI Settings Repository instance.
final aiSettingsRepositoryProvider = Provider<AiSettingsRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AiSettingsRepository(prefs);
});

/// Provides the AI Repository instance.
final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(
    secureStorage: ref.watch(secureStorageServiceProvider),
    geminiService: ref.watch(geminiServiceProvider),
    settingsRepository: ref.watch(aiSettingsRepositoryProvider),
  );
});

// ────────────────────────── STATE NOTIFIERS & PROVIDERS ──────────────────────────

/// StateNotifier that manages in-memory cached API key and updates secure storage.
class ApiKeyNotifier extends StateNotifier<String?> {
  final AiRepository _aiRepository;

  ApiKeyNotifier(this._aiRepository) : super(null) {
    _loadKey();
  }

  /// Loads the API key from secure storage on startup.
  Future<void> _loadKey() async {
    final key = await _aiRepository.getApiKey();
    state = key;
  }

  /// Saves the API key securely.
  Future<void> saveKey(String key) async {
    await _aiRepository.saveApiKey(key);
    state = key;
  }

  /// Deletes the API key from secure storage.
  Future<void> removeKey() async {
    await _aiRepository.deleteApiKey();
    state = null;
  }
}

/// Provider for the API Key state.
final apiKeyProvider = StateNotifierProvider<ApiKeyNotifier, String?>((ref) {
  return ApiKeyNotifier(ref.watch(aiRepositoryProvider));
});

/// StateNotifier that manages the local AI Settings state and serializes it in SharedPreferences.
class AiSettingsNotifier extends StateNotifier<AiSettings> {
  final AiSettingsRepository _repository;

  AiSettingsNotifier(this._repository)
      : super(_repository.loadSettings());

  /// Updates settings locally and triggers SharedPreferences saving.
  Future<void> updateSettings({
    bool? isEnabled,
    String? model,
    bool? apiKeyExists,
    DateTime? lastValidatedAt,
  }) async {
    final updated = state.copyWith(
      isEnabled: isEnabled,
      model: model,
      apiKeyExists: apiKeyExists,
      lastValidatedAt: lastValidatedAt,
    );
    await _repository.saveSettings(updated);
    state = updated;
  }

  /// Disables AI features and purges settings cache.
  Future<void> clearSettings() async {
    await _repository.clearSettings();
    state = AiSettings.defaultSettings();
  }
}

/// Provider for the AI Settings state.
final aiSettingsProvider = StateNotifierProvider<AiSettingsNotifier, AiSettings>((ref) {
  final repository = ref.watch(aiSettingsRepositoryProvider);
  return AiSettingsNotifier(repository);
});

// ────────────────────────── COMPUTED STATUS ──────────────────────────

/// State model representing aggregated AI status.
class AiStatus {
  final bool isEnabled;
  final bool hasKey;
  final bool isReady;
  final String activeModel;

  const AiStatus({
    required this.isEnabled,
    required this.hasKey,
    required this.isReady,
    required this.activeModel,
  });
}

/// Aggregated provider to expose whether AI features are fully configured and ready.
final aiStatusProvider = Provider<AiStatus>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  return AiStatus(
    isEnabled: settings.isEnabled,
    hasKey: settings.apiKeyExists,
    isReady: settings.isEnabled && settings.apiKeyExists,
    activeModel: settings.model,
  );
});

// ────────────────────────── CHAT STATE NOTIFIER ──────────────────────────

class AiChatNotifier extends StateNotifier<AiChatState> {
  final AiRepository _aiRepository;

  AiChatNotifier(this._aiRepository)
      : super(AiChatState(
          messages: [],
          isLoading: false,
          streamingText: null,
          selectedNote: null,
          selectedDeck: null,
          selectedText: null,
          error: null,
        ));

  void selectNote(Note? note) {
    state = state.copyWith(selectedNote: note, clearNote: note == null);
  }

  void selectDeck(Deck? deck) {
    state = state.copyWith(selectedDeck: deck, clearDeck: deck == null);
  }

  void selectText(String? text) {
    state = state.copyWith(selectedText: text, clearText: text == null);
  }

  void clearAllContext() {
    state = state.copyWith(
      clearNote: true,
      clearDeck: true,
      clearText: true,
    );
  }

  void clearChat() {
    state = state.copyWith(
      messages: [],
      clearError: true,
      isLoading: false,
      streamingText: '',
    );
  }

  Future<void> sendMessage(String query) async {
    if (query.trim().isEmpty && state.selectedNote == null && state.selectedText == null) return;

    final userMessage = ChatMessage(
      id: const Uuid().v4(),
      content: query,
      isUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      clearError: true,
    );

    // 1. Build context string
    String? contextText;
    final sb = StringBuffer();
    if (state.selectedNote != null) {
      sb.writeln('Active Note Title: ${state.selectedNote!.title}');
      sb.writeln('Active Note Content:\n${state.selectedNote!.content}');
    }
    if (state.selectedText != null && state.selectedText!.trim().isNotEmpty) {
      sb.writeln('Selected/Pasted Context Text:\n${state.selectedText}');
    }
    if (state.selectedDeck != null) {
      sb.writeln('Active Deck Title: ${state.selectedDeck!.title}');
      sb.writeln('Active Deck Description: ${state.selectedDeck!.description}');
    }
    if (sb.isNotEmpty) {
      contextText = sb.toString().trim();
    }

    // 2. Format chat history
    final history = state.messages
        .where((m) => m.id != userMessage.id) // Exclude the current user query
        .map((m) => {
              'role': m.isUser ? 'user' : 'model',
              'content': m.content,
            })
        .toList();

    // 3. Call repository
    final result = await _aiRepository.generateAiResponse(
      query: query,
      contextText: contextText,
      chatHistory: history,
    );

    if (result.isSuccess) {
      final aiRes = result.data!;
      state = state.copyWith(isLoading: false);
      
      // 4. Stream response to UI
      await _streamText(
        aiRes.text,
        category: aiRes.category,
        complexity: aiRes.complexity,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error,
      );
    }
  }

  Future<void> regenerateLastMessage() async {
    final messages = state.messages;
    final lastUserIdx = messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx == -1) return;

    final queryText = messages[lastUserIdx].content;

    // Remove everything after the last user message
    final newMessages = messages.sublist(0, lastUserIdx);
    state = state.copyWith(messages: newMessages);

    // Resend
    await sendMessage(queryText);
  }

  /// Simulated typing/streaming effect
  Future<void> _streamText(
    String fullText, {
    required String category,
    required String complexity,
  }) async {
    final words = fullText.split(' ');
    String current = '';
    
    for (int i = 0; i < words.length; i++) {
      if (current.isNotEmpty) current += ' ';
      current += words[i];
      state = state.copyWith(streamingText: current);
      // Wait ~15ms between words to simulate real-time typing
      await Future.delayed(const Duration(milliseconds: 15));
    }

    // Done streaming, save as permanent message
    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      content: fullText,
      isUser: false,
      timestamp: DateTime.now(),
      category: category,
      complexity: complexity,
    );

    state = state.copyWith(
      messages: [...state.messages, assistantMessage],
      streamingText: '', // Clear streaming text
    );
  }
}

/// Provider for the AI Chat state.
final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref.watch(aiRepositoryProvider));
});

// ────────────────────────── BACKWARD COMPATIBLE SERVICE ADAPTER ──────────────────────────

/// Adapter to keep original codebase calls working, routing through new AiRepository.
class AiService {
  final AiRepository _aiRepository;

  AiService(this._aiRepository);

  Future<Result<String>> summarizeText(String text) async {
    return await _aiRepository.generateSummary(text);
  }

  Future<Result<String>> generateFlashcards(String text) async {
    return await _aiRepository.generateFlashcards(text);
  }

  Future<Result<String>> explainConcept(String text) async {
    return await _aiRepository.explainConcept(text);
  }
}

/// Provider exposing the backward-compatible AiService adapter.
final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(ref.watch(aiRepositoryProvider));
});
