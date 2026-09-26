import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/tour_model.dart';
import '../repositories/tour_repository.dart';
import '../services/auth_service.dart';
import '../../core/constants/app_constants.dart';
import 'active_tour_cache_service.dart';
import 'offline_expense_queue_service.dart';

final offlineTourQueueProvider = Provider<OfflineTourQueueService>((ref) {
  final service = OfflineTourQueueService(
    tourRepo: ref.watch(tourRepositoryProvider),
    ref: ref,
    connectivity: Connectivity(),
  );
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});

class OfflineTourQueueService {
  static const String boxName = 'offline_tours_queue';
  static const String localToursBox = 'local_tours';

  final TourRepository? _tourRepo;
  final Ref? _ref;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  OfflineTourQueueService({
    TourRepository? tourRepo,
    Ref? ref,
    Connectivity? connectivity,
  })  : _tourRepo = tourRepo,
        _ref = ref,
        _connectivity = connectivity ?? Connectivity();

  static Box get _queueBox => Hive.box(boxName);
  static Box get _localBox => Hive.box(localToursBox);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
    if (!Hive.isBoxOpen(localToursBox)) {
      await Hive.openBox(localToursBox);
    }
  }

  void initialize() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet) {
        syncQueuedOperations();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  // ─── Local Tour CRUD ──────────────────────────────────────────────────────

  Future<TourModel> createTourLocally({
    required String name,
    required String currency,
    required String currencySymbol,
    required String adminId,
    required DateTime startDate,
    required DateTime endDate,
    String? adminName,
    String? adminEmail,
  }) async {
    await init();

    final localId = 'local_${const Uuid().v4()}';
    final inviteCode = _generateInviteCode();

    final tourMap = <String, dynamic>{
      'id': localId,
      'name': name,
      'currency': currency,
      'currencySymbol': currencySymbol,
      'adminId': adminId,
      'inviteCode': inviteCode,
      'status': 'active',
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
      'members': [adminId],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'isLocalOnly': true,
    };

    await _localBox.put(localId, tourMap);

    // Save admin as an active member in the local tour
    final memberMap = <String, dynamic>{
      'userId': adminId,
      'tourId': localId,
      'displayName': (adminName != null && adminName.isNotEmpty) ? adminName : 'Admin',
      'email': adminEmail ?? '',
      'role': 'admin',
      'status': 'active',
      'joinedAt': DateTime.now().millisecondsSinceEpoch,
      'isOffline': false,
    };
    await _localBox.put('member_${localId}_$adminId', memberMap);

    await _queueBox.put('create_$localId', {
      'type': 'createTour',
      'localId': localId,
      'data': tourMap,
      'queuedAt': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('[OFFLINE_TOUR_QUEUE] Created local tour: $name ($localId)');

    return TourModel(
      id: localId,
      name: name,
      description: null,
      currency: currency,
      currencySymbol: currencySymbol,
      adminId: adminId,
      inviteCode: inviteCode,
      status: TourStatus.active,
      startDate: startDate,
      endDate: endDate,
      memberIds: [adminId],
      createdAt: DateTime.now(),
    );
  }

  bool isLocalTour(String tourId) => tourId.startsWith('local_');

  Map<String, dynamic>? getLocalTour(String localId) {
    if (!Hive.isBoxOpen(localToursBox)) return null;
    final val = _localBox.get(localId);
    if (val is Map) return Map<String, dynamic>.from(val);
    return null;
  }

  /// Deletes a local tour and all associated queued members and expenses completely without internet.
  Future<void> deleteLocalTour(String localTourId) async {
    await init();
    if (Hive.isBoxOpen(localToursBox)) {
      await _localBox.delete(localTourId);
      final memberKeys = _localBox.keys
          .where((k) => k.toString().startsWith('member_${localTourId}_'))
          .toList();
      for (final k in memberKeys) {
        await _localBox.delete(k);
      }
    }

    if (Hive.isBoxOpen(boxName)) {
      await _queueBox.delete('create_$localTourId');
      final queueKeys = _queueBox.keys
          .where((k) => k.toString().startsWith('addMember_${localTourId}_'))
          .toList();
      for (final k in queueKeys) {
        await _queueBox.delete(k);
      }
    }

    try {
      if (Hive.isBoxOpen('offline_expenses_queue')) {
        final expBox = Hive.box('offline_expenses_queue');
        final expKeys = expBox.keys.where((k) {
          final val = expBox.get(k);
          return val is Map && val['tourId'] == localTourId;
        }).toList();
        for (final k in expKeys) {
          await expBox.delete(k);
        }
      }
    } catch (_) {}

    if (ActiveTourCacheService.getActiveTourId() == localTourId) {
      await ActiveTourCacheService.clearCachedActiveTour();
    }
    debugPrint('[OFFLINE_TOUR_QUEUE] Deleted local tour: $localTourId');
  }

  /// Queues an online tour for deletion when internet connection is restored.
  Future<void> queueTourDeletion({
    required String tourId,
    String? currentUserId,
  }) async {
    await init();
    await _queueBox.put('delete_$tourId', {
      'type': 'deleteTour',
      'tourId': tourId,
      'currentUserId': currentUserId,
      'queuedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (ActiveTourCacheService.getActiveTourId() == tourId) {
      await ActiveTourCacheService.clearCachedActiveTour();
    }
    debugPrint('[OFFLINE_TOUR_QUEUE] Queued online tour deletion for sync: $tourId');
  }

  /// Returns tour IDs that have been queued for deletion offline so they can be hidden from UI immediately.
  Set<String> getQueuedDeletedTourIds() {
    if (!Hive.isBoxOpen(boxName)) return {};
    final deletedIds = <String>{};
    for (final key in _queueBox.keys) {
      final val = _queueBox.get(key);
      if (val is Map && val['type'] == 'deleteTour') {
        final id = val['tourId'] as String?;
        if (id != null) deletedIds.add(id);
      }
    }
    return deletedIds;
  }

  // ─── Offline Member Ops ───────────────────────────────────────────────────

  /// Returns all offline members queued for a specific tour.
  /// Used as a last-resort fallback to show proper names even when stream and cache are both empty.
  List<TourMemberModel> getQueuedMembersForTour(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = <TourMemberModel>[];
    for (final key in _queueBox.keys) {
      final val = _queueBox.get(key);
      if (val is Map) {
        final op = Map<String, dynamic>.from(val);
        if (op['type'] == 'addOfflineMember' && op['tourId'] == tourId) {
          final data = op['data'];
          if (data is Map) {
            final m = Map<String, dynamic>.from(data);
            list.add(TourMemberModel(
              userId: m['userId'] as String? ?? '',
              displayName: m['displayName'] as String? ?? 'Offline Friend',
              email: '',
              photoUrl: null,
              role: 'member',
              isOffline: true,
              joinedAt: DateTime.now(),
              balance: 0.0,
            ));
          }
        }
      }
    }
    return list;
  }


  Future<TourMemberModel> addOfflineMemberLocally({
    required String tourId,
    required String name,
  }) async {
    await init();

    final memberId = 'offline_${const Uuid().v4()}';
    final memberMap = <String, dynamic>{
      'userId': memberId,
      'displayName': name.trim(),
      'email': '',
      'photoUrl': null,
      'role': 'member',
      'isOffline': true,
      'joinedAt': DateTime.now().millisecondsSinceEpoch,
      'balance': 0.0,
    };

    final member = TourMemberModel(
      userId: memberId,
      displayName: name.trim(),
      email: '',
      photoUrl: null,
      role: 'member',
      isOffline: true,
      joinedAt: DateTime.now(),
      balance: 0.0,
    );

    // Immediately update the UI-visible cache so getCachedMembers() returns this member right away
    await ActiveTourCacheService.appendCachedMember(tourId, member);

    if (isLocalTour(tourId)) {
      final tourData = getLocalTour(tourId);
      if (tourData != null) {
        final members = List<dynamic>.from(tourData['members'] as List? ?? []);
        members.add(memberId);
        tourData['members'] = members;
        await _localBox.put(tourId, tourData);
      }
      await _localBox.put('member_${tourId}_$memberId', memberMap);
    }

    await _queueBox.put('addMember_${tourId}_$memberId', {
      'type': 'addOfflineMember',
      'tourId': tourId,
      'memberId': memberId,
      'data': memberMap,
      'queuedAt': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('[OFFLINE_TOUR_QUEUE] Queued offline member: $name ($memberId) for tour $tourId');

    return member;
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  Future<int> syncQueuedOperations() async {
    if (_isSyncing) return 0;
    if (!Hive.isBoxOpen(boxName) || _queueBox.isEmpty) return 0;

    _isSyncing = true;
    int syncedCount = 0;

    debugPrint('[OFFLINE_TOUR_QUEUE] Starting sync for ${_queueBox.length} operation(s)...');

    try {
      if (_ref == null || _tourRepo == null) return 0;
      final user = _ref.read(currentUserProvider).value;
      if (user == null) return 0;

      final entries = <String, Map<String, dynamic>>{};
      for (final key in _queueBox.keys) {
        final val = _queueBox.get(key);
        if (val is Map) {
          entries[key.toString()] = Map<String, dynamic>.from(val);
        }
      }
      final sorted = entries.entries.toList()
        ..sort((a, b) {
          final at = (a.value['queuedAt'] as int?) ?? 0;
          final bt = (b.value['queuedAt'] as int?) ?? 0;
          return at.compareTo(bt);
        });

      final localIdToReal = <String, String>{};

      for (final entry in sorted) {
        final key = entry.key;
        final op = entry.value;
        final type = op['type'] as String?;

        try {
          if (type == 'createTour') {
            final localId = op['localId'] as String;
            final data = Map<String, dynamic>.from(op['data'] as Map);

            final startMs = data['startDate'] as int;
            final endMs = data['endDate'] as int;

            final tour = await _tourRepo.createTour(
              name: data['name'] as String,
              currency: data['currency'] as String,
              currencySymbol: data['currencySymbol'] as String,
              adminId: user.uid,
              startDate: DateTime.fromMillisecondsSinceEpoch(startMs),
              endDate: DateTime.fromMillisecondsSinceEpoch(endMs),
            );

            await _tourRepo.addAdminAsMember(tourId: tour.id, admin: user);
            localIdToReal[localId] = tour.id;

            if (Hive.isBoxOpen(localToursBox)) {
              await _localBox.delete(localId);
              final memberKeys = _localBox.keys
                  .where((k) => k.toString().startsWith('member_${localId}_'))
                  .toList();
              for (final k in memberKeys) {
                await _localBox.delete(k);
              }
            }

            // 1. Reassign active tour cache from local ID to real Firestore ID
            await ActiveTourCacheService.reassignTourId(localId, tour.id);
            await ActiveTourCacheService.cacheActiveTour(tour: tour);

            // 2. Remap queued offline expenses to the new real tour ID
            await OfflineExpenseQueueService().remapTourId(localId, tour.id);

            // 3. Update Riverpod active tour override if this tour is currently open
            if (_ref.read(activeTourIdOverrideProvider) == localId) {
              _ref.read(activeTourIdOverrideProvider.notifier).state = tour.id;
            }

            // 4. Trigger immediate sync of all queued expenses for this newly created tour
            unawaited(OfflineExpenseQueueService().syncQueuedExpenses());

            debugPrint('[OFFLINE_TOUR_QUEUE] Synced local tour "$localId" -> "${tour.id}"');
            await _queueBox.delete(key);
            syncedCount++;
          } else if (type == 'addOfflineMember') {
            var tourId = op['tourId'] as String;
            final memberId = op['memberId'] as String;
            final data = Map<String, dynamic>.from(op['data'] as Map);

            if (localIdToReal.containsKey(tourId)) {
              tourId = localIdToReal[tourId]!;
            }

            if (tourId.startsWith('local_')) {
              debugPrint('[OFFLINE_TOUR_QUEUE] Skipping member for un-synced tour $tourId');
              continue;
            }

            await FirebaseFirestore.instance
                .collection(AppConstants.toursCollection)
                .doc(tourId)
                .collection(AppConstants.membersSubcollection)
                .doc(memberId)
                .set({
              'userId': memberId,
              'displayName': data['displayName'],
              'email': '',
              'photoUrl': null,
              'role': 'member',
              'isOffline': true,
              'joinedAt': FieldValue.serverTimestamp(),
              'balance': 0.0,
            }, SetOptions(merge: true));

            await FirebaseFirestore.instance
                .collection(AppConstants.toursCollection)
                .doc(tourId)
                .update({
              'members': FieldValue.arrayUnion([memberId]),
            });

            if (Hive.isBoxOpen(localToursBox)) {
              await _localBox.delete('member_${tourId}_$memberId');
            }

            debugPrint('[OFFLINE_TOUR_QUEUE] Synced offline member ${data['displayName']} to tour $tourId');
            await _queueBox.delete(key);
            syncedCount++;
          } else if (type == 'deleteTour') {
            final tourId = op['tourId'] as String;
            final currentUserId = op['currentUserId'] as String?;
            await _tourRepo.deleteTour(tourId, currentUserId: currentUserId);
            debugPrint('[OFFLINE_TOUR_QUEUE] Synced offline tour deletion: $tourId');
            await _queueBox.delete(key);
            syncedCount++;
          }
        } catch (e) {
          debugPrint('[OFFLINE_TOUR_QUEUE] Failed to sync op "$key": $e');
        }
      }
    } finally {
      _isSyncing = false;
    }

    if (syncedCount > 0) {
      debugPrint('[OFFLINE_TOUR_QUEUE] Sync complete: $syncedCount op(s)');
    }
    return syncedCount;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var seed = DateTime.now().millisecondsSinceEpoch;
    final buf = StringBuffer();
    for (int i = 0; i < 8; i++) {
      seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
      buf.write(chars[seed % chars.length]);
    }
    return buf.toString();
  }

  /// Prunes any orphaned member entries from local_tours box where the parent tour no longer exists
  static Future<void> pruneOrphanedLocalData() async {
    try {
      await init();
      if (Hive.isBoxOpen(localToursBox)) {
        final box = Hive.box(localToursBox);
        final keys = List.from(box.keys);
        final tourIds = keys
            .where((k) => !k.toString().startsWith('member_'))
            .map((k) => k.toString())
            .toSet();

        for (final k in keys) {
          final str = k.toString();
          if (str.startsWith('member_')) {
            final hasParentTour = tourIds.any((tId) => str.startsWith('member_${tId}_'));
            if (!hasParentTour) {
              await box.delete(k);
              debugPrint('[OFFLINE_TOUR_QUEUE] Pruned orphaned local member key: $k');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[OFFLINE_TOUR_QUEUE] Error pruning orphaned local data: $e');
    }
  }
}
