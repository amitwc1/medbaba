import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SharedPreferences _prefs;
  static const _apiKeyKey = 'gemini_api_key';

  SettingsNotifier(this._prefs) : super(SettingsState(
    geminiApiKey: _prefs.getString(_apiKeyKey),
  ));

  Future<void> setGeminiApiKey(String key) async {
    await _prefs.setString(_apiKeyKey, key);
    state = state.copyWith(geminiApiKey: key);
  }
}

class SettingsState {
  final String? geminiApiKey;

  SettingsState({this.geminiApiKey});

  SettingsState copyWith({String? geminiApiKey}) {
    return SettingsState(
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(sharedPreferencesProvider));
});
