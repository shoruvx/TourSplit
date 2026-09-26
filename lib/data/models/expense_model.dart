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
  final Map<String, double>? payers;
  final SplitType splitType;
  final List<String> splitAmong;
  final Map<String, double>? customSplits;
  final String? description;
  final DateTime date;
  final ExpenseStatus status;
  final String addedByUserId;
  final String addedByName;
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
    this.addedByName = '',
    required this.createdAt,
  });

  bool get isPending => status == ExpenseStatus.pendingApproval;
  bool get isApproved => status == ExpenseStatus.approved;
  bool get isRejected => status == ExpenseStatus.rejected;

  Map<String, double> get contributions {
    if (payers != null && payers!.isNotEmpty) {
      return payers!;
    }
    return {paidByUserId: amount};
  }

  bool get isMultiPayer => payers != null && payers!.length > 1;

  Map<String, double> get splits {
    if (splitType == SplitType.custom && customSplits != null) {
      return customSplits!;
    }
    if (splitAmong.isEmpty) return {};
    final share = amount / splitAmong.length;
    return {for (final uid in splitAmong) uid: share};
  }

  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    return ExpenseModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  factory ExpenseModel.fromMap(Map<String, dynamic> data, String id) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is DateTime) return val;
      return DateTime.now();
    }

    return ExpenseModel(
      id: id,
      tourId: data['tourId'] ?? '',
      title: data['title'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'BDT',
      category: data['category'] ?? 'General',
      paidByUserId: data['paidBy'] ?? data['paidByUserId'] ?? '',
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
      date: parseDate(data['date']),
      status: _parseStatus(data['status']),
      addedByUserId: data['addedBy'] ?? data['addedByUserId'] ?? '',
      addedByName: data['addedByName'] ??
          (data['addedBy'] == (data['paidBy'] ?? data['paidByUserId'])
              ? (data['paidByName'] ?? '')
              : ''),
      createdAt: parseDate(data['createdAt']),
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
        'status':
            status.name == 'pendingApproval' ? 'pending_approval' : status.name,
        'addedBy': addedByUserId,
        'addedByName': addedByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ExpenseModel copyWith({
    String? id,
    String? tourId,
    String? title,
    double? amount,
    String? currency,
    String? category,
    String? paidByUserId,
    String? paidByName,
    Map<String, double>? payers,
    SplitType? splitType,
    List<String>? splitAmong,
    Map<String, double>? customSplits,
    String? description,
    DateTime? date,
    ExpenseStatus? status,
    String? addedByUserId,
    String? addedByName,
    DateTime? createdAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      tourId: tourId ?? this.tourId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      paidByUserId: paidByUserId ?? this.paidByUserId,
      paidByName: paidByName ?? this.paidByName,
      payers: payers ?? this.payers,
      splitType: splitType ?? this.splitType,
      splitAmong: splitAmong ?? this.splitAmong,
      customSplits: customSplits ?? this.customSplits,
      description: description ?? this.description,
      date: date ?? this.date,
      status: status ?? this.status,
      addedByUserId: addedByUserId ?? this.addedByUserId,
      addedByName: addedByName ?? this.addedByName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String resolveAddedByName([String? cachedName]) {
    if (cachedName != null && cachedName.trim().isNotEmpty) {
      return cachedName.trim();
    }
    if (addedByName.trim().isNotEmpty) {
      return addedByName.trim();
    }
    if (addedByUserId.isNotEmpty &&
        addedByUserId == paidByUserId &&
        paidByName.trim().isNotEmpty) {
      return paidByName.trim();
    }
    return 'Unknown';
  }
}
