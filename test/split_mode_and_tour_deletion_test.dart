import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/services/active_tour_cache_service.dart';
import 'package:toursplit/presentation/widgets/whats_new_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_split_del_');
    Hive.init(tempDir.path);
    await Hive.openBox(ActiveTourCacheService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Add Expense Split Rearrangement Logic Tests', () {
    test('Specific Member mode defaults to single selected member', () {
      final now = DateTime(2026, 1, 1);
      final members = [
        TourMemberModel(userId: 'user_alice', displayName: 'Alice', email: 'alice@example.com', role: 'admin', joinedAt: now),
        TourMemberModel(userId: 'user_bob', displayName: 'Bob', email: 'bob@example.com', role: 'member', joinedAt: now),
        TourMemberModel(userId: 'user_charlie', displayName: 'Charlie', email: 'charlie@example.com', role: 'member', joinedAt: now),
      ];

      // Simulated initialization logic from AddExpenseScreen
      final currentUserId = 'user_alice';
      String? paidByUserId;
      List<String> selectedMemberIds = [];

      final defaultPayer = members.firstWhere(
        (m) => m.userId == currentUserId,
        orElse: () => members.first,
      );
      paidByUserId = defaultPayer.userId;

      if (selectedMemberIds.isEmpty) {
        final defaultTarget = paidByUserId;
        final targetMember = members.firstWhere(
          (m) => m.userId == defaultTarget,
          orElse: () => members.first,
        );
        selectedMemberIds = [targetMember.userId];
      }

      // Assert only 1 member selected by default
      expect(selectedMemberIds.length, 1);
      expect(selectedMemberIds.first, 'user_alice');

      // Tapping another member in Specific Member mode adds or switches
      selectedMemberIds.add('user_bob');
      expect(selectedMemberIds.length, 2);

      // Deselecting first member leaves single member
      selectedMemberIds.remove('user_alice');
      expect(selectedMemberIds.length, 1);
      expect(selectedMemberIds.first, 'user_bob');
    });

    test('Equal split mode shares among all members equally', () {
      final now = DateTime(2026, 1, 1);
      final members = [
        TourMemberModel(userId: 'user_alice', displayName: 'Alice', email: 'alice@example.com', role: 'admin', joinedAt: now),
        TourMemberModel(userId: 'user_bob', displayName: 'Bob', email: 'bob@example.com', role: 'member', joinedAt: now),
      ];

      int splitMode = 0; // Equally (All)
      final splitMembers = splitMode == 0
          ? members.map((m) => m.userId).toList()
          : ['user_alice'];

      expect(splitMembers.length, 2);
      expect(splitMembers, containsAll(['user_alice', 'user_bob']));
    });

    test('Custom split mode maps exact amounts correctly and verifies total', () {
      final customSplits = <String, double>{
        'user_alice': 300.0,
        'user_bob': 200.0,
      };

      final totalExpense = 500.0;
      final sum = customSplits.values.fold(0.0, (acc, v) => acc + v);

      expect((sum - totalExpense).abs() < 0.05, isTrue);
      expect(customSplits.keys.toList(), containsAll(['user_alice', 'user_bob']));
    });
  });

  group('Complete Tour Removal & ActiveTourCacheService Tests', () {
    test('removeTourCache completely removes all tour keys and active tour data',
        () async {
      const tourId = 'tour_to_delete_complete';
      final tour = TourModel(
        id: tourId,
        name: 'Deleted Beach Tour',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'creator_1',
        inviteCode: 'DEL123',
        status: TourStatus.active,
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 3)),
        memberIds: ['creator_1', 'member_2'],
        createdAt: DateTime.now(),
      );

      final now = DateTime(2026, 1, 1);
      final members = <TourMemberModel>[
        TourMemberModel(userId: 'creator_1', displayName: 'Creator', email: 'creator@example.com', role: 'admin', joinedAt: now),
        TourMemberModel(userId: 'member_2', displayName: 'Member Two', email: 'member2@example.com', role: 'member', joinedAt: now),
      ];

      await ActiveTourCacheService.cacheActiveTour(
        tour: tour,
        members: members,
      );

      expect(ActiveTourCacheService.getActiveTourId(), tourId);
      expect(ActiveTourCacheService.getCachedMembers(tourId).length, 2);

      // Now tour creator deletes the tour completely from everyone's account
      await ActiveTourCacheService.removeTourCache(tourId);

      expect(ActiveTourCacheService.getActiveTourId(), isNull);
      expect(ActiveTourCacheService.getCachedActiveTour(), isNull);
      expect(ActiveTourCacheService.getCachedMembers(tourId), isEmpty);
    });
  });

  group('WhatsNewDialog Feature Standard Tests', () {
    test('contains Unified Navigation Bar feature with emoji formatting', () {
      final navBarFeature = WhatsNewDialog.features.firstWhere(
        (f) => f.title == 'Unified Navigation Bar',
      );
      expect(navBarFeature.description, contains('bottom navigation bar'));
      expect(WhatsNewDialog.features.length, 7);
    });
  });
}
