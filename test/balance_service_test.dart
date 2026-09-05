import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/expense_model.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/settlement_model.dart';
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

    test('Offline member with name only is correctly included in splits and debts', () {
      final offlineMember = TourMemberModel(
        userId: 'offline_david',
        displayName: 'David (Offline Friend)',
        email: '',
        role: 'member',
        isOffline: true,
        balance: 0,
        joinedAt: DateTime.now(),
      );

      final allMembers = [...members, offlineMember];

      // Alice paid 400 for dinner split among Alice, Bob, Charlie, and David (100 each)
      final expense = ExpenseModel(
        id: 'exp3',
        tourId: 'tour1',
        title: 'Dinner with David',
        amount: 400,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'user_a',
        paidByName: 'Alice',
        splitType: SplitType.equal,
        splitAmong: ['user_a', 'user_b', 'user_c', 'offline_david'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_a',
        createdAt: DateTime.now(),
      );

      final balances = BalanceService.calculateBalances(allMembers, [expense]);
      // Alice paid 400, owes 100 -> net +300
      expect(balances['user_a'], closeTo(300.0, 0.01));
      // Bob, Charlie, David owe 100 each
      expect(balances['user_b'], closeTo(-100.0, 0.01));
      expect(balances['user_c'], closeTo(-100.0, 0.01));
      expect(balances['offline_david'], closeTo(-100.0, 0.01));

      final debts = BalanceService.simplifyDebts(balances, allMembers);
      expect(debts.length, 3);
      expect(debts.any((d) => d.fromUserId == 'offline_david' && d.fromUserName == 'David (Offline Friend)' && d.amount == 100), isTrue);
    });

    test('calculateTotalPaid accurately calculates each member total paid amount', () {
      final exp1 = ExpenseModel(
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

      final exp2 = ExpenseModel(
        id: 'exp2',
        tourId: 'tour1',
        title: 'Snacks',
        amount: 500,
        currency: 'BDT',
        category: 'Snacks',
        paidByUserId: 'user_b',
        paidByName: 'Bob',
        payers: {
          'user_a': 200.0,
          'user_b': 300.0,
        },
        splitType: SplitType.equal,
        splitAmong: ['user_a', 'user_b', 'user_c'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_b',
        createdAt: DateTime.now(),
      );

      final totalPaid = BalanceService.calculateTotalPaid(members, [exp1, exp2]);
      // Alice paid 300 + 200 = 500
      expect(totalPaid['user_a'], closeTo(500.0, 0.01));
      // Bob paid 300
      expect(totalPaid['user_b'], closeTo(300.0, 0.01));
      // Charlie paid 0
      expect(totalPaid['user_c'], closeTo(0.0, 0.01));
    });

    test('Floating-point precision does not produce ghost debts (< 0.01)', () {
      // Balance map with tiny floating point residual like 0.000000000000001
      final Map<String, double> noisyBalances = {
        'user_a': 0.004,
        'user_b': -0.004,
        'user_c': 0.0,
      };
      final debts = BalanceService.simplifyDebts(noisyBalances, members);
      expect(debts.isEmpty, isTrue);
    });

    test('Applying full settlement completely eliminates debt without residual', () {
      final exp = ExpenseModel(
        id: 'exp_s',
        tourId: 'tour1',
        title: 'Taxi',
        amount: 300.33,
        currency: 'BDT',
        category: 'Transport',
        paidByUserId: 'user_a',
        paidByName: 'Alice',
        splitType: SplitType.equal,
        splitAmong: ['user_a', 'user_b', 'user_c'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_a',
        createdAt: DateTime.now(),
      );

      final initialBalances = BalanceService.calculateBalances(members, [exp]);
      // Each pays 100.11. Alice net +200.22, Bob -100.11, Charlie -100.11
      expect(initialBalances['user_b'], closeTo(-100.11, 0.01));

      // Bob settles 100.11 to Alice
      final settlement = SettlementModel(
        id: 'set1',
        tourId: 'tour1',
        fromUserId: 'user_b',
        fromUserName: 'Bob',
        toUserId: 'user_a',
        toUserName: 'Alice',
        amount: 100.11,
        currency: 'BDT',
        status: SettlementStatus.approved,
        requestedAt: DateTime.now(),
      );

      final settledBalances = BalanceService.applySettlements(initialBalances, [settlement]);
      expect(settledBalances['user_b'], 0.0);
      expect(settledBalances['user_a'], closeTo(100.11, 0.01));

      final remainingDebts = BalanceService.simplifyDebts(settledBalances, members);
      // Only Charlie owes Alice now
      expect(remainingDebts.length, 1);
      expect(remainingDebts.first.fromUserId, 'user_c');
      expect(remainingDebts.first.toUserId, 'user_a');
      expect(remainingDebts.first.amount, closeTo(100.11, 0.01));
    });

    test('Past member retention and status checks', () {
      final tour = TourModel(
        id: 't1',
        name: 'Sylhet Tour',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'user_a',
        status: TourStatus.active,
        startDate: DateTime.now(),
        memberIds: ['user_a', 'user_b'],
        pastMemberIds: ['user_c'],
        inviteCode: 'CODE123',
        createdAt: DateTime.now(),
      );

      expect(tour.isMember('user_a'), isTrue);
      expect(tour.isMember('user_b'), isTrue);
      expect(tour.isMember('user_c'), isFalse);
      expect(tour.isPastMember('user_c'), isTrue);
      expect(tour.isMemberOrPast('user_c'), isTrue);

      final memberLeft = TourMemberModel(
        userId: 'user_c',
        displayName: 'Charlie',
        email: 'c@test.com',
        role: 'member',
        status: 'left',
        balance: 0,
        joinedAt: DateTime.now(),
      );
      expect(memberLeft.isLeft, isTrue);

      final memberRemoved = TourMemberModel(
        userId: 'user_d',
        displayName: 'David',
        email: 'd@test.com',
        role: 'member',
        status: 'removed',
        balance: 0,
        joinedAt: DateTime.now(),
      );
      expect(memberRemoved.isLeft, isTrue);

      final memberActive = TourMemberModel(
        userId: 'user_a',
        displayName: 'Alice',
        email: 'a@test.com',
        role: 'admin',
        status: 'active',
        balance: 0,
        joinedAt: DateTime.now(),
      );
      expect(memberActive.isLeft, isFalse);
    });

    test('Custom split assigns exact custom spending and balances to each member', () {
      // Alice pays 1000 for an activity
      // Custom split: Alice 200, Bob 500, Charlie 300
      final customExpense = ExpenseModel(
        id: 'exp_custom',
        tourId: 'tour1',
        title: 'Boat Safari',
        amount: 1000,
        currency: 'BDT',
        category: 'General',
        paidByUserId: 'user_a',
        paidByName: 'Alice',
        splitType: SplitType.custom,
        splitAmong: ['user_a', 'user_b', 'user_c'],
        customSplits: {
          'user_a': 200.0,
          'user_b': 500.0,
          'user_c': 300.0,
        },
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_a',
        createdAt: DateTime.now(),
      );

      final totalPaid = BalanceService.calculateTotalPaid(members, [customExpense]);
      expect(totalPaid['user_a'], closeTo(1000.0, 0.01));
      expect(totalPaid['user_b'], closeTo(0.0, 0.01));
      expect(totalPaid['user_c'], closeTo(0.0, 0.01));

      final totalSpent = BalanceService.calculateTotalSpent(members, [customExpense]);
      // Alice spent 200, Bob spent 500, Charlie spent 300
      expect(totalSpent['user_a'], closeTo(200.0, 0.01));
      expect(totalSpent['user_b'], closeTo(500.0, 0.01));
      expect(totalSpent['user_c'], closeTo(300.0, 0.01));

      final balances = BalanceService.calculateBalances(members, [customExpense]);
      // Alice paid 1000, spent 200 -> net +800
      expect(balances['user_a'], closeTo(800.0, 0.01));
      // Bob paid 0, spent 500 -> net -500
      expect(balances['user_b'], closeTo(-500.0, 0.01));
      // Charlie paid 0, spent 300 -> net -300
      expect(balances['user_c'], closeTo(-300.0, 0.01));

      final debts = BalanceService.simplifyDebts(balances, members);
      expect(debts.length, 2);
      expect(debts.any((d) => d.fromUserId == 'user_b' && d.toUserId == 'user_a' && d.amount == 500), isTrue);
      expect(debts.any((d) => d.fromUserId == 'user_c' && d.toUserId == 'user_a' && d.amount == 300), isTrue);
    });
  });
}


