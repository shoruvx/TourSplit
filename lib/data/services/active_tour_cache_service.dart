import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tour_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

class ActiveTourCacheService {
  static const String boxName = 'active_tour_cache';

  static Box get _box => Hive.box(boxName);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
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

  /// Cache only the latest active tour data to save ROM storage
  static Future<void> cacheActiveTour({
    required TourModel tour,
    List<TourMemberModel>? members,
    List<ExpenseModel>? expenses,
  }) async {
    try {
      await init();
      await _box.put('active_tour_id', tour.id);
      await _box.put('active_tour_data', _sanitizeForHive(tour.toFirestore()));

      if (members != null && members.isNotEmpty) {
        // Preserve any offline-queued members already in cache that aren't in the
        // incoming stream list — they haven't synced to Firestore yet so the stream
        // won't know about them. Without this, the postFrameCallback overwrites them.
        final key = 'active_tour_members_${tour.id}';
        final existing = _box.get(key);
        final existingOfflineExtras = <Map<String, dynamic>>[];
        if (existing is List) {
          for (final item in existing) {
            if (item is Map) {
              final m = Map<String, dynamic>.from(item);
              final uid = m['userId'] as String? ?? '';
              // Keep offline-queued members not yet in the incoming stream list
              if (uid.startsWith('offline_') && !members.any((nm) => nm.userId == uid)) {
                existingOfflineExtras.add(m);
              }
            }
          }
        }
        final memberMaps = members.map((m) => _sanitizeForHive(m.toFirestore())).toList();
        memberMaps.addAll(existingOfflineExtras);
        await _box.put(key, memberMaps);
      }

      if (expenses != null) {
        // Cache up to 100 most recent expenses to keep memory and storage footprint tiny
        final recent = expenses.take(100).map((e) {
          final map = _sanitizeForHive(e.toFirestore());
          map['id'] = e.id;
          return map;
        }).toList();
        await _box.put('active_tour_expenses_${tour.id}', recent);
      }

      // Automatically prune stale cache from previous tours to keep storage footprint minimal
      await pruneStaleToursCache(tour.id);
    } catch (e) {
      debugPrint('[CACHE] Error caching active tour: $e');
    }
  }

  static Future<void> setActiveTourId(String? tourId) async {
    try {
      await init();
      if (tourId == null || tourId.isEmpty) {
        await _box.delete('active_tour_id');
      } else {
        await _box.put('active_tour_id', tourId);
      }
    } catch (e) {
      debugPrint('[CACHE] Error setting active tour ID: $e');
    }
  }

  /// Clears only the active tour pointer from Hive, preserving cached tour data, members, and expenses.
  static Future<void> clearActiveTourId() async {
    try {
      await init();
      await _box.delete('active_tour_id');
      await pruneStaleToursCache(null);
      debugPrint('[CACHE] Cleared active tour pointer and pruned stale tour data');
    } catch (e) {
      debugPrint('[CACHE] Error clearing active tour ID: $e');
    }
  }

  static String? getActiveTourId() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box.get('active_tour_id') as String?;
  }

  static TourModel? getCachedActiveTour() {
    if (!Hive.isBoxOpen(boxName)) return null;
    final map = _box.get('active_tour_data');
    final id = _box.get('active_tour_id') as String?;
    if (map is Map && id != null) {
      try {
        final stringMap = Map<String, dynamic>.from(map);
        return TourModel.fromMap(stringMap, id);
      } catch (e) {
        debugPrint('[CACHE] Error reading cached tour: $e');
      }
    }
    return null;
  }

  static List<TourMemberModel> getCachedMembers(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = _box.get('active_tour_members_$tourId');
    if (list is List) {
      try {
        return list
            .map((item) {
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);
                final uid = map['userId'] as String? ?? '';
                final isOffline =
                    map['isOffline'] == true || uid.startsWith('offline_');
                return TourMemberModel(
                  userId: uid,
                  displayName: map['displayName'] as String? ?? 'Member',
                  username: map['username'] as String? ?? '',
                  email: map['email'] as String? ?? '',
                  photoUrl: map['photoUrl'] as String?,
                  role: map['role'] as String? ?? 'member',
                  status: map['status'] as String? ?? 'active',
                  joinedAt: DateTime.now(),
                  balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
                  isOffline: isOffline,
                );
              }
              return null;
            })
            .whereType<TourMemberModel>()
            .toList();
      } catch (e) {
        debugPrint('[CACHE] Error reading cached members: $e');
      }
    }
    return [];
  }

  static List<ExpenseModel> getCachedExpenses(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = _box.get('active_tour_expenses_$tourId');
    if (list is List) {
      try {
        return list
            .map((item) {
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);
                final id = map['id'] as String? ?? '';
                return ExpenseModel.fromMap(map, id);
              }
              return null;
            })
            .whereType<ExpenseModel>()
            .toList();
      } catch (e) {
        debugPrint('[CACHE] Error reading cached expenses: $e');
      }
    }
    return [];
  }

  /// Appends or updates a single expense in the cached expenses list for a tour.
  static Future<void> appendCachedExpense(String tourId, ExpenseModel expense) async {
    try {
      await init();
      final key = 'active_tour_expenses_$tourId';
      final existing = _box.get(key);
      final List<dynamic> list = existing is List ? List.from(existing) : [];

      list.removeWhere((item) {
        if (item is Map) {
          return (item['id'] as String?) == expense.id;
        }
        return false;
      });

      final map = _sanitizeForHive(expense.toFirestore());
      map['id'] = expense.id;
      list.insert(0, map);
      if (list.length > 100) list.removeLast();
      await _box.put(key, list);
      debugPrint('[CACHE] Appended/updated cached expense "${expense.title}" (${expense.id}) for tour $tourId');
    } catch (e) {
      debugPrint('[CACHE] Error appending cached expense: $e');
    }
  }

  /// Removes an expense from the cached expenses list for a tour.
  static Future<void> removeCachedExpense(String tourId, String expenseId) async {
    try {
      await init();
      final key = 'active_tour_expenses_$tourId';
      final existing = _box.get(key);
      if (existing is List) {
        final List<dynamic> list = List.from(existing);
        final initialLen = list.length;
        list.removeWhere((item) {
          if (item is Map) {
            return (item['id'] as String?) == expenseId;
          }
          return false;
        });
        if (list.length != initialLen) {
          await _box.put(key, list);
          debugPrint('[CACHE] Removed cached expense $expenseId for tour $tourId');
        }
      }
    } catch (e) {
      debugPrint('[CACHE] Error removing cached expense: $e');
    }
  }

  /// Appends a single member to the cached members list for a tour.
  /// Used to immediately reflect offline-added members in the UI without a Firestore round-trip.
  static Future<void> appendCachedMember(String tourId, TourMemberModel member) async {
    try {
      await init();
      final key = 'active_tour_members_$tourId';
      final existing = _box.get(key);
      final List<dynamic> list = existing is List ? List.from(existing) : [];

      // Avoid duplicates
      list.removeWhere((item) {
        if (item is Map) {
          return (item['userId'] as String?) == member.userId;
        }
        return false;
      });

      final memberMap = _sanitizeForHive({
        'userId': member.userId,
        'displayName': member.displayName,
        'username': member.username,
        'email': member.email,
        'photoUrl': member.photoUrl,
        'role': member.role,
        'status': member.status,
        'isOffline': member.isOffline,
        'balance': member.balance,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
      });

      list.add(memberMap);
      await _box.put(key, list);
      debugPrint('[CACHE] Appended member "${member.displayName}" (${member.userId}) for tour $tourId');
    } catch (e) {
      debugPrint('[CACHE] Error appending cached member: $e');
    }
  }

  /// Clears the cached active tour, its members, and expenses from Hive
  static Future<void> clearCachedActiveTour() async {
    try {
      await init();
      final id = _box.get('active_tour_id') as String?;
      await _box.delete('active_tour_id');
      await _box.delete('active_tour_data');
      if (id != null) {
        await _box.delete('active_tour_members_$id');
        await _box.delete('active_tour_expenses_$id');
      }
      debugPrint('[CACHE] Cleared cached active tour ($id)');
      await pruneStaleToursCache(null);
    } catch (e) {
      debugPrint('[CACHE] Error clearing cached active tour: $e');
    }
  }

  /// Prunes cached members, expenses, and settlements for all tours except [activeTourId].
  /// When [activeTourId] is null, prunes all lingering tour members, expenses, and settlements.
  static Future<void> pruneStaleToursCache([String? activeTourId]) async {
    try {
      await init();
      final currentActive = activeTourId ?? getActiveTourId();
      final keys = List.from(_box.keys);
      for (final key in keys) {
        final keyStr = key.toString();
        if (keyStr.startsWith('active_tour_members_')) {
          if (currentActive == null || keyStr != 'active_tour_members_$currentActive') {
            await _box.delete(key);
            debugPrint('[CACHE] Pruned stale cached members: $keyStr');
          }
        } else if (keyStr.startsWith('active_tour_expenses_')) {
          if (currentActive == null || keyStr != 'active_tour_expenses_$currentActive') {
            await _box.delete(key);
            debugPrint('[CACHE] Pruned stale cached expenses: $keyStr');
          }
        } else if (keyStr.startsWith('active_tour_settlements_')) {
          if (currentActive == null || keyStr != 'active_tour_settlements_$currentActive') {
            await _box.delete(key);
            debugPrint('[CACHE] Pruned stale cached settlements: $keyStr');
          }
        }
      }
    } catch (e) {
      debugPrint('[CACHE] Error pruning stale tours cache: $e');
    }
  }

  /// Reassigns cached tour data from [oldTourId] (e.g. local_...) to [newTourId] (Firestore ID).
  static Future<void> reassignTourId(String oldTourId, String newTourId) async {
    try {
      await init();
      final activeId = getActiveTourId();
      if (activeId == oldTourId) {
        await _box.put('active_tour_id', newTourId);
      }
      final membersKey = 'active_tour_members_$oldTourId';
      if (_box.containsKey(membersKey)) {
        final members = _box.get(membersKey);
        await _box.put('active_tour_members_$newTourId', members);
        await _box.delete(membersKey);
      }
      final expensesKey = 'active_tour_expenses_$oldTourId';
      if (_box.containsKey(expensesKey)) {
        final expenses = _box.get(expensesKey);
        await _box.put('active_tour_expenses_$newTourId', expenses);
        await _box.delete(expensesKey);
      }
      final settlementsKey = 'active_tour_settlements_$oldTourId';
      if (_box.containsKey(settlementsKey)) {
        final settlements = _box.get(settlementsKey);
        await _box.put('active_tour_settlements_$newTourId', settlements);
        await _box.delete(settlementsKey);
      }
      await pruneStaleToursCache(newTourId);
      debugPrint('[CACHE] Reassigned cached tour data: $oldTourId -> $newTourId');
    } catch (e) {
      debugPrint('[CACHE] Error reassigning tour ID: $e');
    }
  }

  /// Gets cached approved settlements for [tourId]
  static List<SettlementModel> getCachedSettlements(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = _box.get('active_tour_settlements_$tourId');
    if (list is List) {
      try {
        return list
            .map((item) {
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);
                final id = map['id'] as String? ?? '';
                return SettlementModel.fromMap(map, id);
              }
              return null;
            })
            .whereType<SettlementModel>()
            .toList();
      } catch (e) {
        debugPrint('[CACHE] Error reading cached settlements: $e');
      }
    }
    return [];
  }

  /// Caches approved settlements for [tourId]
  static Future<void> cacheSettlements(String tourId, List<SettlementModel> settlements) async {
    try {
      await init();
      final key = 'active_tour_settlements_$tourId';
      final list = settlements.take(50).map((s) {
        final map = _sanitizeForHive(s.toFirestore());
        map['id'] = s.id;
        return map;
      }).toList();
      await _box.put(key, list);
    } catch (e) {
      debugPrint('[CACHE] Error caching settlements: $e');
    }
  }

  /// Appends a single settlement to the cached settlements list
  static Future<void> appendCachedSettlement(String tourId, SettlementModel settlement) async {
    try {
      await init();
      final key = 'active_tour_settlements_$tourId';
      final existing = _box.get(key);
      final List<dynamic> list = existing is List ? List.from(existing) : [];

      list.removeWhere((item) {
        if (item is Map) return (item['id'] as String?) == settlement.id;
        return false;
      });

      final map = _sanitizeForHive(settlement.toFirestore());
      map['id'] = settlement.id;
      list.insert(0, map);
      await _box.put(key, list);
      debugPrint('[CACHE] Appended cached settlement "${settlement.id}" for tour $tourId');
    } catch (e) {
      debugPrint('[CACHE] Error appending cached settlement: $e');
    }
  }
}
