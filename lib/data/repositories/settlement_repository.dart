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

    if (localSettlement.isApproved) {
      await ActiveTourCacheService.appendCachedSettlement(tourId, localSettlement);
    }

    if (tourId.startsWith('local_')) {
      return localSettlement;
    }

    try {
      final ref = await _settlements(tourId).add(data).timeout(const Duration(milliseconds: 2000));
      final doc = await ref.get();
      return SettlementModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore requestSettlement offline/timeout: $e');
      return localSettlement;
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
    }

    if (tourId.startsWith('local_')) {
      return;
    }

    // 2. Update Firestore if online
    try {
      await _settlements(tourId).doc(settlementId).update({
        'status': status.name,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': resolvedByUserId,
      }).timeout(const Duration(milliseconds: 2000));
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
        final list =
            snap.docs.map((d) => SettlementModel.fromFirestore(d)).toList();
        final approved = list.where((s) => s.isApproved).toList();
        ActiveTourCacheService.cacheSettlements(tourId, approved);
        return list;
      });
    } catch (e) {
      debugPrint('[SETTLEMENT] Firestore watchSettlements offline/error: $e');
      if (cached.isNotEmpty) yield cached;
    }
  }

  Stream<List<SettlementModel>> watchPendingSettlements(String tourId) {
    if (tourId.startsWith('local_')) {
      return Stream.value(<SettlementModel>[]);
    }
    return _settlements(tourId)
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SettlementModel.fromFirestore(d)).toList());
  }
}

final settlementRepositoryProvider =
    Provider<SettlementRepository>((_) => SettlementRepository());

final tourSettlementsStreamProvider =
    StreamProvider.family<List<SettlementModel>, String>((ref, tourId) {
  return ref.watch(settlementRepositoryProvider).watchSettlements(tourId);
});

final pendingSettlementsStreamProvider =
    StreamProvider.family<List<SettlementModel>, String>((ref, tourId) {
  return ref
      .watch(settlementRepositoryProvider)
      .watchPendingSettlements(tourId);
});
