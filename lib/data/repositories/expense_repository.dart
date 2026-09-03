import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_model.dart';
import '../../core/constants/app_constants.dart';

class ExpenseRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _expenses(String tourId) => _db
      .collection(AppConstants.toursCollection)
      .doc(tourId)
      .collection(AppConstants.expensesSubcollection);

  Future<ExpenseModel> addExpense(ExpenseModel expense) async {
    final data = expense.toFirestore()
      ..['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _expenses(expense.tourId).add(data);
    final doc = await ref.get();
    return ExpenseModel.fromFirestore(doc);
  }

  Future<void> updateExpenseStatus(
    String tourId,
    String expenseId,
    ExpenseStatus status,
  ) async {
    await _expenses(tourId).doc(expenseId).update({
      'status': status == ExpenseStatus.pendingApproval
          ? 'pending_approval'
          : status.name,
    });
  }

  Future<void> updateExpense(
      String tourId, String expenseId, Map<String, dynamic> data) async {
    await _expenses(tourId).doc(expenseId).update(data);
  }

  Future<void> deleteExpense(String tourId, String expenseId) async {
    await _expenses(tourId).doc(expenseId).delete();
  }

  Stream<List<ExpenseModel>> watchExpenses(String tourId) {
    return _expenses(tourId).orderBy('date', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList());
  }

  Stream<List<ExpenseModel>> watchApprovedExpenses(String tourId) {
    return _expenses(tourId)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Stream<ExpenseModel?> watchExpense(String tourId, String expenseId) {
    return _expenses(tourId)
        .doc(expenseId)
        .snapshots()
        .map((doc) => doc.exists ? ExpenseModel.fromFirestore(doc) : null);
  }

  Future<ExpenseModel?> getExpense(String tourId, String expenseId) async {
    final doc = await _expenses(tourId).doc(expenseId).get();
    return doc.exists ? ExpenseModel.fromFirestore(doc) : null;
  }

  Stream<List<ExpenseModel>> watchPendingExpenses(String tourId) {
    return _expenses(tourId)
        .where('status', isEqualTo: 'pending_approval')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }
}

final expenseRepositoryProvider =
    Provider<ExpenseRepository>((_) => ExpenseRepository());

final tourExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchExpenses(tourId);
});

final approvedExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchApprovedExpenses(tourId);
});

final pendingExpensesStreamProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, tourId) {
  return ref.watch(expenseRepositoryProvider).watchPendingExpenses(tourId);
});

final singleExpenseStreamProvider =
    StreamProvider.family<ExpenseModel?, ({String tourId, String expenseId})>(
        (ref, arg) {
  return ref
      .watch(expenseRepositoryProvider)
      .watchExpense(arg.tourId, arg.expenseId);
});
