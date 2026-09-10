import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Service managing the welcome greeting cycle on app open.
///
/// Instead of automatically cycling continuously while on the screen,
/// the greeting cycles once each time the user opens the app.
class WelcomeGreetingService {
  static const String _boxName = 'app_preferences';
  static const String _key = 'welcome_greeting_index';

  static int _sessionGreetingIndex = 0;
  static bool _initialized = false;

  /// Advances the persistent greeting index by 1 each time the app is launched.
  /// Stores and caches the value in memory for the duration of this app session.
  static Future<int> advanceSessionGreeting() async {
    if (_initialized) {
      return _sessionGreetingIndex;
    }
    _initialized = true;
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box(_boxName)
          : await Hive.openBox(_boxName);
      final lastIndex = box.get(_key, defaultValue: -1) as int;
      _sessionGreetingIndex = lastIndex + 1;
      await box.put(_key, _sessionGreetingIndex);
    } catch (e) {
      debugPrint('[GREETING] Error accessing Hive: $e');
      _sessionGreetingIndex = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    return _sessionGreetingIndex;
  }

  /// Returns the greeting index established for this app session.
  static int get sessionGreetingIndex => _sessionGreetingIndex;

  /// Visible for testing: resets the session initialization flag and index.
  @visibleForTesting
  static void resetForTesting([int index = 0]) {
    _initialized = false;
    _sessionGreetingIndex = index;
  }
}
