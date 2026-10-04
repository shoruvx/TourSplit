import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settlement_model.dart';
import '../../core/constants/app_constants.dart';
import '../services/active_tour_cache_service.dart';

class SettlementRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _settlements(String tourId) => _db
      .collection(AppConstants.toursCollection)
      .doc(tourId)
      .collection(AppConstants.settlementsSubcollection);

  Future<SettlementModel> requestSettlement({
    required String tourId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required double amount,
    required String currency,
    String? note,
    bool autoApprove = false,
    String? resolvedByUserId,
  }) async {
    // 1. Guard against duplicate pending requests between the same members
    if (!autoApprove) {
      final cached = ActiveTourCacheService.getCachedSettlements(tourId);
      final existingPending = cached.firstWhereOrNull((s) =>
          s.fromUserId == fromUserId &&
          s.toUserId == toUserId &&
          s.status == SettlementStatus.requested);
      if (existingPending != null) {
        debugPrint('[SETTLEMENT] Existing pending settlement found in cache: ${existingPending.id}');
        return existingPending;
      }

      if (!tourId.startsWith('local_')) {
        try {
          final query = await _settlements(tourId)
              .where('fromUserId', isEqualTo: fromUserId)
              .where('toUserId', isEqualTo: toUserId)
              .where('status', isEqualTo: 'requested')
              .limit(1)
              .get()
              .timeout(const Duration(milliseconds: 1500));
          if (query.docs.isNotEmpty) {
            final existing = SettlementModel.fromFirestore(query.docs.first);
            await ActiveTourCacheService.appendCachedSettlement(tourId, existing);
            debugPrint('[SETTLEMENT] Existing pending settlement found in Firestore: ${existing.id}');
            return existing;
          }
        } catch (_) {}
      }
    }

    final data = {
      'tourId': tourId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'amount': amount,
      'currency': currency,
      'status': autoApprove ? 'approved' : 'requested',
      'requestedAt': FieldValue.serverTimestamp(),
      'resolvedAt': autoApprove ? FieldValue.serverTimestamp() : null,
      'resolvedBy': autoApprove ? (resolvedByUserId ?? fromUserId) : null,
      'note': note,
    };

    final localId = 'settle_${DateTime.now().millisecondsSinceEpoch}';
    final localSettlement = SettlementModel(
      id: localId,
      tourId: tourId,
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      toUserId: toUserId,
      toUserName: toUserName,
      amount: amount,
      currency: currency,
      status: autoApprove ? SettlementStatus.approved : SettlementStatus.requested,
      requestedAt: DateTime.now(),
      resolvedAt: autoApprove ? DateTime.now() : null,
      resolvedBy: autoApprove ? (resolvedByUserId ?? fromUserId) : null,
      note: note,
    );

    // Save locally to cache immediately so UI reflects pending/approved state
    await ActiveTourCacheService.appendCachedSettlement(tourId, localSettlement);

    if (tourId.startsWith('local_')) {
      return localSettlement;
    }

    try {
      final docData = Map<String, dynamic>.from(data);
      docData['id'] = localId;
      await _settlements(tourId)
          .doc(localId)
          .set(docData, SetOptions(merge: true))
          .timeout(const Duration(milliseconds: 2000));
      return localSettlement;
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore requestSettlement offline/timeout: $e');
      return localSettlement;
    }
  }

  Future<void> saveSettlement(SettlementModel settlement) async {
    if (settlement.tourId.startsWith('local_')) return;
    try {
      final docRef = settlement.id.isNotEmpty
          ? _settlements(settlement.tourId).doc(settlement.id)
          : _settlements(settlement.tourId).doc();
      await docRef.set(settlement.toFirestore(), SetOptions(merge: true));
      await ActiveTourCacheService.appendCachedSettlement(settlement.tourId, settlement);
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore saveSettlement error: $e');
    }
  }

  Future<void> resolveSettlement({
    required String tourId,
    required String settlementId,
    required SettlementStatus status,
    required String resolvedByUserId,
  }) async {
    // 1. Immediately update ActiveTourCacheService
    final cached = ActiveTourCacheService.getCachedSettlements(tourId);
    final target = cached.firstWhereOrNull((s) => s.id == settlementId);
    if (target != null) {
      final updated = target.copyWith(
        status: status,
        resolvedAt: DateTime.now(),
        resolvedBy: resolvedByUserId,
      );
      await ActiveTourCacheService.appendCachedSettlement(tourId, updated);

      // If approved, automatically discard any OTHER pending settlement duplicates between this pair
      if (status == SettlementStatus.approved) {
        final duplicates = cached.where((s) =>
            s.id != settlementId &&
            s.fromUserId == target.fromUserId &&
            s.toUserId == target.toUserId &&
            s.status == SettlementStatus.requested).toList();

        for (final dup in duplicates) {
          final discarded = dup.copyWith(
            status: SettlementStatus.rejected,
            resolvedAt: DateTime.now(),
            resolvedBy: resolvedByUserId,
            note: 'Auto-discarded: duplicate settlement already resolved',
          );
          await ActiveTourCacheService.appendCachedSettlement(tourId, discarded);

          if (!tourId.startsWith('local_')) {
            try {
              await _settlements(tourId).doc(dup.id).set({
                'status': 'rejected',
                'resolvedAt': FieldValue.serverTimestamp(),
                'resolvedBy': resolvedByUserId,
                'note': 'Auto-discarded: duplicate settlement already resolved',
              }, SetOptions(merge: true)).timeout(const Duration(milliseconds: 1500));
            } catch (_) {}
          }
        }
      }
    }

    if (tourId.startsWith('local_')) {
      return;
    }

    // 2. Update Firestore if online
    try {
      await _settlements(tourId).doc(settlementId).set({
        'status': status.name,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': resolvedByUserId,
      }, SetOptions(merge: true)).timeout(const Duration(milliseconds: 2000));
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore resolveSettlement offline/timeout: $e');
    }
  }

  Stream<List<SettlementModel>> watchSettlements(String tourId) async* {
    final cached = ActiveTourCacheService.getCachedSettlements(tourId);
    if (cached.isNotEmpty) {
      yield cached;
    }

    if (tourId.startsWith('local_')) {
      yield cached;
      return;
    }

    try {
      yield* _settlements(tourId)
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map((snap) {
        final firestoreList =
            snap.docs.map((d) => SettlementModel.fromFirestore(d)).toList();
        final localCached = ActiveTourCacheService.getCachedSettlements(tourId);

        final Map<String, SettlementModel> mergedMap = {};
        for (final s in localCached) {
          mergedMap[s.id] = s;
        }
        for (final s in firestoreList) {
          mergedMap[s.id] = s;
        }
        final list = mergedMap.values.toList();

        // Automatic deduplication: keep only earliest pending settlement per from/to pair
        final seenPendingPairs = <String>{};
        final deduplicated = <SettlementModel>[];
        final duplicatesToDiscard = <SettlementModel>[];

        for (final s in list) {
          if (s.isPending) {
            final pairKey = '${s.fromUserId}_${s.toUserId}';
            if (seenPendingPairs.contains(pairKey)) {
              duplicatesToDiscard.add(s);
              continue;
            }
            seenPendingPairs.add(pairKey);
          }
          deduplicated.add(s);
        }

        // Silently discard duplicates in Firestore in the background
        for (final dup in duplicatesToDiscard) {
          _settlements(tourId).doc(dup.id).update({
            'status': 'rejected',
            'resolvedAt': FieldValue.serverTimestamp(),
            'resolvedBy': 'system_deduplication',
            'note': 'Auto-discarded: redundant duplicate pending request',
          }).catchError((_) {});
        }

        ActiveTourCacheService.cacheSettlements(tourId, deduplicated);
        return deduplicated;
      });
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore watchSettlements offline/error: $e');
      if (cached.isNotEmpty) yield cached;
    }
  }

  Stream<List<SettlementModel>> watchPendingSettlements(String tourId) async* {
    final cached = ActiveTourCacheService.getCachedSettlements(tourId);
    final cachedPending = cached.where((s) => s.isPending).toList();
    if (cachedPending.isNotEmpty) {
      yield cachedPending;
    }
    if (tourId.startsWith('local_')) {
      yield cachedPending;
      return;
    }
    try {
      yield* _settlements(tourId)
          .where('status', isEqualTo: 'requested')
          .snapshots()
          .map((snap) =>
              snap.docs.map((d) => SettlementModel.fromFirestore(d)).toList());
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore watchPendingSettlements offline/error: $e');
      if (cachedPending.isNotEmpty) yield cachedPending;
    }
  }
}

final settlementRepositoryProvider =
    Provider<SettlementRepository>((_) => SettlementRepository());

final tourSettlementsStreamProvider =
    StreamProvider.family<List<SettlementModel>, String>((ref, tourId) {
  ref.watch(localSettlementsRefreshProvider);
  return ref.watch(settlementRepositoryProvider).watchSettlements(tourId);
});

final pendingSettlementsStreamProvider =
    StreamProvider.family<List<SettlementModel>, String>((ref, tourId) {
  ref.watch(localSettlementsRefreshProvider);
  return ref
      .watch(settlementRepositoryProvider)
      .watchPendingSettlements(tourId);
});
