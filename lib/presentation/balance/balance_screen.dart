import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/balance_service.dart';
import '../../data/models/tour_model.dart';
import '../../data/models/settlement_model.dart';
import '../widgets/member_avatar.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';

class BalanceScreen extends ConsumerWidget {
  const BalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }
    final tourId = user.activeTourId!;

    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));
    final expensesStream = ref.watch(approvedExpensesStreamProvider(tourId));
    final settlementsStream = ref.watch(tourSettlementsStreamProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null || tour.isDeleted) {
          return Scaffold(
            appBar: AppBar(title: const Text('Balances')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('The tour is no longer available.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          );
        }

        return membersStream.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (members) => expensesStream.when(
            loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator())),
            error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
            data: (expenses) => settlementsStream.when(
              loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator())),
              error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
              data: (settlements) {
                final approvedSettlements =
                    settlements.where((s) => s.isApproved).toList();

                var balances =
                    BalanceService.calculateBalances(members, expenses);
                balances = BalanceService.applySettlements(
                    balances, approvedSettlements);
                final debts = BalanceService.simplifyDebts(balances, members);
                final totalPaidMap =
                    BalanceService.calculateTotalPaid(members, expenses);
                final isDark = Theme.of(context).brightness == Brightness.dark;

                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  child: Scaffold(
                    appBar: AppBar(
                      title: const Text('Balances'),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        tooltip: 'Back',
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.handshake_rounded,
                              color: AppColors.primaryTeal),
                          tooltip: 'Manual Settlement',
                          onPressed: () => ManualSettlementDialog.show(
                            context,
                            ref: ref,
                            tour: tour,
                            members: members,
                            computedBalances: balances,
                            currentUserId: user.uid,
                          ),
                        ),
                      ],
                    ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Balance Overview',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Format: Total Paid (±Net Balance). Negative (-) owes, positive (+) gets back.',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => ManualSettlementDialog.show(
                                context,
                                ref: ref,
                                tour: tour,
                                members: members,
                                computedBalances: balances,
                                currentUserId: user.uid,
                              ),
                              icon: const Icon(Icons.handshake_rounded,
                                  size: 15, color: Colors.white),
                              label: const Text(
                                'Manual Settle',
                                style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...members.map((m) {
                        final balance = balances[m.userId] ?? 0.0;
                        final totalPaid = totalPaidMap[m.userId] ?? 0.0;
                        return _BalanceCard(
                          member: m,
                          balance: balance,
                          totalPaid: totalPaid,
                          currency: tour.currencySymbol,
                          currentUserId: user.uid,
                        ).animate().fadeIn(
                            delay:
                                Duration(milliseconds: members.indexOf(m) * 60),
                            duration: 300.ms);
                      }),
                      const SizedBox(height: 24),
                      Text('Who Owes Whom',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (debts.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Column(
                              children: [
                                Text('🎉', style: TextStyle(fontSize: 36)),
                                SizedBox(height: 8),
                                Text('All Settled!',
                                    style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accent)),
                              ],
                            ),
                          ),
                        )
                      else
                        ...debts.map((d) => _DebtCard(
                              debt: d,
                              currency: tour.currencySymbol,
                              currentUserId: user.uid,
                              onSettle: () => _requestSettlement(
                                  context, ref, tourId, d, tour.currency),
                            ).animate().fadeIn()),
                    ],
                  ),
                ),
              );
              },
            ),
          ),
        );
      },
    );
  }

  void _requestSettlement(BuildContext context, WidgetRef ref, String tourId,
      DebtTransaction debt, String currency) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Settlement'),
        content: Text(
            '${debt.fromUserName} will pay ${debt.toUserName} the amount shown. Request settlement?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Request')),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(settlementRepositoryProvider).requestSettlement(
            tourId: tourId,
            fromUserId: debt.fromUserId,
            fromUserName: debt.fromUserName,
            toUserId: debt.toUserId,
            toUserName: debt.toUserName,
            amount: debt.amount,
            currency: currency,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settlement requested. Waiting for admin approval.'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final TourMemberModel member;
  final double balance;
  final double totalPaid;
  final String currency;
  final String currentUserId;

  const _BalanceCard({
    required this.member,
    required this.balance,
    required this.totalPaid,
    required this.currency,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPositive = balance > 0.01;
    final isNegative = balance < -0.01;
    final isSettled = !isPositive && !isNegative;

    Color balanceColor = isPositive
        ? AppColors.positive
        : isNegative
            ? AppColors.negative
            : (isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary);

    final balanceSign = isNegative ? '-' : (isPositive ? '+' : '');
    final balanceAbsFormatted = balance.abs().toStringAsFixed(0);
    final formattedPaid = totalPaid.toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            MemberAvatar(
              initials: member.initials,
              photoUrl: member.photoUrl,
              radius: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName +
                        (member.userId == currentUserId ? ' (You)' : ''),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Paid: $currency$formattedPaid • ${member.isOffline ? "Offline" : (member.role == "admin" ? "Admin" : "Member")}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isSettled
                          ? 0
                          : (balance.abs() / (balance.abs() + 1))
                              .clamp(0.0, 1.0),
                      backgroundColor:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      valueColor: AlwaysStoppedAnimation(balanceColor),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency$formattedPaid ($balanceSign$currency$balanceAbsFormatted)',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: balanceColor,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: balanceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPositive
                        ? 'Gets Back $currency$balanceAbsFormatted'
                        : (isNegative
                            ? 'Owes $currency$balanceAbsFormatted'
                            : 'Settled'),
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: balanceColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final DebtTransaction debt;
  final String currency;
  final String currentUserId;
  final VoidCallback onSettle;

  const _DebtCard({
    required this.debt,
    required this.currency,
    required this.currentUserId,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInvolved =
        debt.fromUserId == currentUserId || debt.toUserId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isInvolved ? AppColors.primaryBlue.withValues(alpha: 0.06) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: debt.fromUserName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.negative,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const TextSpan(text: ' owes '),
                    TextSpan(
                      text: debt.toUserName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.positive,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    TextSpan(
                      text: '\n$currency ${debt.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Outfit',
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (debt.fromUserId == currentUserId)
              TextButton(
                onPressed: onSettle,
                child: const Text('Settle Up',
                    style: TextStyle(
                        fontFamily: 'Outfit',
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
