import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/expense_model.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/services/balance_service.dart';

void main() {
  group('BalanceService & Multi-Payer Tests', () {
    final memberA = TourMemberModel(
      userId: 'user_a',
      displayName: 'Alice',
      email: 'alice@test.com',
      role: 'admin',
      balance: 0,
      joinedAt: DateTime.now(),
    );

    final memberB = TourMemberModel(
      userId: 'user_b',
      displayName: 'Bob',
      email: 'bob@test.com',
      role: 'member',
      balance: 0,
      joinedAt: DateTime.now(),
    );

    final memberC = TourMemberModel(
      userId: 'user_c',
      displayName: 'Charlie',
      email: 'charlie@test.com',
      role: 'member',
      balance: 0,
      joinedAt: DateTime.now(),
    );

    final members = [memberA, memberB, memberC];

    test('Single payer equal split calculation', () {
      final expense = ExpenseModel(
        id: 'exp1',
        tourId: 'tour1',
        title: 'Dinner',
        amount: 300,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'user_a',
        paidByName: 'Alice',
        splitType: SplitType.equal,
        splitAmong: ['user_a', 'user_b', 'user_c'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_a',
        createdAt: DateTime.now(),
      );

      final balances = BalanceService.calculateBalances(members, [expense]);
      // Alice paid 300, owes 100 -> net +200
      expect(balances['user_a'], closeTo(200.0, 0.01));
      // Bob owes 100 -> net -100
      expect(balances['user_b'], closeTo(-100.0, 0.01));
      // Charlie owes 100 -> net -100
      expect(balances['user_c'], closeTo(-100.0, 0.01));

      final debts = BalanceService.simplifyDebts(balances, members);
      expect(debts.length, 2);
    });

    test('Multi-contributor split calculation (Alice paid 600, Bob paid 400)', () {
      // Hotel costs 1200 split equally among A, B, C (400 each)
      // Alice contributed 700, Bob contributed 500, Charlie contributed 0. Total = 1200
      final expense = ExpenseModel(
        id: 'exp2',
        tourId: 'tour1',
        title: 'Hotel',
        amount: 1200,
        currency: 'BDT',
        category: 'Hotel',
        paidByUserId: 'user_a',
        paidByName: 'Alice & Bob',
        payers: {
          'user_a': 700.0,
          'user_b': 500.0,
        },
        splitType: SplitType.equal,
        splitAmong: ['user_a', 'user_b', 'user_c'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_a',
        createdAt: DateTime.now(),
      );

      final balances = BalanceService.calculateBalances(members, [expense]);
      // Each person's share = 400
      // Alice paid 700 -> net +300
      expect(balances['user_a'], closeTo(300.0, 0.01));
      // Bob paid 500 -> net +100
      expect(balances['user_b'], closeTo(100.0, 0.01));
      // Charlie paid 0 -> net -400
      expect(balances['user_c'], closeTo(-400.0, 0.01));

      final debts = BalanceService.simplifyDebts(balances, members);
      // Charlie owes Alice 300 and Bob 100
      expect(debts.length, 2);
      expect(debts.any((d) => d.fromUserId == 'user_c' && d.toUserId == 'user_a' && d.amount == 300), isTrue);
      expect(debts.any((d) => d.fromUserId == 'user_c' && d.toUserId == 'user_b' && d.amount == 100), isTrue);
    });
  });
}
