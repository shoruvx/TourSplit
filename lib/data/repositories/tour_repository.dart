import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tour_model.dart';
import '../models/user_model.dart';
import '../services/user_cache_service.dart';
import '../services/active_tour_cache_service.dart';
import '../services/offline_tour_queue_service.dart';
import '../services/auth_service.dart' show currentUserProvider;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/constants/app_constants.dart';

class TourRepository {
  final FirebaseFirestore? _customDb;
  final FirebaseAuth? _customAuth;

  TourRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _customDb = firestore,
        _customAuth = auth;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  CollectionReference get _tours =>
      _db.collection(AppConstants.toursCollection);

  CollectionReference get _users =>
      _db.collection(AppConstants.usersCollection);

  Future<TourModel> createTour({
    required String name,
    String? description,
    required String currency,
    required String currencySymbol,
    required String adminId,
    required DateTime startDate,
    DateTime? endDate,
    double? budget,
    String? coverImageUrl,
  }) async {
    final inviteCode = _generateInviteCode();

    final tourData = {
      'name': name,
      'description': description,
      'currency': currency,
      'currencySymbol': currencySymbol,
      'adminId': adminId,
      'inviteCode': inviteCode,
      'status': 'active',
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
      'budget': budget,
      'coverImageUrl': coverImageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'members': [adminId],
    };

    final docRef = await _tours.add(tourData);
    final doc = await docRef.get();
    final tour = TourModel.fromFirestore(doc);

    await _db
        .collection(AppConstants.usersCollection)
        .doc(adminId)
        .update({'activeTourId': docRef.id});

    return tour;
  }

  Future<TourModel?> getTourByInviteCode(String code) async {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');
    if (clean.isEmpty) return null;

    final candidates = <String>[clean];

    if (clean.contains('0')) candidates.add(clean.replaceAll('0', 'O'));
    if (clean.contains('O')) candidates.add(clean.replaceAll('O', '0'));

    if (clean.contains('1')) candidates.add(clean.replaceAll('1', 'I'));
    if (clean.contains('I')) candidates.add(clean.replaceAll('I', '1'));

    debugPrint(
        '[INVITE_DEBUG] Searching for clean: "$clean", candidates: $candidates');
    for (final candidate in candidates) {
      try {
        final query = await _tours
            .where('inviteCode', isEqualTo: candidate)
            .limit(1)
            .get();

        debugPrint(
            '[INVITE_DEBUG] Candidate "$candidate" found ${query.docs.length} docs');
        if (query.docs.isNotEmpty) {
          final tour = TourModel.fromFirestore(query.docs.first);
          debugPrint(
              '[INVITE_DEBUG] Tour: "${tour.name}", code: "${tour.inviteCode}", status: "${tour.status}"');
          return tour;
        }
      } catch (e, st) {
        debugPrint('[INVITE_DEBUG] ERROR querying candidate "$candidate": $e\n$st');
      }
    }

    return null;
  }

  Future<void> joinTour({
    required String tourId,
    required UserModel user,
  }) async {
    final batch = _db.batch();

    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([user.uid]),
      'pastMembers': FieldValue.arrayRemove([user.uid]),
    });

    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(user.uid);
    batch.set(
      memberRef,
      {
        'userId': user.uid,
        'displayName': user.displayName,
        'username': user.username,
        'email': user.email,
        'photoUrl': user.photoUrl,
        'role': 'member',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
        'balance': 0.0,
      },
      SetOptions(merge: true),
    );

    // Only update activeTourId if the joining user is the currently authenticated user
    if (_auth.currentUser?.uid == user.uid) {
      final userRef = _db.collection(AppConstants.usersCollection).doc(user.uid);
      batch.update(userRef, {'activeTourId': tourId});
    }

    await batch.commit();
  }

  /// Explicitly add a member to the tour without attempting to mutate the target user's private document
  Future<void> addMemberToTour({
    required String tourId,
    required UserModel user,
  }) async {
    final batch = _db.batch();

    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([user.uid]),
      'pastMembers': FieldValue.arrayRemove([user.uid]),
    });

    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(user.uid);
    batch.set(
      memberRef,
      {
        'userId': user.uid,
        'displayName': user.displayName,
        'username': user.username,
        'email': user.email,
        'photoUrl': user.photoUrl,
        'role': 'member',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
        'balance': 0.0,
      },
      SetOptions(merge: true),
    );

    if (_auth.currentUser?.uid == user.uid) {
      final userRef = _db.collection(AppConstants.usersCollection).doc(user.uid);
      batch.update(userRef, {'activeTourId': tourId});
    }

    await batch.commit();
  }

  Future<void> addAdminAsMember({
    required String tourId,
    required UserModel admin,
  }) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(admin.uid)
        .set({
      'userId': admin.uid,
      'displayName': admin.displayName,
      'email': admin.email,
      'photoUrl': admin.photoUrl,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });
  }

  Future<void> inviteMemberByEmail({
    required String tourId,
    required String email,
    required String inviterName,
  }) async {
    await _db.collection('invites').add({
      'tourId': tourId,
      'email': email.toLowerCase(),
      'inviterName': inviterName,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  TourModel? getLocalTour(String tourId) {
    try {
      if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
        final box = Hive.box(OfflineTourQueueService.localToursBox);
        final val = box.get(tourId);
        if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          final members = (m['members'] as List?)?.cast<String>() ?? [];
          return TourModel(
            id: m['id'] as String? ?? tourId,
            name: m['name'] as String? ?? 'Offline Tour',
            description: m['description'] as String?,
            currency: m['currency'] as String? ?? 'USD',
            currencySymbol: m['currencySymbol'] as String? ?? '\$',
            adminId: m['adminId'] as String? ?? '',
            inviteCode: m['inviteCode'] as String? ?? '',
            status: TourStatus.active,
            startDate: m['startDate'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['startDate'] as int)
                : DateTime.now(),
            endDate: m['endDate'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['endDate'] as int)
                : DateTime.now().add(const Duration(days: 7)),
            memberIds: members,
            createdAt: m['createdAt'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int)
                : DateTime.now(),
          );
        }
      }
      final cached = ActiveTourCacheService.getCachedActiveTour();
      if (cached != null && cached.id == tourId) return cached;
      return null;
    } catch (_) {
      return null;
    }
  }

  Stream<TourModel?> watchTour(String tourId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalTour(tourId);
      if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
        final box = Hive.box(OfflineTourQueueService.localToursBox);
        await for (final _ in box.watch(key: tourId)) {
          yield getLocalTour(tourId);
        }
      }
      return;
    }
    final cached = ActiveTourCacheService.getCachedActiveTour();
    if (cached != null && cached.id == tourId) {
      yield cached;
    }
    try {
      yield* _tours.doc(tourId).snapshots().map(
            (doc) => doc.exists ? TourModel.fromFirestore(doc) : null,
          );
    } catch (e) {
      debugPrint('[TOUR_REPO] watchTour error: $e');
      if (cached != null && cached.id == tourId) yield cached;
    }
  }

  Stream<List<TourMemberModel>> watchMembers(String tourId) async* {
    if (tourId.startsWith('local_')) {
      yield getLocalTourMembers(tourId);
      if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
        final box = Hive.box(OfflineTourQueueService.localToursBox);
        await for (final _ in box.watch()) {
          yield getLocalTourMembers(tourId);
        }
      }
      return;
    }

    final cached = ActiveTourCacheService.getCachedMembers(tourId);
    if (cached.isNotEmpty) {
      yield cached;
    }

    try {
      yield* _tours
          .doc(tourId)
          .collection(AppConstants.membersSubcollection)
          .snapshots()
          .map((snap) {
            final firestoreMembers = snap.docs.map((d) {
              final m = TourMemberModel.fromFirestore(d);
              if (!m.isOffline) {
                UserCacheService.cacheTourMember(m);
              }
              return m;
            }).where((m) =>
                m.role != 'pending' &&
                m.role != 'rejected' &&
                m.role != 'deleted' &&
                m.status != 'deleted').toList();

            // Merge any offline-queued members from cache
            final currentCached = ActiveTourCacheService.getCachedMembers(tourId);
            for (final c in currentCached) {
              if (!firestoreMembers.any((m) => m.userId == c.userId)) {
                firestoreMembers.add(c);
              }
            }
            return firestoreMembers;
          });
    } catch (e) {
      debugPrint('[TOUR_REPO] watchMembers error: $e, using cached members');
      if (cached.isNotEmpty) yield cached;
    }
  }

  List<TourMemberModel> getLocalTourMembers(String tourId) {
    final members = <TourMemberModel>[];
    try {
      if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
        final box = Hive.box(OfflineTourQueueService.localToursBox);
        for (final k in box.keys) {
          if (k.toString().startsWith('member_${tourId}_')) {
            final val = box.get(k);
            if (val is Map) {
              final m = Map<String, dynamic>.from(val);
              members.add(TourMemberModel(
                userId: m['userId'] as String? ?? '',
                displayName: m['displayName'] as String? ?? 'Member',
                email: m['email'] as String? ?? '',
                photoUrl: m['photoUrl'] as String?,
                role: m['role'] as String? ?? 'member',
                status: m['status'] as String? ?? 'active',
                joinedAt: DateTime.fromMillisecondsSinceEpoch(m['joinedAt'] as int? ?? 0),
                balance: (m['balance'] as num?)?.toDouble() ?? 0.0,
                isOffline: m['isOffline'] == true,
              ));
            }
          }
        }
      }
    } catch (_) {}

    // Merge any cached members that aren't in localToursBox yet
    final cached = ActiveTourCacheService.getCachedMembers(tourId);
    for (final cm in cached) {
      if (!members.any((m) => m.userId == cm.userId)) {
        members.add(cm);
      }
    }

    // Merge any offline-queued members
    try {
      final queued = OfflineTourQueueService().getQueuedMembersForTour(tourId);
      for (final qm in queued) {
        if (!members.any((m) => m.userId == qm.userId)) {
          members.add(qm);
        }
      }
    } catch (_) {}

    if (members.isEmpty) {
      final tour = getLocalTour(tourId);
      if (tour != null && tour.adminId.isNotEmpty) {
        final cachedUser = UserCacheService.getUser(tour.adminId);
        members.add(TourMemberModel(
          userId: tour.adminId,
          displayName: cachedUser?.displayName ?? 'Admin',
          email: '',
          role: 'admin',
          status: 'active',
          joinedAt: tour.createdAt,
          balance: 0.0,
          isOffline: false,
        ));
      }
    }
    return members;
  }

  Future<void> updateTour(String tourId, Map<String, dynamic> data) async {
    await _tours.doc(tourId).update(data);
  }

  Future<void> completeTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'completed',
      'endDate': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reopenTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'active',
      'endDate': null,
    });
  }

  Future<void> deleteTour(String tourId, {String? currentUserId}) async {
    if (tourId.startsWith('local_')) {
      await _deleteLocalTourInternal(tourId);
      return;
    }

    final isOffline = await _isNetworkOffline();
    if (isOffline) {
      await _queueTourDeletionInternal(tourId, currentUserId);
      return;
    }

    try {
      final tour = await getTour(tourId).timeout(const Duration(seconds: 4));
      final isAdmin =
          currentUserId != null && tour != null && tour.isAdmin(currentUserId);

      // If current user is not admin or is already a past member, only remove for themselves
      if (!isAdmin && currentUserId != null && currentUserId.isNotEmpty) {
        await removeTourForUser(tourId, currentUserId);
        return;
      }

      // 1. Remove current user from members array and clear activeTourId immediately
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          await _tours.doc(tourId).update({
            'members': FieldValue.arrayRemove([currentUserId]),
          }).timeout(const Duration(seconds: 4));
        } catch (_) {}
        try {
          await _users.doc(currentUserId).update({'activeTourId': null}).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      // 2. Soft-mark as deleted and clear remaining members list so all listeners drop it instantly
      try {
        await _tours.doc(tourId).update({
          'isDeleted': true,
          'status': 'deleted',
          'members': [],
        }).timeout(const Duration(seconds: 4));
      } catch (_) {}

      // 3. Collect member IDs from subcollection to clear their activeTourId
      final membersSnap = await _tours
          .doc(tourId)
          .collection(AppConstants.membersSubcollection)
          .get()
          .timeout(const Duration(seconds: 4));
      final memberIds = membersSnap.docs.map((d) => d.id).toSet();
      if (currentUserId != null) memberIds.add(currentUserId);

      final subcollections = [
        AppConstants.membersSubcollection,
        AppConstants.expensesSubcollection,
        AppConstants.settlementsSubcollection,
        AppConstants.categoriesSubcollection,
        'join_requests',
        'chats',
      ];

      for (final sub in subcollections) {
        try {
          final snap = await _tours.doc(tourId).collection(sub).get().timeout(const Duration(seconds: 4));
          const batchLimit = 499;
          for (int i = 0; i < snap.docs.length; i += batchLimit) {
            final batch = _db.batch();
            final chunk = snap.docs.skip(i).take(batchLimit);
            for (final doc in chunk) {
              batch.delete(doc.reference);
            }
            await batch.commit().timeout(const Duration(seconds: 4));
          }
        } catch (_) {}
      }

      try {
        await _tours.doc(tourId).delete().timeout(const Duration(seconds: 4));
      } catch (_) {}

      for (final uid in memberIds) {
        try {
          await _db
              .collection(AppConstants.usersCollection)
              .doc(uid)
              .update({'activeTourId': null}).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      if (ActiveTourCacheService.getActiveTourId() == tourId) {
        await ActiveTourCacheService.clearCachedActiveTour();
      }
    } catch (e) {
      // Offline fallback: queue deletion for sync and clear locally
      await _queueTourDeletionInternal(tourId, currentUserId);
    }
  }

  Future<bool> _isNetworkOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteLocalTourInternal(String localTourId) async {
    try {
      if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
        final box = Hive.box(OfflineTourQueueService.localToursBox);
        await box.delete(localTourId);
        final memberKeys = box.keys
            .where((k) => k.toString().startsWith('member_${localTourId}_'))
            .toList();
        for (final k in memberKeys) {
          await box.delete(k);
        }
      }
      if (Hive.isBoxOpen(OfflineTourQueueService.boxName)) {
        final qBox = Hive.box(OfflineTourQueueService.boxName);
        await qBox.delete('create_$localTourId');
        final queueKeys = qBox.keys
            .where((k) => k.toString().startsWith('addMember_${localTourId}_'))
            .toList();
        for (final k in queueKeys) {
          await qBox.delete(k);
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
    } catch (e) {
      debugPrint('[TOUR_REPO] Error deleting local tour: $e');
    }
  }

  Future<void> _queueTourDeletionInternal(String tourId, String? currentUserId) async {
    try {
      if (Hive.isBoxOpen(OfflineTourQueueService.boxName)) {
        final qBox = Hive.box(OfflineTourQueueService.boxName);
        await qBox.put('delete_$tourId', {
          'type': 'deleteTour',
          'tourId': tourId,
          'currentUserId': currentUserId,
          'queuedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
      if (ActiveTourCacheService.getActiveTourId() == tourId) {
        await ActiveTourCacheService.clearCachedActiveTour();
      }
    } catch (e) {
      debugPrint('[TOUR_REPO] Error queuing tour deletion: $e');
    }
  }

  Future<TourMemberModel> addOfflineMember({
    required String tourId,
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Name cannot be empty');

    final memberId = 'offline_${const Uuid().v4()}';
    final batch = _db.batch();

    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([memberId]),
    });

    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(memberId);

    batch.set(memberRef, {
      'userId': memberId,
      'displayName': cleanName,
      'email': '',
      'photoUrl': null,
      'role': 'member',
      'isOffline': true,
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });

    await batch.commit();

    return TourMemberModel(
      userId: memberId,
      displayName: cleanName,
      email: '',
      photoUrl: null,
      role: 'member',
      isOffline: true,
      joinedAt: DateTime.now(),
      balance: 0.0,
    );
  }

  Future<void> updateOfflineMemberName({
    required String tourId,
    required String memberId,
    required String newName,
  }) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;

    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(memberId)
        .update({
      'displayName': cleanName,
    });
  }

  Future<UserModel?> findUserByUsernameOrEmail(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return null;

    try {
      var snap = await _db
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        return UserModel.fromFirestore(snap.docs.first);
      }

      snap = await _db
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: clean)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        return UserModel.fromFirestore(snap.docs.first);
      }
    } catch (_) {}

    return null;
  }

  Future<void> replaceOfflineMemberWithOnlineUser({
    required String tourId,
    required String offlineMemberId,
    required String onlineUserId,
    required String onlineUserName,
    String? onlineUserPhotoUrl,
    String? onlineUserEmail,
  }) async {
    // 1. Fetch all expenses for this tour
    final expensesSnap = await _tours
        .doc(tourId)
        .collection(AppConstants.expensesSubcollection)
        .get();

    // 2. Fetch all settlements for this tour
    final settlementsSnap = await _tours
        .doc(tourId)
        .collection(AppConstants.settlementsSubcollection)
        .get();

    final batch = _db.batch();

    // A. Update expenses
    for (final expDoc in expensesSnap.docs) {
      final data = expDoc.data();
      bool needsUpdate = false;
      final updates = <String, dynamic>{};

      if (data['paidByUserId'] == offlineMemberId ||
          data['paidBy'] == offlineMemberId) {
        updates['paidByUserId'] = onlineUserId;
        updates['paidBy'] = onlineUserId;
        updates['paidByName'] = onlineUserName;
        needsUpdate = true;
      }

      final payers = data['payers'] as Map<String, dynamic>?;
      if (payers != null && payers.containsKey(offlineMemberId)) {
        final newPayers = Map<String, dynamic>.from(payers);
        final amt = (newPayers.remove(offlineMemberId) as num?)?.toDouble() ?? 0.0;
        newPayers[onlineUserId] =
            ((newPayers[onlineUserId] as num?)?.toDouble() ?? 0.0) + amt;
        updates['payers'] = newPayers;
        needsUpdate = true;
      }

      final splitAmong = data['splitAmong'] as List<dynamic>?;
      if (splitAmong != null && splitAmong.contains(offlineMemberId)) {
        final newSplitAmong = List<dynamic>.from(splitAmong);
        final index = newSplitAmong.indexOf(offlineMemberId);
        if (index != -1) {
          if (!newSplitAmong.contains(onlineUserId)) {
            newSplitAmong[index] = onlineUserId;
          } else {
            newSplitAmong.removeAt(index);
          }
        }
        updates['splitAmong'] = newSplitAmong;
        needsUpdate = true;
      }

      final customSplits = data['customSplits'] as Map<String, dynamic>?;
      if (customSplits != null && customSplits.containsKey(offlineMemberId)) {
        final newCustomSplits = Map<String, dynamic>.from(customSplits);
        final amt =
            (newCustomSplits.remove(offlineMemberId) as num?)?.toDouble() ?? 0.0;
        newCustomSplits[onlineUserId] =
            ((newCustomSplits[onlineUserId] as num?)?.toDouble() ?? 0.0) + amt;
        updates['customSplits'] = newCustomSplits;
        needsUpdate = true;
      }

      if (needsUpdate) {
        batch.update(expDoc.reference, updates);
      }
    }

    // B. Update settlements
    for (final setDoc in settlementsSnap.docs) {
      final data = setDoc.data();
      bool needsUpdate = false;
      final updates = <String, dynamic>{};

      if (data['fromUserId'] == offlineMemberId) {
        updates['fromUserId'] = onlineUserId;
        updates['fromUserName'] = onlineUserName;
        needsUpdate = true;
      }
      if (data['toUserId'] == offlineMemberId) {
        updates['toUserId'] = onlineUserId;
        updates['toUserName'] = onlineUserName;
        needsUpdate = true;
      }

      if (needsUpdate) {
        batch.update(setDoc.reference, updates);
      }
    }

    // C. Update members subcollection
    final offlineMemberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(offlineMemberId);
    batch.delete(offlineMemberRef);

    final onlineMemberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(onlineUserId);
    batch.set(
      onlineMemberRef,
      {
        'userId': onlineUserId,
        'displayName': onlineUserName,
        'email': onlineUserEmail ?? '',
        'photoUrl': onlineUserPhotoUrl,
        'role': 'member',
        'isOffline': false,
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // D. Update tour doc members array
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayRemove([offlineMemberId]),
    });
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([onlineUserId]),
    });

    await batch.commit();

    // E. Set activeTourId on online user if not currently set
    try {
      final userDoc = await _db
          .collection(AppConstants.usersCollection)
          .doc(onlineUserId)
          .get();
      if (userDoc.exists && userDoc.data()?['activeTourId'] == null) {
        await _db
            .collection(AppConstants.usersCollection)
            .doc(onlineUserId)
            .update({'activeTourId': tourId});
      }
    } catch (_) {}
  }

  Future<bool> hasMemberTransactions(String tourId, String userId) async {
    try {
      final expensesSnap = await _tours
          .doc(tourId)
          .collection(AppConstants.expensesSubcollection)
          .get();

      for (final doc in expensesSnap.docs) {
        final data = doc.data();
        if (data['status'] == 'rejected') continue;
        if (data['paidByUserId'] == userId || data['paidBy'] == userId) return true;

        final contributions = data['contributions'] as Map<String, dynamic>?;
        if (contributions != null && contributions.containsKey(userId)) {
          final amt = (contributions[userId] as num?)?.toDouble() ?? 0.0;
          if (amt > 0.009) return true;
        }

        final payers = data['payers'] as Map<String, dynamic>?;
        if (payers != null && payers.containsKey(userId)) {
          final amt = (payers[userId] as num?)?.toDouble() ?? 0.0;
          if (amt > 0.009) return true;
        }

        final splitAmong = data['splitAmong'] as List<dynamic>?;
        if (splitAmong != null && splitAmong.contains(userId)) return true;

        final splits = data['splits'] as Map<String, dynamic>?;
        if (splits != null && splits.containsKey(userId)) {
          final amt = (splits[userId] as num?)?.toDouble() ?? 0.0;
          if (amt > 0.009) return true;
        }

        final customSplits = data['customSplits'] as Map<String, dynamic>?;
        if (customSplits != null && customSplits.containsKey(userId)) {
          final amt = (customSplits[userId] as num?)?.toDouble() ?? 0.0;
          if (amt > 0.009) return true;
        }
      }

      final settlementsSnap = await _tours
          .doc(tourId)
          .collection(AppConstants.settlementsSubcollection)
          .get();

      for (final doc in settlementsSnap.docs) {
        final data = doc.data();
        if (data['fromUserId'] == userId || data['toUserId'] == userId) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeMistakenMember({
    required String tourId,
    required String userId,
  }) async {
    final batch = _db.batch();

    // 1. Completely remove from tour members and pastMembers arrays
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayRemove([userId]),
      'pastMembers': FieldValue.arrayRemove([userId]),
    });

    // 2. Mark member as removed/rejected in subcollection
    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId);
    batch.set(
      memberRef,
      {
        'status': 'deleted',
        'role': 'rejected',
      },
      SetOptions(merge: true),
    );

    // Commit the batch update (both operations permitted for authenticated users)
    await batch.commit();

    // 3. Attempt permanent deletion of member doc from subcollection
    try {
      await memberRef.delete();
    } catch (_) {}

    // 4. Clear user active tour if pointing here (best effort; current user only according to security rules)
    if (!userId.startsWith('offline_')) {
      try {
        final userRef = _db.collection(AppConstants.usersCollection).doc(userId);
        await userRef.update({'activeTourId': null});
      } catch (_) {}
    }
  }

  Future<void> removeMember(String tourId, String userId,
      {bool isKick = true}) async {
    final batch = _db.batch();
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayRemove([userId]),
      'pastMembers': FieldValue.arrayUnion([userId]),
    });
    batch.set(
      _tours
          .doc(tourId)
          .collection(AppConstants.membersSubcollection)
          .doc(userId),
      {
        'status': isKick ? 'removed' : 'left',
        'role': 'past_member',
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    if (!userId.startsWith('offline_')) {
      try {
        await _db.collection(AppConstants.usersCollection).doc(userId).update({
          'activeTourId': null,
        });
      } catch (_) {}
    }
  }

  /// Leaves a tour. If the user has zero financial activity (no contributions/payments,
  /// no expense split shares, and no settlements), they are purged completely from the tour.
  /// If they have financial history, their record is preserved as a past member with status 'left'
  /// so calculations and settlements remain intact. Returns true if preserved as past member.
  Future<bool> leaveTourWithAudit(String tourId, String userId) async {
    if (tourId.startsWith('local_')) {
      await removeTourForUser(tourId, userId);
      return false;
    }
    // 1. Fetch expenses for tour
    final expensesSnap = await _tours
        .doc(tourId)
        .collection(AppConstants.expensesSubcollection)
        .get();

    bool hasActivity = false;
    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      final paidBy = data['paidBy'] ?? data['paidByUserId'];
      if (paidBy == userId) {
        hasActivity = true;
        break;
      }
      final payers = data['payers'];
      if (payers is Map && (payers[userId] as num? ?? 0) > 0) {
        hasActivity = true;
        break;
      }
      final splitAmong = data['splitAmong'];
      if (splitAmong is List && splitAmong.contains(userId)) {
        hasActivity = true;
        break;
      }
      final customSplits = data['customSplits'];
      if (customSplits is Map && (customSplits[userId] as num? ?? 0) > 0) {
        hasActivity = true;
        break;
      }
    }

    if (!hasActivity) {
      // 2. Fetch settlements
      final settlementsSnap = await _tours
          .doc(tourId)
          .collection(AppConstants.settlementsSubcollection)
          .get();
      for (final doc in settlementsSnap.docs) {
        final data = doc.data();
        if (data['fromUserId'] == userId || data['toUserId'] == userId) {
          hasActivity = true;
          break;
        }
      }
    }

    final batch = _db.batch();

    if (!hasActivity) {
      // Complete purge: remove from members & pastMembers, delete member document
      batch.update(_tours.doc(tourId), {
        'members': FieldValue.arrayRemove([userId]),
        'pastMembers': FieldValue.arrayRemove([userId]),
      });
      batch.delete(
        _tours
            .doc(tourId)
            .collection(AppConstants.membersSubcollection)
            .doc(userId),
      );
    } else {
      // Retain math: move to pastMembers, set status left
      batch.update(_tours.doc(tourId), {
        'members': FieldValue.arrayRemove([userId]),
        'pastMembers': FieldValue.arrayUnion([userId]),
      });
      batch.set(
        _tours
            .doc(tourId)
            .collection(AppConstants.membersSubcollection)
            .doc(userId),
        {
          'status': 'left',
          'role': 'past_member',
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    if (!userId.startsWith('offline_')) {
      try {
        await _db.collection(AppConstants.usersCollection).doc(userId).update({
          'activeTourId': null,
        });
      } catch (_) {}
    }

    return hasActivity;
  }

  Future<void> leaveTour(String tourId, String userId) async {
    await leaveTourWithAudit(tourId, userId);
  }

  Future<void> removeTourForUser(String tourId, String userId) async {
    if (tourId.startsWith('local_')) {
      try {
        if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
          final box = Hive.box(OfflineTourQueueService.localToursBox);
          final val = box.get(tourId);
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            final members = (m['members'] as List?)?.cast<String>() ?? [];
            members.remove(userId);
            if (members.isEmpty) {
              await _deleteLocalTourInternal(tourId);
            } else {
              m['members'] = members;
              await box.put(tourId, m);
            }
          }
        }
        if (ActiveTourCacheService.getActiveTourId() == tourId) {
          await ActiveTourCacheService.clearCachedActiveTour();
        }
      } catch (_) {}
      return;
    }

    try {
      final batch = _db.batch();
      batch.update(_tours.doc(tourId), {
        'members': FieldValue.arrayRemove([userId]),
        'pastMembers': FieldValue.arrayRemove([userId]),
      });
      try {
        await _db.collection(AppConstants.usersCollection).doc(userId).update({
          'activeTourId': null,
        });
      } catch (_) {}
      await batch.commit();
    } catch (e) {
      await _queueTourDeletionInternal(tourId, userId);
    }
  }

  Future<void> clearUserActiveTour(String userId) async {
    try {
      await ActiveTourCacheService.clearCachedActiveTour();
      await _db.collection(AppConstants.usersCollection).doc(userId).update({
        'activeTourId': null,
      });
    } catch (_) {}
  }

  Future<void> switchActiveTour(String userId, String tourId, {TourModel? tour}) async {
    await ActiveTourCacheService.setActiveTourId(tourId);
    if (tour != null) {
      await ActiveTourCacheService.cacheActiveTour(tour: tour);
    }
    // Update Firestore in background without blocking the UI
    unawaited(_db.collection(AppConstants.usersCollection).doc(userId).update({
      'activeTourId': tourId,
    }).catchError((e) {
      debugPrint('[TOUR_REPO] switchActiveTour Firestore update error: $e');
    }));
  }

  Future<void> requestToJoinTour({
    required String tourId,
    required String tourName,
    required UserModel user,
  }) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(user.uid)
        .set({
      'tourId': tourId,
      'tourName': tourName,
      'userId': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoUrl,
      'role': 'pending',
      'status': 'pending',
      'joinedAt': FieldValue.serverTimestamp(),
      'requestedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });

    try {
      await _tours.doc(tourId).collection('join_requests').doc(user.uid).set({
        'tourId': tourId,
        'tourName': tourName,
        'userId': user.uid,
        'displayName': user.displayName,
        'email': user.email,
        'photoUrl': user.photoUrl,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<JoinRequestModel?> watchUserJoinRequest(String tourId, String userId) {
    return _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final role = data['role'] ?? 'member';
      final status = (role == 'member' || role == 'admin')
          ? 'approved'
          : (role == 'rejected' ? 'rejected' : (data['status'] ?? 'pending'));
      return JoinRequestModel(
        id: doc.id,
        tourId: data['tourId'] ?? tourId,
        tourName: data['tourName'] ?? '',
        userId: data['userId'] ?? userId,
        displayName: data['displayName'] ?? '',
        email: data['email'] ?? '',
        photoUrl: data['photoUrl'],
        status: status,
        requestedAt:
            (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    });
  }

  Stream<List<JoinRequestModel>> watchTourJoinRequests(String tourId) {
    if (tourId.startsWith('local_')) {
      return Stream.value(<JoinRequestModel>[]);
    }
    return _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .where('role', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return JoinRequestModel(
                id: d.id,
                tourId: data['tourId'] ?? tourId,
                tourName: data['tourName'] ?? '',
                userId: data['userId'] ?? d.id,
                displayName: data['displayName'] ?? 'Member',
                email: data['email'] ?? '',
                photoUrl: data['photoUrl'],
                status: data['status'] ?? 'pending',
                requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              );
            }).toList());
  }

  Future<void> approveJoinRequest({
    required String tourId,
    required JoinRequestModel request,
  }) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(request.userId)
        .set({
      'userId': request.userId,
      'displayName': request.displayName,
      'email': request.email,
      'photoUrl': request.photoUrl,
      'role': 'member',
      'status': 'approved',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    }, SetOptions(merge: true));

    await _tours.doc(tourId).update({
      'members': FieldValue.arrayUnion([request.userId]),
    });

    try {
      await _users.doc(request.userId).set({
        'activeTourId': tourId,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> rejectJoinRequest({
    required String tourId,
    required String userId,
  }) async {
    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId);
    await memberRef.set({
      'role': 'rejected',
      'status': 'rejected',
    }, SetOptions(merge: true));

    try {
      await _tours
          .doc(tourId)
          .collection('join_requests')
          .doc(userId)
          .update({'status': 'rejected'});
    } catch (_) {}
  }

  Future<void> setMemberRole({
    required String tourId,
    required String userId,
    required String role,
  }) async {
    final batch = _db.batch();

    if (role == 'admin') {
      batch.update(_tours.doc(tourId), {
        'adminIds': FieldValue.arrayUnion([userId]),
      });
    } else {
      batch.update(_tours.doc(tourId), {
        'adminIds': FieldValue.arrayRemove([userId]),
      });
    }

    batch.update(
      _tours
          .doc(tourId)
          .collection(AppConstants.membersSubcollection)
          .doc(userId),
      {'role': role},
    );

    await batch.commit();
  }

  Stream<List<TourModel>> watchUserTours(String userId) {
    late StreamController<List<TourModel>> controller;
    StreamSubscription? subActive;
    StreamSubscription? subPast;
    StreamSubscription? subLocal;
    List<TourModel> activeList = [];
    List<TourModel> pastList = [];

    void emitCombined() {
      if (controller.isClosed) return;
      final queuedDeleted = <String>{};
      try {
        if (Hive.isBoxOpen(OfflineTourQueueService.boxName)) {
          final qBox = Hive.box(OfflineTourQueueService.boxName);
          for (final k in qBox.keys) {
            final val = qBox.get(k);
            if (val is Map && val['type'] == 'deleteTour') {
              final id = val['tourId'] as String?;
              if (id != null) queuedDeleted.add(id);
            }
          }
        }
      } catch (_) {}

      final map = <String, TourModel>{};

      // 1. Include local tours from Hive
      try {
        if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
          final box = Hive.box(OfflineTourQueueService.localToursBox);
          for (final key in box.keys) {
            if (key.toString().startsWith('local_')) {
              final val = box.get(key);
              if (val is Map) {
                final m = Map<String, dynamic>.from(val);
                final members = (m['members'] as List?)?.cast<String>() ?? [];
                if (members.contains(userId) ||
                    (m['adminId'] as String? ?? '') == userId) {
                  final t = TourModel(
                    id: m['id'] as String? ?? key.toString(),
                    name: m['name'] as String? ?? 'Offline Tour',
                    description: null,
                    currency: m['currency'] as String? ?? 'BDT',
                    currencySymbol: m['currencySymbol'] as String? ?? '৳',
                    adminId: m['adminId'] as String? ?? userId,
                    inviteCode: m['inviteCode'] as String? ?? '',
                    status: TourStatus.active,
                    startDate: m['startDate'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                            m['startDate'] as int)
                        : DateTime.now(),
                    endDate: m['endDate'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                            m['endDate'] as int)
                        : DateTime.now().add(const Duration(days: 7)),
                    memberIds: members,
                    createdAt: m['createdAt'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                            m['createdAt'] as int)
                        : DateTime.now(),
                  );
                  map[t.id] = t;
                }
              }
            }
          }
        }
      } catch (_) {}

      // Include cached active tour if it belongs to this user
      final cachedActive = ActiveTourCacheService.getCachedActiveTour();
      if (cachedActive != null &&
          (cachedActive.memberIds.contains(userId) ||
              cachedActive.adminId == userId)) {
        map.putIfAbsent(cachedActive.id, () => cachedActive);
      }

      for (final t in activeList) {
        map[t.id] = t;
      }
      for (final t in pastList) {
        map.putIfAbsent(t.id, () => t);
      }
      final list = map.values
          .where((t) =>
              !queuedDeleted.contains(t.id) &&
              !t.isDeleted &&
              t.status != TourStatus.deleted)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(list);
    }

    controller = StreamController<List<TourModel>>(
      onListen: () {
        // Immediate emit for instant offline / cached responsiveness
        emitCombined();

        try {
          if (Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) {
            final box = Hive.box(OfflineTourQueueService.localToursBox);
            subLocal = box.watch().listen((_) => emitCombined());
          }
        } catch (_) {}

        subActive = _tours
            .where('members', arrayContains: userId)
            .snapshots()
            .listen((snap) {
          activeList = snap.docs
              .where((d) => d.exists)
              .map((d) => TourModel.fromFirestore(d))
              .toList();
          emitCombined();
        }, onError: (_) {
          if (!controller.isClosed) {
            emitCombined();
          }
        });

        subPast = _tours
            .where('pastMembers', arrayContains: userId)
            .snapshots()
            .listen((snap) {
          pastList = snap.docs
              .where((d) => d.exists)
              .map((d) => TourModel.fromFirestore(d))
              .toList();
          emitCombined();
        }, onError: (_) {
          emitCombined();
        });
      },
      onCancel: () {
        subActive?.cancel();
        subPast?.cancel();
        subLocal?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> updateMemberBalance(
      String tourId, String userId, double balance) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId)
        .update({'balance': balance});
  }

  Future<TourModel?> getTour(String tourId) async {
    if (tourId.startsWith('local_')) {
      return getLocalTour(tourId);
    }
    try {
      final doc = await _tours.doc(tourId).get();
      return doc.exists ? TourModel.fromFirestore(doc) : null;
    } catch (_) {
      return getLocalTour(tourId);
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      AppConstants.inviteCodeLength,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }
}

final tourRepositoryProvider =
    Provider<TourRepository>((_) => TourRepository());

class ActiveTourIdOverrideNotifier extends Notifier<String?> {
  @override
  String? build() => ActiveTourCacheService.getActiveTourId();

  @override
  set state(String? val) => super.state = val;
  void setTourId(String? id) => state = id;
}

final activeTourIdOverrideProvider =
    NotifierProvider<ActiveTourIdOverrideNotifier, String?>(
        ActiveTourIdOverrideNotifier.new);

const String kNoActiveTourId = '__none__';

final activeTourIdProvider = Provider<String?>((ref) {
  final queuedDeleted = <String>{};
  try {
    if (Hive.isBoxOpen(OfflineTourQueueService.boxName)) {
      final qBox = Hive.box(OfflineTourQueueService.boxName);
      for (final k in qBox.keys) {
        final val = qBox.get(k);
        if (val is Map && val['type'] == 'deleteTour') {
          final id = val['tourId'] as String?;
          if (id != null) queuedDeleted.add(id);
        }
      }
    }
  } catch (_) {}

  final overrideId = ref.watch(activeTourIdOverrideProvider);
  if (overrideId == kNoActiveTourId) {
    return null;
  }
  if (overrideId != null &&
      overrideId.isNotEmpty &&
      !queuedDeleted.contains(overrideId)) {
    return overrideId;
  }
  final localId = ActiveTourCacheService.getActiveTourId();
  if (localId != null &&
      localId.isNotEmpty &&
      !queuedDeleted.contains(localId)) {
    return localId;
  }
  final user = ref.watch(currentUserProvider).value;
  if (user?.activeTourId != null &&
      !queuedDeleted.contains(user!.activeTourId)) {
    return user.activeTourId;
  }
  return null;
});

final tourStreamProvider =
    StreamProvider.family<TourModel?, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTour(tourId);
});

final tourMembersStreamProvider =
    StreamProvider.family<List<TourMemberModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchMembers(tourId);
});

final tourPendingJoinRequestsProvider =
    StreamProvider.family<List<JoinRequestModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTourJoinRequests(tourId);
});

final userToursStreamProvider =
    StreamProvider.family<List<TourModel>, String>((ref, userId) {
  return ref.watch(tourRepositoryProvider).watchUserTours(userId);
});

