import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/expense_model.dart';
import 'package:toursplit/data/models/settlement_model.dart';
import 'package:toursplit/data/services/active_tour_cache_service.dart';
import 'package:toursplit/data/services/offline_expense_queue_service.dart';
import 'package:toursplit/data/services/offline_tour_queue_service.dart';
import 'package:toursplit/data/repositories/expense_repository.dart';
import 'package:toursplit/data/repositories/tour_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockExpenseRepository implements ExpenseRepository {
  final List<ExpenseModel> added = [];

  @override
  Future<ExpenseModel> addExpense(ExpenseModel expense) async {
    added.add(expense);
    return expense;
  }

  @override
  String generateExpenseId(String tourId) => 'mock_expense_${added.length + 1}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_offline_');
    Hive.init(tempDir.path);
    await Hive.openBox(ActiveTourCacheService.boxName);
    await Hive.openBox(OfflineExpenseQueueService.boxName);
    await Hive.openBox(OfflineTourQueueService.boxName);
    await Hive.openBox(OfflineTourQueueService.localToursBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ActiveTourCacheService Tests', () {
    test('Caches and restores single active tour and members accurately', () async {
      final now = DateTime.now();
      final tour = TourModel(
        id: 'tour_sajek_1',
        name: 'Sajek Valley Tour',
        description: 'Trip to Sajek',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_1',
        inviteCode: 'SAJEK123',
        status: TourStatus.active,
        startDate: now,
        createdAt: now,
        memberIds: ['admin_1', 'user_2'],
      );

      final members = [
        TourMemberModel(
          userId: 'admin_1',
          displayName: 'Admin Leader',
          username: 'leader',
          email: 'admin@toursplit.app',
          role: 'admin',
          joinedAt: now,
        ),
        TourMemberModel(
          userId: 'user_2',
          displayName: 'Traveler Jane',
          username: 'jane',
          email: 'jane@toursplit.app',
          role: 'member',
          joinedAt: now,
        ),
      ];

      final exp = ExpenseModel(
        id: 'cached_exp_1',
        tourId: 'tour_sajek_1',
        title: 'Lunch',
        amount: 500.0,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'admin_1',
        paidByName: 'Admin Leader',
        splitType: SplitType.equal,
        splitAmong: ['admin_1', 'user_2'],
        status: ExpenseStatus.approved,
        date: now,
        createdAt: now,
        addedByUserId: 'admin_1',
      );

      await ActiveTourCacheService.cacheActiveTour(
        tour: tour,
        members: members,
        expenses: [exp],
      );

      expect(ActiveTourCacheService.getActiveTourId(), 'tour_sajek_1');
      final restoredTour = ActiveTourCacheService.getCachedActiveTour();
      expect(restoredTour, isNotNull);
      expect(restoredTour!.id, 'tour_sajek_1');
      expect(restoredTour.name, 'Sajek Valley Tour');
      expect(restoredTour.currencySymbol, '৳');
      expect(restoredTour.memberIds, contains('user_2'));

      final restoredMembers = ActiveTourCacheService.getCachedMembers('tour_sajek_1');
      expect(restoredMembers.length, 2);
      expect(restoredMembers.first.displayName, 'Admin Leader');
      expect(restoredMembers.last.displayName, 'Traveler Jane');

      final restoredExpenses = ActiveTourCacheService.getCachedExpenses('tour_sajek_1');
      expect(restoredExpenses.length, 1);
      expect(restoredExpenses.first.id, 'cached_exp_1');
      expect(restoredExpenses.first.title, 'Lunch');
      expect(restoredExpenses.first.amount, 500.0);
    });

    test('clearCachedActiveTour clears cached tour ID, data, and members', () async {
      await ActiveTourCacheService.clearCachedActiveTour();
      expect(ActiveTourCacheService.getActiveTourId(), isNull);
      expect(ActiveTourCacheService.getCachedActiveTour(), isNull);
      expect(ActiveTourCacheService.getCachedMembers('tour_sajek_1'), isEmpty);
    });

    test('clearActiveTourId clears only the active tour pointer while preserving cached tour data', () async {
      final sampleTour = TourModel(
        id: 'tour_cox_preserved',
        name: 'Cox Bazar Preserved',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_1',
        inviteCode: 'PRESERVED1',
        status: TourStatus.active,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 5),
        memberIds: ['admin_1'],
        createdAt: DateTime(2026, 3, 1),
      );

      await ActiveTourCacheService.cacheActiveTour(tour: sampleTour);
      expect(ActiveTourCacheService.getActiveTourId(), 'tour_cox_preserved');
      expect(ActiveTourCacheService.getCachedActiveTour()?.name, 'Cox Bazar Preserved');

      await ActiveTourCacheService.clearActiveTourId();
      expect(ActiveTourCacheService.getActiveTourId(), isNull);
      expect(ActiveTourCacheService.getCachedActiveTour(), isNull);
    });

    test('activeTourIdProvider returns null when activeTourIdOverrideProvider is kNoActiveTourId', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Cache a tour first
      await ActiveTourCacheService.setActiveTourId('tour_cox_preserved');
      expect(container.read(activeTourIdProvider), 'tour_cox_preserved');

      // Set override to kNoActiveTourId -> returns null so landing screen displays
      container.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
      expect(container.read(activeTourIdProvider), isNull);

      // Re-selecting a tour overrides kNoActiveTourId
      container.read(activeTourIdOverrideProvider.notifier).state = 'new_selected_tour';
      expect(container.read(activeTourIdProvider), 'new_selected_tour');
    });
  });

  group('OfflineExpenseQueueService Tests', () {
    test('Queues expense locally and retrieves it correctly', () async {
      final mockRepo = MockExpenseRepository();
      final service = OfflineExpenseQueueService(
        expenseRepo: mockRepo,
        connectivity: Connectivity(),
      );

      final exp1 = ExpenseModel(
        id: 'local_exp_1',
        tourId: 'tour_sajek_1',
        title: 'Highway Breakfast',
        amount: 850.0,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'user_2',
        paidByName: 'Traveler Jane',
        splitType: SplitType.equal,
        splitAmong: ['admin_1', 'user_2'],
        status: ExpenseStatus.pendingApproval,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        addedByUserId: 'user_2',
      );

      await service.queueExpense(exp1);

      final queued = service.getQueuedExpenses(tourId: 'tour_sajek_1');
      expect(queued.length, 1);
      expect(queued.first.id, 'local_exp_1');
      expect(queued.first.title, 'Highway Breakfast');
      expect(queued.first.amount, 850.0);
      expect(queued.first.paidByName, 'Traveler Jane');

      // Sync test
      final syncedCount = await service.syncQueuedExpenses();
      expect(syncedCount, 1);
      expect(mockRepo.added.length, 1);
      expect(mockRepo.added.first.title, 'Highway Breakfast');

      // Queue should now be empty after sync
      final remaining = service.getQueuedExpenses(tourId: 'tour_sajek_1');
      expect(remaining.isEmpty, isTrue);
    });
  });

  group('OfflineTourQueueService & Offline Tour Deletion Tests', () {
    test('createTourLocally stores tour and admin member, and deleteLocalTour cleans up fully', () async {
      final service = OfflineTourQueueService();
      final now = DateTime.now();

      final tour = await service.createTourLocally(
        name: 'Cox\'s Bazar Trip',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'user_shoruv_1',
        startDate: now,
        endDate: now.add(const Duration(days: 3)),
        adminName: 'Shoruv',
        adminEmail: 'shoruv@example.com',
      );

      expect(tour.id.startsWith('local_'), isTrue);
      expect(tour.name, 'Cox\'s Bazar Trip');
      expect(tour.memberIds, contains('user_shoruv_1'));

      // Check local tours box has the tour and admin member
      final localBox = Hive.box(OfflineTourQueueService.localToursBox);
      expect(localBox.containsKey(tour.id), isTrue);
      expect(localBox.containsKey('member_${tour.id}_user_shoruv_1'), isTrue);

      final qBox = Hive.box(OfflineTourQueueService.boxName);
      expect(qBox.containsKey('create_${tour.id}'), isTrue);

      // Delete locally
      await service.deleteLocalTour(tour.id);
      expect(localBox.containsKey(tour.id), isFalse);
      expect(localBox.containsKey('member_${tour.id}_user_shoruv_1'), isFalse);
      expect(qBox.containsKey('create_${tour.id}'), isFalse);
    });

    test('queueTourDeletion queues deletion and getQueuedDeletedTourIds returns it', () async {
      final service = OfflineTourQueueService();
      const serverTourId = 'online_tour_dhaka_99';

      await service.queueTourDeletion(tourId: serverTourId, currentUserId: 'user_shoruv_1');
      final deletedIds = service.getQueuedDeletedTourIds();

      expect(deletedIds.contains(serverTourId), isTrue);
    });

    test('addOfflineMemberLocally preserves admin and includes all n added members', () async {
      final service = OfflineTourQueueService();
      final now = DateTime.now();

      final tour = await service.createTourLocally(
        name: 'Sylhet Tour',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_shoruv',
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        adminName: 'Shoruv',
        adminEmail: 'shoruv@test.com',
      );

      final m1 = await service.addOfflineMemberLocally(
        tourId: tour.id,
        name: 'Ruhel',
      );

      final m2 = await service.addOfflineMemberLocally(
        tourId: tour.id,
        name: 'Hai',
      );

      final tourRepo = TourRepository();
      final members = tourRepo.getLocalTourMembers(tour.id);

      expect(members.length, 3);
      expect(members.map((m) => m.userId), containsAll(['admin_shoruv', m1.userId, m2.userId]));
      expect(members.map((m) => m.displayName), containsAll(['Shoruv', 'Ruhel', 'Hai']));
    });
  });

  group('Offline Expense Queue & Deletion Tests', () {
    test('queueExpense immediately caches and queues, getLocalExpenses returns it', () async {
      final mockRepo = MockExpenseRepository();
      final queueService = OfflineExpenseQueueService(expenseRepo: mockRepo);
      final expenseRepo = ExpenseRepository();
      const localTourId = 'local_cox_bazar_42';
      final now = DateTime.now();

      final exp1 = ExpenseModel(
        id: 'off_exp_1',
        tourId: localTourId,
        title: 'Dinner',
        amount: 1200.0,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'admin_shoruv',
        paidByName: 'Shoruv',
        splitType: SplitType.equal,
        splitAmong: ['admin_shoruv', 'offline_friend_1'],
        status: ExpenseStatus.approved,
        date: now,
        createdAt: now,
        addedByUserId: 'admin_shoruv',
      );

      final exp2 = ExpenseModel(
        id: 'off_exp_2',
        tourId: localTourId,
        title: 'CNG Fare',
        amount: 300.0,
        currency: 'BDT',
        category: 'Transport',
        paidByUserId: 'offline_friend_1',
        paidByName: 'Friend 1',
        splitType: SplitType.equal,
        splitAmong: ['admin_shoruv', 'offline_friend_1'],
        status: ExpenseStatus.approved,
        date: now.add(const Duration(minutes: 5)),
        createdAt: now.add(const Duration(minutes: 5)),
        addedByUserId: 'admin_shoruv',
      );

      await queueService.queueExpense(exp1);
      await queueService.queueExpense(exp2);

      // Verify both appear in local expenses
      final localExpenses = expenseRepo.getLocalExpenses(localTourId);
      expect(localExpenses.length, 2);
      expect(localExpenses.map((e) => e.id), containsAll(['off_exp_1', 'off_exp_2']));

      final totalSpent = localExpenses.where((e) => e.isApproved).fold(0.0, (s, e) => s + e.amount);
      expect(totalSpent, 1500.0);

      // Delete exp1 offline
      await expenseRepo.deleteExpense(localTourId, exp1.id);

      final remainingExpenses = expenseRepo.getLocalExpenses(localTourId);
      expect(remainingExpenses.length, 1);
      expect(remainingExpenses.first.id, 'off_exp_2');

      // Total spent recalculates immediately without the deleted expense
      final newTotalSpent = remainingExpenses.where((e) => e.isApproved).fold(0.0, (s, e) => s + e.amount);
      expect(newTotalSpent, 300.0);
    });

    test('queueExpenseDeletion for online tour excludes expense from local resolution', () async {
      final mockRepo = MockExpenseRepository();
      final queueService = OfflineExpenseQueueService(expenseRepo: mockRepo);
      final expenseRepo = ExpenseRepository();
      const onlineTourId = 'online_sundarbans_88';
      final now = DateTime.now();

      final exp = ExpenseModel(
        id: 'server_exp_777',
        tourId: onlineTourId,
        title: 'Boat Ride',
        amount: 2500.0,
        currency: 'BDT',
        category: 'Transport',
        paidByUserId: 'admin_1',
        paidByName: 'Admin',
        splitType: SplitType.equal,
        splitAmong: ['admin_1'],
        status: ExpenseStatus.approved,
        date: now,
        createdAt: now,
        addedByUserId: 'admin_1',
      );

      // Cache it
      await ActiveTourCacheService.appendCachedExpense(onlineTourId, exp);
      expect(expenseRepo.getLocalExpenses(onlineTourId).any((e) => e.id == 'server_exp_777'), isTrue);

      // Delete while offline
      await expenseRepo.deleteExpense(onlineTourId, 'server_exp_777');

      final deletedIds = queueService.getQueuedDeletedExpenseIds(tourId: onlineTourId);
      expect(deletedIds.contains('server_exp_777'), isTrue);

      // Verify it is excluded from getLocalExpenses
      final localExpenses = expenseRepo.getLocalExpenses(onlineTourId);
      expect(localExpenses.any((e) => e.id == 'server_exp_777'), isFalse);
    });

    test('pruneStaleToursCache keeps only active tour data and removes other tours', () async {
      final tourA = TourModel(
        id: 'tour_A',
        name: 'Tour A',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_1',
        inviteCode: 'TOURA1',
        status: TourStatus.active,
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        memberIds: ['admin_1'],
        createdAt: DateTime.now(),
      );

      final expA = ExpenseModel(
        id: 'exp_A_1',
        tourId: 'tour_A',
        title: 'Lunch A',
        amount: 200,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'admin_1',
        paidByName: 'Admin',
        splitType: SplitType.equal,
        splitAmong: ['admin_1'],
        status: ExpenseStatus.approved,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        addedByUserId: 'admin_1',
      );

      final expB = ExpenseModel(
        id: 'exp_B_1',
        tourId: 'tour_B',
        title: 'Dinner B',
        amount: 500,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'admin_1',
        paidByName: 'Admin',
        splitType: SplitType.equal,
        splitAmong: ['admin_1'],
        status: ExpenseStatus.approved,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        addedByUserId: 'admin_1',
      );

      // Cache Tour B first
      await ActiveTourCacheService.appendCachedExpense('tour_B', expB);
      expect(ActiveTourCacheService.getCachedExpenses('tour_B').isNotEmpty, isTrue);

      // Now activate and cache Tour A
      await ActiveTourCacheService.cacheActiveTour(
        tour: tourA,
        expenses: [expA],
      );

      // Verify Tour A is retained
      expect(ActiveTourCacheService.getActiveTourId(), 'tour_A');
      expect(ActiveTourCacheService.getCachedExpenses('tour_A').length, 1);

      // Verify Tour B was pruned from cache to save storage
      expect(ActiveTourCacheService.getCachedExpenses('tour_B'), isEmpty);
    });

    test('reassignTourId and remapTourId updates local tour to synced Firestore tour ID', () async {
      final queueService = OfflineExpenseQueueService(
        expenseRepo: MockExpenseRepository(),
        connectivity: Connectivity(),
      );

      final localExp = ExpenseModel(
        id: 'local_exp_999',
        tourId: 'local_tour_dhaka',
        title: 'Boat Rental',
        amount: 1200,
        currency: 'BDT',
        category: 'Transport',
        paidByUserId: 'admin_1',
        paidByName: 'Admin',
        splitType: SplitType.equal,
        splitAmong: ['admin_1'],
        status: ExpenseStatus.approved,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        addedByUserId: 'admin_1',
      );

      // Queue and cache under local tour ID
      await queueService.queueExpense(localExp);
      expect(queueService.getQueuedExpenses(tourId: 'local_tour_dhaka').length, 1);
      expect(ActiveTourCacheService.getCachedExpenses('local_tour_dhaka').length, 1);

      // Remap to synced Firestore tour ID
      const realTourId = 'real_firestore_tour_888';
      await ActiveTourCacheService.reassignTourId('local_tour_dhaka', realTourId);
      await queueService.remapTourId('local_tour_dhaka', realTourId);

      // Verify local tour ID is empty and real tour ID contains the expense
      expect(queueService.getQueuedExpenses(tourId: 'local_tour_dhaka'), isEmpty);
      expect(queueService.getQueuedExpenses(tourId: realTourId).length, 1);
      expect(queueService.getQueuedExpenses(tourId: realTourId).first.id, 'local_exp_999');

      expect(ActiveTourCacheService.getCachedExpenses('local_tour_dhaka'), isEmpty);
      expect(ActiveTourCacheService.getCachedExpenses(realTourId).length, 1);
      expect(ActiveTourCacheService.getCachedExpenses(realTourId).first.id, 'local_exp_999');
    });

    test('Settlement offline caching and retrieval works seamlessly', () async {
      final settlement = SettlementModel(
        id: 'settle_offline_1',
        tourId: 'tour_settle_test',
        fromUserId: 'user_1',
        fromUserName: 'Alice',
        toUserId: 'user_2',
        toUserName: 'Bob',
        amount: 750,
        currency: 'BDT',
        status: SettlementStatus.approved,
        requestedAt: DateTime.now(),
        resolvedAt: DateTime.now(),
        resolvedBy: 'user_2',
      );

      await ActiveTourCacheService.appendCachedSettlement('tour_settle_test', settlement);

      final cached = ActiveTourCacheService.getCachedSettlements('tour_settle_test');
      expect(cached.length, 1);
      expect(cached.first.id, 'settle_offline_1');
      expect(cached.first.amount, 750.0);
      expect(cached.first.isApproved, isTrue);
    });

    test('pruneOrphanedLocalData removes orphaned local member entries', () async {
      final localBox = Hive.box(OfflineTourQueueService.localToursBox);
      // Valid local tour and its member
      await localBox.put('local_tour_active_123', {'id': 'local_tour_active_123', 'name': 'Active Tour'});
      await localBox.put('member_local_tour_active_123_user1', {'displayName': 'User 1'});

      // Orphaned member where tour does not exist
      await localBox.put('member_local_tour_deleted_999_user2', {'displayName': 'User 2'});

      expect(localBox.containsKey('member_local_tour_deleted_999_user2'), isTrue);

      await OfflineTourQueueService.pruneOrphanedLocalData();

      // Active tour & member preserved
      expect(localBox.containsKey('local_tour_active_123'), isTrue);
      expect(localBox.containsKey('member_local_tour_active_123_user1'), isTrue);

      // Orphaned member removed
      expect(localBox.containsKey('member_local_tour_deleted_999_user2'), isFalse);
    });
  });
}
