import '../models/expense_model.dart';
import '../models/tour_model.dart';
import '../models/settlement_model.dart';

class BalanceService {
  static Map<String, double> calculateBalances(
    List<TourMemberModel> members,
    List<ExpenseModel> approvedExpenses,
  ) {
    final balances = <String, double>{
      for (final m in members) m.userId: 0.0,
    };

    for (final expense in approvedExpenses) {
      if (expense.status != ExpenseStatus.approved) continue;

      final contributions = expense.contributions;
      for (final entry in contributions.entries) {
        balances[entry.key] = (balances[entry.key] ?? 0) + entry.value;
      }

      final splits = expense.splits;
      for (final entry in splits.entries) {
        balances[entry.key] = (balances[entry.key] ?? 0) - entry.value;
      }
    }

    final rounded = <String, double>{};
    for (final entry in balances.entries) {
      final val = (entry.value * 100).round() / 100;
      rounded[entry.key] = val.abs() < 0.009 ? 0.0 : val;
    }
    return rounded;
  }

  static Map<String, double> calculateTotalPaid(
    List<TourMemberModel> members,
    List<ExpenseModel> approvedExpenses,
  ) {
    final totalPaid = <String, double>{
      for (final m in members) m.userId: 0.0,
    };

    for (final expense in approvedExpenses) {
      if (expense.status != ExpenseStatus.approved) continue;

      final contributions = expense.contributions;
      for (final entry in contributions.entries) {
        totalPaid[entry.key] = (totalPaid[entry.key] ?? 0.0) + entry.value;
      }
    }

    final rounded = <String, double>{};
    for (final entry in totalPaid.entries) {
      rounded[entry.key] = (entry.value * 100).round() / 100;
    }
    return rounded;
  }

  static Map<String, double> calculateTotalSpent(
    List<TourMemberModel> members,
    List<ExpenseModel> approvedExpenses,
  ) {
    final totalSpent = <String, double>{
      for (final m in members) m.userId: 0.0,
    };

    for (final expense in approvedExpenses) {
      if (expense.status != ExpenseStatus.approved) continue;

      final splits = expense.splits;
      for (final entry in splits.entries) {
        totalSpent[entry.key] = (totalSpent[entry.key] ?? 0.0) + entry.value;
      }
    }

    final rounded = <String, double>{};
    for (final entry in totalSpent.entries) {
      final val = (entry.value * 100).round() / 100;
      rounded[entry.key] = val.abs() < 0.009 ? 0.0 : val;
    }
    return rounded;
  }

  static Map<String, double> applySettlements(
    Map<String, double> balances,
    List<SettlementModel> approvedSettlements,
  ) {
    final result = Map<String, double>.from(balances);
    for (final s in approvedSettlements) {
      if (s.status != SettlementStatus.approved) continue;
      result[s.fromUserId] = (result[s.fromUserId] ?? 0) + s.amount;
      result[s.toUserId] = (result[s.toUserId] ?? 0) - s.amount;
    }

    final rounded = <String, double>{};
    for (final entry in result.entries) {
      final val = (entry.value * 100).round() / 100;
      rounded[entry.key] = val.abs() < 0.009 ? 0.0 : val;
    }
    return rounded;
  }

  static List<DebtTransaction> simplifyDebts(
    Map<String, double> balances,
    List<TourMemberModel> members,
  ) {
    final memberMap = {for (final m in members) m.userId: m};

    final creditors = <MapEntry<String, double>>[];
    final debtors = <MapEntry<String, double>>[];

    for (final entry in balances.entries) {
      if (entry.value > 0.009) {
        creditors.add(entry);
      } else if (entry.value < -0.009) {
        debtors.add(MapEntry(entry.key, -entry.value));
      }
    }

    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final transactions = <DebtTransaction>[];
    int ci = 0, di = 0;

    var creditAmounts = creditors.map((e) => e.value).toList();
    var debtAmounts = debtors.map((e) => e.value).toList();

    while (ci < creditors.length && di < debtors.length) {
      double settle = creditAmounts[ci] < debtAmounts[di]
          ? creditAmounts[ci]
          : debtAmounts[di];
      settle = (settle * 100).round() / 100;

      if (settle >= 0.01) {
        transactions.add(DebtTransaction(
          fromUserId: debtors[di].key,
          fromUserName:
              memberMap[debtors[di].key]?.displayName ?? debtors[di].key,
          toUserId: creditors[ci].key,
          toUserName:
              memberMap[creditors[ci].key]?.displayName ?? creditors[ci].key,
          amount: settle,
        ));
      }

      creditAmounts[ci] =
          ((creditAmounts[ci] - settle) * 100).round() / 100;
      debtAmounts[di] =
          ((debtAmounts[di] - settle) * 100).round() / 100;

      if (creditAmounts[ci] < 0.01) ci++;
      if (debtAmounts[di] < 0.01) di++;
    }

    return transactions;
  }
}
