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

class BalanceScreen extends ConsumerWidget {
  const BalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
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
        if (tour == null) return const Scaffold();

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

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Balances'),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...members.map((m) {
                        final balance = balances[m.userId] ?? 0.0;
                        return _BalanceCard(
                          member: m,
                          balance: balance,
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
                            color: AppColors.accent.withOpacity(0.1),
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
  final String currency;
  final String currentUserId;

  const _BalanceCard({
    required this.member,
    required this.balance,
    required this.currency,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPositive = balance > 0;
    final isNegative = balance < 0;
    final isSettled = balance.abs() < 0.01;

    Color balanceColor = isPositive
        ? AppColors.positive
        : isNegative
            ? AppColors.negative
            : (isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary);

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
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
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
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isSettled
                      ? 'Settled'
                      : '${isPositive ? '+' : ''}$currency ${balance.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: balanceColor,
                  ),
                ),
                if (!isSettled)
                  Text(
                    isPositive ? 'Gets back' : '⚠ In loan',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11,
                      color: balanceColor,
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
      color: isInvolved ? AppColors.primaryBlue.withOpacity(0.06) : null,
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
