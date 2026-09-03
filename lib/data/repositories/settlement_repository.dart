import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settlement_model.dart';
import '../../core/constants/app_constants.dart';

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
  }) async {
    final data = {
      'tourId': tourId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'amount': amount,
      'currency': currency,
      'status': 'requested',
      'requestedAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
      'resolvedBy': null,
      'note': note,
    };

    final ref = await _settlements(tourId).add(data);
    final doc = await ref.get();
    return SettlementModel.fromFirestore(doc);
  }

  Future<void> resolveSettlement({
    required String tourId,
    required String settlementId,
    required SettlementStatus status,
    required String resolvedByUserId,
  }) async {
    await _settlements(tourId).doc(settlementId).update({
      'status': status.name,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': resolvedByUserId,
    });
  }

  Stream<List<SettlementModel>> watchSettlements(String tourId) {
    return _settlements(tourId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SettlementModel.fromFirestore(d)).toList());
  }

  Stream<List<SettlementModel>> watchPendingSettlements(String tourId) {
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
