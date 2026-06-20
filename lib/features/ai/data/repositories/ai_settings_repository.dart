import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/ai_settings.dart';

/// Repository responsible for loading and saving AI settings in SharedPreferences.
class AiSettingsRepository {
  final SharedPreferences _prefs;
  static const _settingsKey = 'ai_settings_key';

  AiSettingsRepository(this._prefs);

  /// Loads AI Settings from SharedPreferences. Returns default settings if none found.
  AiSettings loadSettings() {
    try {
      final jsonStr = _prefs.getString(_settingsKey);
      if (jsonStr != null) {
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return AiSettings.fromJson(map);
      }
    } catch (_) {
      // Silently fall back to default settings on error
    }
    return AiSettings.defaultSettings();
  }

  /// Saves AI Settings to SharedPreferences.
  Future<void> saveSettings(AiSettings settings) async {
    final jsonStr = jsonEncode(settings.toJson());
    await _prefs.setString(_settingsKey, jsonStr);
  }

  /// Clears the AI Settings configuration.
  Future<void> clearSettings() async {
    await _prefs.remove(_settingsKey);
  }
}
