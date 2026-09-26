import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/services/user_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_user_cache_');
    Hive.init(tempDir.path);
    await Hive.openBox<Map>(UserCacheService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TourMemberModel.displayHandle tests', () {
    test('Offline member returns "Offline Friend"', () {
      final member = TourMemberModel(
        userId: 'offline_1',
        displayName: 'Bob (Offline)',
        email: '',
        role: 'member',
        joinedAt: DateTime.now(),
        isOffline: true,
      );

      expect(member.displayHandle, 'Offline Friend');
    });

    test('Online member with username returns "@username"', () {
      final member = TourMemberModel(
        userId: 'user_1',
        displayName: 'John Doe',
        username: 'johndoe',
        email: 'john@example.com',
        role: 'member',
        joinedAt: DateTime.now(),
        isOffline: false,
      );

      expect(member.displayHandle, '@johndoe');
    });

    test('Online member without username falls back to email handle', () {
      final member = TourMemberModel(
        userId: 'user_2',
        displayName: 'Alice Smith',
        username: '',
        email: 'alice.smith@example.com',
        role: 'member',
        joinedAt: DateTime.now(),
        isOffline: false,
      );

      expect(member.displayHandle, '@alice.smith');
    });

    test('Online member with no username and no email returns empty string', () {
      final member = TourMemberModel(
        userId: 'user_3',
        displayName: 'Guest',
        username: '',
        email: '',
        role: 'member',
        joinedAt: DateTime.now(),
        isOffline: false,
      );

      expect(member.displayHandle, '');
    });
  });

  group('UserCacheService username persistence tests', () {
    test('Caches user with username correctly', () async {
      await UserCacheService.cacheUser(
        uid: 'user_10',
        displayName: 'Sarah Connor',
        username: 'sarahc',
        photoUrl: 'https://example.com/sarah.jpg',
      );

      final cached = UserCacheService.getUser('user_10');
      expect(cached, isNotNull);
      expect(cached!.uid, 'user_10');
      expect(cached.displayName, 'Sarah Connor');
      expect(cached.username, 'sarahc');
      expect(cached.photoUrl, 'https://example.com/sarah.jpg');
    });

    test('Preserves existing username when updated with empty username', () async {
      await UserCacheService.cacheUser(
        uid: 'user_20',
        displayName: 'Miles Morales',
        username: 'spiderman',
      );

      // Subsequent update without username (e.g. from an offline member record or partial payload)
      await UserCacheService.cacheUser(
        uid: 'user_20',
        displayName: 'Miles Morales (Updated)',
        username: '',
      );

      final cached = UserCacheService.getUser('user_20');
      expect(cached, isNotNull);
      expect(cached!.displayName, 'Miles Morales (Updated)');
      expect(cached.username, 'spiderman');
    });

    test('Updates username when new username is non-empty', () async {
      await UserCacheService.cacheUser(
        uid: 'user_30',
        displayName: 'Peter Parker',
        username: 'peterp',
      );

      await UserCacheService.cacheUser(
        uid: 'user_30',
        displayName: 'Peter Parker',
        username: 'webslinger',
      );

      final cached = UserCacheService.getUser('user_30');
      expect(cached, isNotNull);
      expect(cached!.username, 'webslinger');
    });

    test('cacheTourMember preserves existing username if tour member username is empty', () async {
      await UserCacheService.cacheUser(
        uid: 'user_40',
        displayName: 'Gwen Stacy',
        username: 'spidergwen',
      );

      final member = TourMemberModel(
        userId: 'user_40',
        displayName: 'Gwen Stacy',
        username: '',
        email: 'gwen@example.com',
        role: 'member',
        joinedAt: DateTime.now(),
      );

      await UserCacheService.cacheTourMember(member);

      final cached = UserCacheService.getUser('user_40');
      expect(cached, isNotNull);
      expect(cached!.username, 'spidergwen');
    });
  });
}
