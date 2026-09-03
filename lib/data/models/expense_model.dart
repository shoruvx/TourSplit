import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseStatus { pendingApproval, approved, rejected }

enum SplitType { equal, selected, custom }

class ExpenseModel {
  final String id;
  final String tourId;
  final String title;
  final double amount;
  final String currency;
  final String category;
  final String paidByUserId;
  final String paidByName;
  final Map<String, double>? payers; // userId -> amount contributed (for multi-contributor expenses)
  final SplitType splitType;
  final List<String> splitAmong; // userIds
  final Map<String, double>? customSplits; // userId -> amount
  final String? description;
  final DateTime date;
  final ExpenseStatus status;
  final String addedByUserId;
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.tourId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.paidByUserId,
    required this.paidByName,
    this.payers,
    required this.splitType,
    required this.splitAmong,
    this.customSplits,
    this.description,
    required this.date,
    required this.status,
    required this.addedByUserId,
    required this.createdAt,
  });

  bool get isPending => status == ExpenseStatus.pendingApproval;
  bool get isApproved => status == ExpenseStatus.approved;
  bool get isRejected => status == ExpenseStatus.rejected;

  /// Returns each member's contribution toward paying this expense
  Map<String, double> get contributions {
    if (payers != null && payers!.isNotEmpty) {
      return payers!;
    }
    return {paidByUserId: amount};
  }

  /// Whether this expense was contributed to by multiple people
  bool get isMultiPayer => payers != null && payers!.length > 1;

  /// Returns each member's share of this expense
  Map<String, double> get splits {
    if (splitType == SplitType.custom && customSplits != null) {
      return customSplits!;
    }
    if (splitAmong.isEmpty) return {};
    final share = amount / splitAmong.length;
    return {for (final uid in splitAmong) uid: share};
  }

  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExpenseModel(
      id: doc.id,
      tourId: data['tourId'] ?? '',
      title: data['title'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'BDT',
      category: data['category'] ?? 'Miscellaneous',
      paidByUserId: data['paidBy'] ?? '',
      paidByName: data['paidByName'] ?? '',
      payers: data['payers'] != null
          ? Map<String, double>.from(
              (data['payers'] as Map).map(
                (k, v) => MapEntry(k as String, (v as num).toDouble()),
              ),
            )
          : null,
      splitType: _parseSplitType(data['splitType']),
      splitAmong: List<String>.from(data['splitAmong'] ?? []),
      customSplits: data['customSplits'] != null
          ? Map<String, double>.from(
              (data['customSplits'] as Map).map(
                (k, v) => MapEntry(k as String, (v as num).toDouble()),
              ),
            )
          : null,
      description: data['description'],
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _parseStatus(data['status']),
      addedByUserId: data['addedBy'] ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static ExpenseStatus _parseStatus(String? s) {
    switch (s) {
      case 'approved':
        return ExpenseStatus.approved;
      case 'rejected':
        return ExpenseStatus.rejected;
      default:
        return ExpenseStatus.pendingApproval;
    }
  }

  static SplitType _parseSplitType(String? s) {
    switch (s) {
      case 'selected':
        return SplitType.selected;
      case 'custom':
        return SplitType.custom;
      default:
        return SplitType.equal;
    }
  }

  Map<String, dynamic> toFirestore() => {
        'tourId': tourId,
        'title': title,
        'amount': amount,
        'currency': currency,
        'category': category,
        'paidBy': paidByUserId,
        'paidByName': paidByName,
        'payers': payers,
        'splitType': splitType.name,
        'splitAmong': splitAmong,
        'customSplits': customSplits,
        'description': description,
        'date': Timestamp.fromDate(date),
        'status': status.name == 'pendingApproval'
            ? 'pending_approval'
            : status.name,
        'addedBy': addedByUserId,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ExpenseModel copyWith({ExpenseStatus? status}) {
    return ExpenseModel(
      id: id,
      tourId: tourId,
      title: title,
      amount: amount,
      currency: currency,
      category: category,
      paidByUserId: paidByUserId,
      paidByName: paidByName,
      payers: payers,
      splitType: splitType,
      splitAmong: splitAmong,
      customSplits: customSplits,
      description: description,
      date: date,
      status: status ?? this.status,
      addedByUserId: addedByUserId,
      createdAt: createdAt,
    );
  }
}
