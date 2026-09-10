import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:toursplit/data/services/welcome_greeting_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_greeting_test');
    Hive.init(tempDir.path);
    WelcomeGreetingService.resetForTesting(0);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WelcomeGreetingService Tests', () {
    test('First app open initializes greeting index to 0', () async {
      final index = await WelcomeGreetingService.advanceSessionGreeting();
      expect(index, 0);
      expect(WelcomeGreetingService.sessionGreetingIndex, 0);
    });

    test('Calling advanceSessionGreeting multiple times in same session does not re-advance', () async {
      final first = await WelcomeGreetingService.advanceSessionGreeting();
      final second = await WelcomeGreetingService.advanceSessionGreeting();
      expect(first, second);
      expect(first, 0);
    });

    test('Simulating subsequent app opens advances the greeting index sequentially', () async {
      // 1st open
      final open1 = await WelcomeGreetingService.advanceSessionGreeting();
      expect(open1, 0);

      // Simulate app restart: reset session in-memory state
      WelcomeGreetingService.resetForTesting();
      final open2 = await WelcomeGreetingService.advanceSessionGreeting();
      expect(open2, 1);

      // Simulate 3rd app restart
      WelcomeGreetingService.resetForTesting();
      final open3 = await WelcomeGreetingService.advanceSessionGreeting();
      expect(open3, 2);

      // Simulate 4th app restart
      WelcomeGreetingService.resetForTesting();
      final open4 = await WelcomeGreetingService.advanceSessionGreeting();
      expect(open4, 3);
    });
  });
}
