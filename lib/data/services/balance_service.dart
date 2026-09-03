import '../models/expense_model.dart';
import '../models/tour_model.dart';
import '../models/settlement_model.dart';

/// Computes per-member net balances from a list of approved expenses.
/// Then uses a greedy algorithm to simplify the debts into the minimum
/// number of transactions needed to settle everything.
class BalanceService {
  /// Calculate net balance for each member from approved expenses.
  /// Positive = owed money. Negative = owes money.
  static Map<String, double> calculateBalances(
    List<TourMemberModel> members,
    List<ExpenseModel> approvedExpenses,
  ) {
    // Initialize all members at zero
    final balances = <String, double>{
      for (final m in members) m.userId: 0.0,
    };

    for (final expense in approvedExpenses) {
      if (expense.status != ExpenseStatus.approved) continue;

      // Payer(s) get credited for their contribution
      final contributions = expense.contributions;
      for (final entry in contributions.entries) {
        balances[entry.key] = (balances[entry.key] ?? 0) + entry.value;
      }

      // Each participant in the split gets debited their share
      final splits = expense.splits;
      for (final entry in splits.entries) {
        balances[entry.key] =
            (balances[entry.key] ?? 0) - entry.value;
      }
    }

    return balances;
  }

  /// Apply approved settlements to existing balances.
  static Map<String, double> applySettlements(
    Map<String, double> balances,
    List<SettlementModel> approvedSettlements,
  ) {
    final result = Map<String, double>.from(balances);
    for (final s in approvedSettlements) {
      if (s.status != SettlementStatus.approved) continue;
      // Payer pays — reduce their debt (make less negative)
      result[s.fromUserId] = (result[s.fromUserId] ?? 0) + s.amount;
      // Receiver receives — reduce what's owed to them
      result[s.toUserId] = (result[s.toUserId] ?? 0) - s.amount;
    }
    return result;
  }

  /// Simplify debts: given net balances, compute the minimum set of
  /// transactions to settle all debts (greedy two-pointer approach).
  static List<DebtTransaction> simplifyDebts(
    Map<String, double> balances,
    List<TourMemberModel> members,
  ) {
    final memberMap = {for (final m in members) m.userId: m};

    // Separate creditors (positive) and debtors (negative)
    final creditors = <MapEntry<String, double>>[];
    final debtors = <MapEntry<String, double>>[];

    for (final entry in balances.entries) {
      if (entry.value > 0.001) {
        creditors.add(entry);
      } else if (entry.value < -0.001) {
        debtors.add(MapEntry(entry.key, -entry.value)); // store as positive
      }
    }

    // Sort descending by amount
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final transactions = <DebtTransaction>[];
    int ci = 0, di = 0;

    var creditAmounts = creditors.map((e) => e.value).toList();
    var debtAmounts = debtors.map((e) => e.value).toList();

    while (ci < creditors.length && di < debtors.length) {
      final settle = creditAmounts[ci] < debtAmounts[di]
          ? creditAmounts[ci]
          : debtAmounts[di];

      transactions.add(DebtTransaction(
        fromUserId: debtors[di].key,
        fromUserName:
            memberMap[debtors[di].key]?.displayName ?? debtors[di].key,
        toUserId: creditors[ci].key,
        toUserName:
            memberMap[creditors[ci].key]?.displayName ?? creditors[ci].key,
        amount: double.parse(settle.toStringAsFixed(2)),
      ));

      creditAmounts[ci] -= settle;
      debtAmounts[di] -= settle;

      if (creditAmounts[ci] < 0.001) ci++;
      if (debtAmounts[di] < 0.001) di++;
    }

    return transactions;
  }
}
