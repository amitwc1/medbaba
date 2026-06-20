/// Model representing the local AI configurations.
/// The API Key itself is never stored here.
class AiSettings {
  final bool isEnabled;
  final String provider;
  final String model;
  final bool apiKeyExists;
  final DateTime? lastValidatedAt;

  const AiSettings({
    required this.isEnabled,
    required this.provider,
    required this.model,
    required this.apiKeyExists,
    this.lastValidatedAt,
  });

  /// Returns the default settings state.
  factory AiSettings.defaultSettings() {
    return const AiSettings(
      isEnabled: false,
      provider: 'gemini',
      model: 'gemini-2.5-flash',
      apiKeyExists: false,
      lastValidatedAt: null,
    );
  }

  AiSettings copyWith({
    bool? isEnabled,
    String? provider,
    String? model,
    bool? apiKeyExists,
    DateTime? lastValidatedAt,
  }) {
    return AiSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      apiKeyExists: apiKeyExists ?? this.apiKeyExists,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': isEnabled,
      'provider': provider,
      'model': model,
      'apiKeyExists': apiKeyExists,
      'lastValidatedAt': lastValidatedAt?.toIso8601String(),
    };
  }

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    return AiSettings(
      isEnabled: json['isEnabled'] as bool? ?? false,
      provider: json['provider'] as String? ?? 'gemini',
      model: json['model'] as String? ?? 'gemini-2.5-flash',
      apiKeyExists: json['apiKeyExists'] as bool? ?? false,
      lastValidatedAt: json['lastValidatedAt'] != null
          ? DateTime.tryParse(json['lastValidatedAt'] as String)
          : null,
    );
  }
}
