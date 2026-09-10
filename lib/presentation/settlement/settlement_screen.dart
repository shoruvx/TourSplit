import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/models/settlement_model.dart';
import '../../data/models/tour_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/services/balance_service.dart';
import 'widgets/manual_settlement_dialog.dart';
import 'widgets/receiver_payment_accounts_view.dart';

class SettlementScreen extends ConsumerWidget {
  const SettlementScreen({super.key});

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }
    final tourId = user.activeTourId!;

    final tourStream = ref.watch(tourStreamProvider(tourId));
    final settlementsStream = ref.watch(tourSettlementsStreamProvider(tourId));
    final expensesStream = ref.watch(tourExpensesStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: tourStream.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        data: (tour) {
          if (tour == null) return const Scaffold();
          final isAdmin = tour.isAdmin(user.uid);

          return Scaffold(
            appBar: AppBar(
              title: const Text('Settlements'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => _handleBack(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded,
                      color: AppColors.primaryTeal),
                  tooltip: 'Record Settlement',
                  onPressed: () {
                    final approvedExp = expensesStream.maybeWhen(
                      data: (list) => list.where((e) => e.isApproved).toList(),
                      orElse: () => <ExpenseModel>[],
                    );
                    final mems = membersStream.value ?? [];
                    var bals = BalanceService.calculateBalances(mems, approvedExp);
                    final approvedSets = (settlementsStream.value ?? [])
                        .where((s) => s.isApproved)
                        .toList();
                    bals = BalanceService.applySettlements(bals, approvedSets);

                    ManualSettlementDialog.show(
                      context,
                      ref: ref,
                      tour: tour,
                      members: mems,
                      computedBalances: bals,
                      currentUserId: user.uid,
                    );
                  },
                ),
              ],
            ),
            body: settlementsStream.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (settlements) {
                final approvedExpenses = expensesStream.maybeWhen(
                  data: (list) => list.where((e) => e.isApproved).toList(),
                  orElse: () => <ExpenseModel>[],
                );
                final members = membersStream.maybeWhen(
                  data: (list) => list,
                  orElse: () => <TourMemberModel>[],
                );
                final approvedSettlements =
                    settlements.where((s) => s.isApproved).toList();

                var balances =
                    BalanceService.calculateBalances(members, approvedExpenses);
                balances = BalanceService.applySettlements(
                    balances, approvedSettlements);
                final suggestedDebts =
                    BalanceService.simplifyDebts(balances, members);

                final pending = settlements.where((s) => s.isPending).toList();
                final resolved =
                    settlements.where((s) => !s.isPending).toList();

                if (suggestedDebts.isEmpty &&
                    pending.isEmpty &&
                    resolved.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 56, color: AppColors.positive),
                        const SizedBox(height: 16),
                        Text(
                          'All Settled Up',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Outfit',
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No outstanding balances or pending settlements.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryTeal.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.swap_horiz_rounded,
                                    color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Manual Settlement',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primaryTeal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  minimumSize: const Size(0, 34),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () => ManualSettlementDialog.show(
                                  context,
                                  ref: ref,
                                  tour: tour,
                                  members: members,
                                  computedBalances: balances,
                                  currentUserId: user.uid,
                                ),
                                child: const Text(
                                  'Record',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Pay full due to one person or record any custom payment.',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: Colors.white70,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (suggestedDebts.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'Suggested Settlements',
                        color: AppColors.primaryTeal,
                        count: suggestedDebts.length,
                      ),
                      const SizedBox(height: 8),
                      ...suggestedDebts.map((d) => _SuggestedDebtCard(
                            debt: d,
                            currency: tour.currencySymbol,
                            currentUserId: user.uid,
                            onSettle: () => _showSettleConfirmationDialog(
                              context,
                              ref,
                              tour,
                              d,
                              isAdmin,
                            ),
                          ).animate().fadeIn()),
                      const SizedBox(height: 20),
                    ],
                    if (pending.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'Pending Approval',
                        color: AppColors.warning,
                        count: pending.length,
                      ),
                      const SizedBox(height: 8),
                      ...pending.map((s) => _SettlementCard(
                            settlement: s,
                            isAdmin: isAdmin,
                            currentUserId: user.uid,
                            currency: tour.currencySymbol,
                            onApprove: () => _resolve(context, ref, tourId, s,
                                SettlementStatus.approved),
                            onReject: () => _resolve(context, ref, tourId, s,
                                SettlementStatus.rejected),
                          ).animate().fadeIn()),
                      const SizedBox(height: 20),
                    ],
                    if (resolved.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'History',
                        color: AppColors.accent,
                        count: resolved.length,
                      ),
                      const SizedBox(height: 8),
                      ...resolved.map((s) => _SettlementCard(
                            settlement: s,
                            isAdmin: isAdmin,
                            currentUserId: user.uid,
                            currency: tour.currencySymbol,
                          ).animate().fadeIn()),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showSettleConfirmationDialog(
    BuildContext context,
    WidgetRef ref,
    TourModel tour,
    DebtTransaction debt,
    bool isAdmin,
  ) async {
    final noteCtrl = TextEditingController(text: 'Cash / Mobile Payment');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dialog)),
        title: Row(
          children: [
            const Icon(Icons.handshake_rounded, color: AppColors.primaryTeal),
            const SizedBox(width: 10),
            const Text('Record Settlement'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${debt.fromUserName} pays ${debt.toUserName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      Text(
                        '${tour.currencySymbol}${debt.amount % 1 == 0 ? debt.amount.toStringAsFixed(0) : debt.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ],
                  ),
                ),
                ReceiverPaymentAccountsView(
                  toUserId: debt.toUserId,
                  toUserName: debt.toUserName,
                ),
                const SizedBox(height: 12),
                const Text('Payment Method / Note:',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. bKash, Cash, Bank Transfer',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repo = ref.read(settlementRepositoryProvider);
      final settlement = await repo.requestSettlement(
        tourId: tour.id,
        fromUserId: debt.fromUserId,
        fromUserName: debt.fromUserName,
        toUserId: debt.toUserId,
        toUserName: debt.toUserName,
        amount: debt.amount,
        currency: tour.currency,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );

      final currentUid = ref.read(currentUserProvider).value?.uid;
      final isReceiver = currentUid == debt.toUserId;
      if (isReceiver) {
        await repo.resolveSettlement(
          tourId: tour.id,
          settlementId: settlement.id,
          status: SettlementStatus.approved,
          resolvedByUserId: currentUid ?? tour.adminId,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isReceiver
                  ? 'Settlement recorded and approved!'
                  : 'Payment submitted! Waiting for ${debt.toUserName} to approve.',
            ),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    }
  }

  void _resolve(BuildContext context, WidgetRef ref, String tourId,
      SettlementModel s, SettlementStatus status) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    await ref.read(settlementRepositoryProvider).resolveSettlement(
          tourId: tourId,
          settlementId: s.id,
          status: status,
          resolvedByUserId: user.uid,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == SettlementStatus.approved
                ? 'Settlement approved!'
                : 'Settlement rejected.',
          ),
          backgroundColor: status == SettlementStatus.approved
              ? AppColors.positive
              : AppColors.negative,
        ),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _SectionLabel(
      {required this.label, required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestedDebtCard extends StatelessWidget {
  final DebtTransaction debt;
  final String currency;
  final String currentUserId;
  final VoidCallback onSettle;

  const _SuggestedDebtCard({
    required this.debt,
    required this.currency,
    required this.currentUserId,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        debt.fromUserName,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.negative,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 14, color: Colors.grey),
                    ),
                    Flexible(
                      child: Text(
                        debt.toUserName,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.positive,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$currency${debt.amount % 1 == 0 ? debt.amount.toStringAsFixed(0) : debt.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryTeal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onSettle,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Settle',
                style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  final SettlementModel settlement;
  final bool isAdmin;
  final String currentUserId;
  final String currency;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _SettlementCard({
    required this.settlement,
    required this.isAdmin,
    required this.currentUserId,
    required this.currency,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color statusColor;
    String statusText;
    switch (settlement.status) {
      case SettlementStatus.requested:
        statusColor = AppColors.warning;
        statusText = 'Pending';
      case SettlementStatus.approved:
        statusColor = AppColors.positive;
        statusText = '✓ Approved';
      case SettlementStatus.rejected:
        statusColor = AppColors.negative;
        statusText = '✗ Rejected';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              settlement.fromUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.negative,
                                fontFamily: 'Outfit',
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 14, color: Colors.grey),
                          ),
                          Flexible(
                            child: Text(
                              settlement.toUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.positive,
                                fontFamily: 'Outfit',
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$currency${settlement.amount % 1 == 0 ? settlement.amount.toStringAsFixed(0) : settlement.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Outfit',
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (settlement.note != null && settlement.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Note: ${settlement.note}',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Requested ${DateFormat('MMM d, y').format(settlement.requestedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            if (settlement.isPending) ...[
              if (settlement.toUserId == currentUserId) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.negative),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.button)),
                        ),
                        child: const Text('Reject',
                            style: TextStyle(
                                color: AppColors.negative, fontFamily: 'Outfit')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.positive,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.button)),
                        ),
                        child: const Text('Approve',
                            style: TextStyle(fontFamily: 'Outfit')),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Waiting for ${settlement.toUserName} to approve',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
