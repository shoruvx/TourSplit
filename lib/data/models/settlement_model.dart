import 'package:cloud_firestore/cloud_firestore.dart';

enum SettlementStatus { requested, approved, rejected }

class SettlementModel {
  final String id;
  final String tourId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
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
    return SettlementModel.fromMap(data, doc.id);
  }

  factory SettlementModel.fromMap(Map<String, dynamic> data, String id) {
    DateTime reqDate = DateTime.now();
    if (data['requestedAt'] is Timestamp) {
      reqDate = (data['requestedAt'] as Timestamp).toDate();
    } else if (data['requestedAt'] is int) {
      reqDate = DateTime.fromMillisecondsSinceEpoch(data['requestedAt'] as int);
    } else if (data['requestedAt'] is DateTime) {
      reqDate = data['requestedAt'] as DateTime;
    }

    DateTime? resDate;
    if (data['resolvedAt'] is Timestamp) {
      resDate = (data['resolvedAt'] as Timestamp).toDate();
    } else if (data['resolvedAt'] is int) {
      resDate = DateTime.fromMillisecondsSinceEpoch(data['resolvedAt'] as int);
    } else if (data['resolvedAt'] is DateTime) {
      resDate = data['resolvedAt'] as DateTime;
    }

    return SettlementModel(
      id: id,
      tourId: data['tourId'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUserName: data['toUserName'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'BDT',
      status: _parseStatus(data['status']),
      requestedAt: reqDate,
      resolvedAt: resDate,
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
