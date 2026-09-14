import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _boxKey = 'app_preferences';
  static const String _themeKey = 'theme_mode';

  @override
  ThemeMode build() {
    try {
      if (Hive.isBoxOpen(_boxKey)) {
        final box = Hive.box(_boxKey);
        final saved = box.get(_themeKey, defaultValue: 'system') as String;
        if (saved == 'dark') return ThemeMode.dark;
        if (saved == 'light') return ThemeMode.light;
        return ThemeMode.system;
      }
    } catch (_) {}
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final box = Hive.isBoxOpen(_boxKey)
          ? Hive.box(_boxKey)
          : await Hive.openBox(_boxKey);
      final val = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.system ? 'system' : 'light');
      await box.put(_themeKey, val);
    } catch (_) {}
  }

  Future<void> toggleTheme(bool isCurrentlyDark) async {
    final newMode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }
}
