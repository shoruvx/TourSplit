import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/expense_model.dart';
import '../../core/constants/app_constants.dart';
import '../services/active_tour_cache_service.dart';
import '../services/offline_expense_queue_service.dart';

class ExpenseRepository {
  final FirebaseFirestore? _firestore;
  ExpenseRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference _expenses(String tourId) => _db
      .collection(AppConstants.toursCollection)
      .doc(tourId)
      .collection(AppConstants.expensesSubcollection);

  String generateExpenseId(String tourId) => _expenses(tourId).doc().id;

  Future<ExpenseModel> addExpense(ExpenseModel expense) async {
    final docRef = expense.id.isNotEmpty
        ? _expenses(expense.tourId).doc(expense.id)
        : _expenses(expense.tourId).doc();
    final expenseId = docRef.id;
    final createdNow = expense.createdAt;
    final data = expense.copyWith(id: expenseId).toFirestore()
      ..['createdAt'] = FieldValue.serverTimestamp();

    await docRef.set(data, SetOptions(merge: true));

    return expense.copyWith(id: expenseId, createdAt: createdNow);
  }

  Future<void> updateExpenseStatus(
    String tourId,
    String expenseId,
    ExpenseStatus status,
  ) async {
    // 1. Update in ActiveTourCacheService if cached
    final cached = ActiveTourCacheService.getCachedExpenses(tourId);
    final target = cached.firstWhereOrNull((e) => e.id == expenseId);
    if (target != null) {
      final updated = target.copyWith(status: status);
      await ActiveTourCacheService.appendCachedExpense(tourId, updated);
    }

    // 2. Update in OfflineExpenseQueueService if queued
    if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
      final qBox = Hive.box(OfflineExpenseQueueService.boxName);
      if (qBox.containsKey(expenseId)) {
        final val = qBox.get(expenseId);
        if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          m['status'] = status == ExpenseStatus.pendingApproval
              ? 'pending_approval'
              : status.name;
          await qBox.put(expenseId, m);
        }
      }
    }

    // 3. Update in Firestore if not a local tour
    if (!tourId.startsWith('local_')) {
      try {
        await _expenses(tourId).doc(expenseId).update({
          'status': status == ExpenseStatus.pendingApproval
              ? 'pending_approval'
              : status.name,
        }).timeout(const Duration(milliseconds: 1500));
      } catch (e) {
        debugPrint('[EXPENSE_REPO] Firestore updateExpenseStatus offline/timed out: $e');
        if (target != null) {
          final updated = target.copyWith(status: status);
          await OfflineExpenseQueueService().queueExpense(updated);
        }
      }
    }
  }

  Future<void> updateExpense(
      String tourId, String expenseId, Map<String, dynamic> data) async {
    await _expenses(tourId).doc(expenseId).update(data);
  }

  Future<void> deleteExpense(String tourId, String expenseId) async {
    // 1. Remove from active tour cache immediately
    await ActiveTourCacheService.removeCachedExpense(tourId, expenseId);

    // 2. Remove from local queue or queue deletion for online tour
    await OfflineExpenseQueueService().queueExpenseDeletion(tourId, expenseId);

    // 3. Delete from Firestore if it's an online tour
    if (!tourId.startsWith('local_')) {
      try {
        await _expenses(tourId).doc(expenseId).delete().timeout(const Duration(milliseconds: 1500));
        // If Firestore delete succeeded, remove queued deletion entry
        if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
          await Hive.box(OfflineExpenseQueueService.boxName).delete('del_$expenseId');
        }
      } catch (e) {
        debugPrint('[EXPENSE_REPO] Firestore delete offline/timeout: $e');
      }
    }
  }

  List<ExpenseModel> getLocalExpenses(String tourId) {
    final queued = OfflineExpenseQueueService().getQueuedExpenses(tourId: tourId);
    final cached = ActiveTourCacheService.getCachedExpenses(tourId);
    final deletedIds = OfflineExpenseQueueService().getQueuedDeletedExpenseIds(tourId: tourId);

    final Map<String, ExpenseModel> map = {};
    for (final e in queued) {
      if (!deletedIds.contains(e.id)) {
        map[e.id] = e;
      }
    }
    for (final e in cached) {
      if (!deletedIds.contains(e.id)) {
        map.putIfAbsent(e.id, () => e);
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  ExpenseModel? getLocalExpense(String tourId, String expenseId) {
    final deletedIds = OfflineExpenseQueueService().getQueuedDeletedExpenseIds(tourId: tourId);
    if (deletedIds.contains(expenseId)) return null;

    final queued = OfflineExpenseQueueService().getQueuedExpenses(tourId: tourId);
    final qMatch = queued.firstWhereOrNull((e) => e.id == expenseId);
    if (qMatch != null) return qMatch;

    final cached = ActiveTourCacheService.getCachedExpenses(tourId);
    return cached.firstWhereOrNull((e) => e.id == expenseId);
  }

  Stream<List<ExpenseModel>> watchExpenses(String tourId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalExpenses(tourId);
      if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
        final box = Hive.box(OfflineExpenseQueueService.boxName);
        await for (final _ in box.watch()) {
          yield getLocalExpenses(tourId);
        }
      }
      return;
    }

    final local = getLocalExpenses(tourId);
    if (local.isNotEmpty) yield local;

    try {
      yield* _expenses(tourId)
          .orderBy('date', descending: true)
          .snapshots()
          .map((snap) {
        final firestoreList =
            snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList();
        final queued =
            OfflineExpenseQueueService().getQueuedExpenses(tourId: tourId);
        final deletedIds = OfflineExpenseQueueService()
            .getQueuedDeletedExpenseIds(tourId: tourId);

        final validFirestore =
            firestoreList.where((e) => !deletedIds.contains(e.id)).toList();
        final validQueued =
            queued.where((e) => !deletedIds.contains(e.id)).toList();

        final merged = [
          ...validQueued,
          ...validFirestore.where((e) => !validQueued.any((q) => q.id == e.id)),
        ];
        merged.sort((a, b) => b.date.compareTo(a.date));
        return merged;
      });
    } catch (e) {
      debugPrint('[EXPENSE_REPO] Firestore watch failed: $e, falling back to local');
      yield getLocalExpenses(tourId);
    }
  }

  Stream<List<ExpenseModel>> watchApprovedExpenses(String tourId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalExpenses(tourId).where((e) => e.isApproved).toList();
      if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
        final box = Hive.box(OfflineExpenseQueueService.boxName);
        await for (final _ in box.watch()) {
          yield getLocalExpenses(tourId).where((e) => e.isApproved).toList();
        }
      }
      return;
    }

    final local = getLocalExpenses(tourId).where((e) => e.isApproved).toList();
    if (local.isNotEmpty) yield local;

    try {
      yield* _expenses(tourId)
          .where('status', isEqualTo: 'approved')
          .snapshots()
          .map((snap) {
        final firestoreList =
            snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList();
        final queued = OfflineExpenseQueueService()
            .getQueuedExpenses(tourId: tourId)
            .where((e) => e.isApproved)
            .toList();
        final deletedIds = OfflineExpenseQueueService()
            .getQueuedDeletedExpenseIds(tourId: tourId);

        final validFirestore =
            firestoreList.where((e) => !deletedIds.contains(e.id)).toList();
        final validQueued =
            queued.where((e) => !deletedIds.contains(e.id)).toList();

        final merged = [
          ...validQueued,
          ...validFirestore.where((e) => !validQueued.any((q) => q.id == e.id)),
        ];
        merged.sort((a, b) => b.date.compareTo(a.date));
        return merged;
      });
    } catch (e) {
      debugPrint('[EXPENSE_REPO] Firestore approved watch failed: $e, falling back to local');
      yield getLocalExpenses(tourId).where((e) => e.isApproved).toList();
    }
  }

  Stream<ExpenseModel?> watchExpense(String tourId, String expenseId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalExpense(tourId, expenseId);
      if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
        final box = Hive.box(OfflineExpenseQueueService.boxName);
        await for (final _ in box.watch()) {
          yield getLocalExpense(tourId, expenseId);
        }
      }
      return;
    }

    final local = getLocalExpense(tourId, expenseId);
    if (local != null) yield local;

    try {
      yield* _expenses(tourId)
          .doc(expenseId)
          .snapshots()
          .map((doc) => doc.exists
              ? ExpenseModel.fromFirestore(doc)
              : getLocalExpense(tourId, expenseId));
    } catch (_) {
      yield getLocalExpense(tourId, expenseId);
    }
  }

  Future<ExpenseModel?> getExpense(String tourId, String expenseId) async {
    final local = getLocalExpense(tourId, expenseId);
    if (local != null) return local;
    try {
      final doc = await _expenses(tourId).doc(expenseId).get();
      return doc.exists ? ExpenseModel.fromFirestore(doc) : null;
    } catch (_) {
      return null;
    }
  }

  Stream<List<ExpenseModel>> watchPendingExpenses(String tourId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalExpenses(tourId).where((e) => !e.isApproved).toList();
      if (Hive.isBoxOpen(OfflineExpenseQueueService.boxName)) {
        final box = Hive.box(OfflineExpenseQueueService.boxName);
        await for (final _ in box.watch()) {
          yield getLocalExpenses(tourId).where((e) => !e.isApproved).toList();
        }
      }
      return;
    }

    yield* _expenses(tourId)
        .where('status', isEqualTo: 'pending_approval')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }
}

final expenseRepositoryProvider =
    Provider<ExpenseRepository>((_) => ExpenseRepository());

final tourExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchExpenses(tourId);
});

final approvedExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchApprovedExpenses(tourId);
});

final pendingExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchPendingExpenses(tourId);
});

final singleExpenseStreamProvider =
    StreamProvider.family<ExpenseModel?, ({String tourId, String expenseId})>(
        (ref, arg) {
  return ref
      .watch(expenseRepositoryProvider)
      .watchExpense(arg.tourId, arg.expenseId);
});
