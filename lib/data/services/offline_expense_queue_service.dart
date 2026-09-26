import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';
import '../repositories/expense_repository.dart';
import 'active_tour_cache_service.dart';

class LocalExpensesRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final localExpensesRefreshProvider =
    NotifierProvider<LocalExpensesRefreshNotifier, int>(
        LocalExpensesRefreshNotifier.new);

final offlineExpenseQueueProvider =
    Provider<OfflineExpenseQueueService>((ref) {
  final service = OfflineExpenseQueueService(
    expenseRepo: ref.watch(expenseRepositoryProvider),
    connectivity: Connectivity(),
  );
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});

class OfflineExpenseQueueService {
  static const String boxName = 'offline_expenses_queue';
  final ExpenseRepository _expenseRepo;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  OfflineExpenseQueueService({
    ExpenseRepository? expenseRepo,
    Connectivity? connectivity,
  })  : _expenseRepo = expenseRepo ?? ExpenseRepository(),
        _connectivity = connectivity ?? Connectivity();

  static Box get _box => Hive.box(boxName);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
  }

  void initialize() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet) {
        syncQueuedExpenses();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  static dynamic _sanitizeValue(dynamic val) {
    if (val is Timestamp) return val.millisecondsSinceEpoch;
    if (val is DateTime) return val.millisecondsSinceEpoch;
    if (val is Map) return _sanitizeForHive(Map<String, dynamic>.from(val));
    if (val is List) return val.map(_sanitizeValue).toList();
    return val;
  }

  static Map<String, dynamic> _sanitizeForHive(Map<String, dynamic> map) {
    return map.map((k, v) => MapEntry(k, _sanitizeValue(v)));
  }

  /// Queue an expense created offline
  Future<void> queueExpense(ExpenseModel expense) async {
    try {
      await init();
      // Remove any pending deletion for this expense
      await _box.delete('del_${expense.id}');

      final map = _sanitizeForHive(expense.toFirestore());
      map['id'] = expense.id;
      map['localCreatedAt'] = expense.createdAt.millisecondsSinceEpoch;
      await _box.put(expense.id, map);

      // Immediately cache it so getCachedExpenses returns it
      await ActiveTourCacheService.appendCachedExpense(expense.tourId, expense);
      debugPrint('[OFFLINE_QUEUE] Queued expense: ${expense.title} (${expense.id})');
    } catch (e) {
      debugPrint('[OFFLINE_QUEUE] Error queueing expense: $e');
    }
  }

  /// Delete a queued expense locally
  Future<void> deleteQueuedExpense(String expenseId) async {
    try {
      await init();
      if (_box.containsKey(expenseId)) {
        await _box.delete(expenseId);
        debugPrint('[OFFLINE_QUEUE] Deleted queued expense: $expenseId');
      }
    } catch (e) {
      debugPrint('[OFFLINE_QUEUE] Error deleting queued expense: $e');
    }
  }

  /// Queue an expense for deletion when back online, or remove it from local queue immediately
  Future<void> queueExpenseDeletion(String tourId, String expenseId) async {
    try {
      await init();
      // 1. If it exists in local offline queue, remove it directly
      if (_box.containsKey(expenseId)) {
        await _box.delete(expenseId);
        debugPrint('[OFFLINE_QUEUE] Removed local-queued expense $expenseId');
      } else if (!tourId.startsWith('local_')) {
        // 2. If it's an online tour expense, queue deletion for sync
        await _box.put('del_$expenseId', {
          'type': 'deleteExpense',
          'tourId': tourId,
          'expenseId': expenseId,
          'queuedAt': DateTime.now().millisecondsSinceEpoch,
        });
        debugPrint('[OFFLINE_QUEUE] Queued online expense deletion for sync: $expenseId');
      }
      // 3. Remove from ActiveTourCacheService as well
      await ActiveTourCacheService.removeCachedExpense(tourId, expenseId);
    } catch (e) {
      debugPrint('[OFFLINE_QUEUE] Error queueing expense deletion: $e');
    }
  }

  /// Remaps all queued expenses and deletion requests from [oldTourId] to [newTourId]
  /// when a local tour is synced to Firestore.
  Future<void> remapTourId(String oldTourId, String newTourId) async {
    try {
      await init();
      final keys = List.from(_box.keys);
      for (final key in keys) {
        final val = _box.get(key);
        if (val is Map) {
          final map = Map<String, dynamic>.from(val);
          if (map['tourId'] == oldTourId) {
            map['tourId'] = newTourId;
            await _box.put(key, map);
            debugPrint('[OFFLINE_QUEUE] Remapped expense $key from $oldTourId -> $newTourId');
          }
        }
      }
    } catch (e) {
      debugPrint('[OFFLINE_QUEUE] Error remapping tour ID in offline expenses: $e');
    }
  }

  /// Returns set of expense IDs that have been queued for deletion
  Set<String> getQueuedDeletedExpenseIds({String? tourId}) {
    if (!Hive.isBoxOpen(boxName)) return {};
    final deleted = <String>{};
    for (final key in _box.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith('del_')) {
        final val = _box.get(key);
        if (val is Map) {
          final tId = val['tourId'] as String?;
          final expId = val['expenseId'] as String? ?? keyStr.substring(4);
          if (tourId == null || tId == tourId) {
            deleted.add(expId);
          }
        } else {
          deleted.add(keyStr.substring(4));
        }
      }
    }
    return deleted;
  }

  /// Get list of all queued offline expenses, optionally filtered by tour
  List<ExpenseModel> getQueuedExpenses({String? tourId}) {
    if (!Hive.isBoxOpen(boxName)) return [];
    try {
      final list = <ExpenseModel>[];
      for (final key in _box.keys) {
        final keyStr = key.toString();
        if (keyStr.startsWith('del_')) continue;
        final val = _box.get(key);
        if (val is Map) {
          final map = Map<String, dynamic>.from(val);
          if (map['type'] == 'deleteExpense') continue;
          final id = key.toString();
          if (tourId == null || map['tourId'] == tourId) {
            final exp = ExpenseModel.fromMap(map, id);
            list.add(exp);
          }
        }
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      debugPrint('[OFFLINE_QUEUE] Error reading queued expenses: $e');
      return [];
    }
  }

  /// Sync all queued expenses and deletions to Firestore once back online
  Future<int> syncQueuedExpenses() async {
    if (_isSyncing) return 0;
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return 0;

    _isSyncing = true;
    int syncedCount = 0;
    debugPrint('[OFFLINE_QUEUE] Starting sync for ${_box.length} offline operation(s)...');

    try {
      final keys = List.from(_box.keys);
      for (final key in keys) {
        final val = _box.get(key);
        if (val is Map) {
          final map = Map<String, dynamic>.from(val);
          if (map['type'] == 'deleteExpense') {
            final tId = map['tourId'] as String? ?? '';
            final expId = map['expenseId'] as String? ?? key.toString().replaceFirst('del_', '');
            try {
              if (tId.isNotEmpty && expId.isNotEmpty && !tId.startsWith('local_')) {
                await _expenseRepo.deleteExpense(tId, expId);
              }
              await _box.delete(key);
              syncedCount++;
              debugPrint('[OFFLINE_QUEUE] Synced expense deletion ($expId)');
            } catch (e) {
              debugPrint('[OFFLINE_QUEUE] Failed to sync expense deletion $expId: $e');
            }
            continue;
          }

          final id = key.toString();
          final expense = ExpenseModel.fromMap(map, id);

          try {
            await _expenseRepo.addExpense(expense);
            await _box.delete(key);
            syncedCount++;
            debugPrint('[OFFLINE_QUEUE] Synced expense ${expense.title} ($id)');
          } catch (e) {
            debugPrint('[OFFLINE_QUEUE] Failed to sync expense $id: $e');
          }
        }
      }
    } finally {
      _isSyncing = false;
    }

    if (syncedCount > 0) {
      debugPrint('[OFFLINE_QUEUE] Completed sync: $syncedCount operation(s) synced');
    }
    return syncedCount;
  }
}
