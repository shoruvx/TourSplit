import 'package:cloud_firestore/cloud_firestore.dart';

enum SettlementStatus { requested, approved, rejected }

class SettlementModel {
  final String id;
  final String tourId;
  final String fromUserId;   // owes money (negative balance)
  final String fromUserName;
  final String toUserId;     // is owed money
  final String toUserName;
  final double amount;
  final String currency;
  final SettlementStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? note;

  const SettlementModel({
    required this.id,
    required this.tourId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.requestedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.note,
  });

  bool get isPending => status == SettlementStatus.requested;
  bool get isApproved => status == SettlementStatus.approved;

  factory SettlementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SettlementModel(
      id: doc.id,
      tourId: data['tourId'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUserName: data['toUserName'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'BDT',
      status: _parseStatus(data['status']),
      requestedAt:
          (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
      note: data['note'],
    );
  }

  static SettlementStatus _parseStatus(String? s) {
    switch (s) {
      case 'approved':
        return SettlementStatus.approved;
      case 'rejected':
        return SettlementStatus.rejected;
      default:
        return SettlementStatus.requested;
    }
  }

  Map<String, dynamic> toFirestore() => {
        'tourId': tourId,
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'toUserId': toUserId,
        'toUserName': toUserName,
        'amount': amount,
        'currency': currency,
        'status': status.name,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'resolvedAt':
            resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
        'resolvedBy': resolvedBy,
        'note': note,
      };

  SettlementModel copyWith({
    SettlementStatus? status,
    DateTime? resolvedAt,
    String? resolvedBy,
  }) {
    return SettlementModel(
      id: id,
      tourId: tourId,
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      toUserId: toUserId,
      toUserName: toUserName,
      amount: amount,
      currency: currency,
      status: status ?? this.status,
      requestedAt: requestedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      note: note,
    );
  }
}

/// Represents a simplified debt transaction (who owes whom and how much)
class DebtTransaction {
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final double amount;

  const DebtTransaction({
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amount,
  });
}
