import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';

/// Theme mode options
enum AppThemeMode { light, dark, amoled }

/// Theme mode state provider
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  return ThemeModeNotifier();
});

/// Provider for the current ThemeData
final themeDataProvider = Provider<ThemeData>((ref) {
  final mode = ref.watch(themeModeProvider);
  return switch (mode) {
    AppThemeMode.light => AppTheme.lightTheme,
    AppThemeMode.dark => AppTheme.darkTheme,
    AppThemeMode.amoled => AppTheme.amoledTheme,
  };
});

/// Theme mode notifier
class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  ThemeModeNotifier() : super(AppThemeMode.light);

  void setThemeMode(AppThemeMode mode) {
    state = mode;
  }

  void toggleTheme() {
    state = switch (state) {
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.amoled,
      AppThemeMode.amoled => AppThemeMode.light,
    };
  }

  ThemeMode get themeMode => switch (state) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.amoled => ThemeMode.dark,
      };
}
