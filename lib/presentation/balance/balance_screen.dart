import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/user_cache_service.dart';
import '../widgets/member_avatar.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';
import '../widgets/app_bottom_nav_bar.dart';

class BalanceScreen extends ConsumerWidget {
  final String? tourId;
  const BalanceScreen({super.key, this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final activeTourId = ref.watch(activeTourIdProvider);
    final effectiveTourId = tourId ??
        activeTourId ??
        user?.activeTourId ??
        cachedTour?.id ??
        ActiveTourCacheService.getActiveTourId();

    if (effectiveTourId == null) {
      if (userAsync.isLoading) {
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      }
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final currentUserId =
        user?.uid ?? ref.watch(authStateProvider).value?.uid ?? '';
    final tourStream = ref.watch(tourStreamProvider(effectiveTourId));
    final membersStream = ref.watch(tourMembersStreamProvider(effectiveTourId));
    final expensesStream =
        ref.watch(approvedExpensesStreamProvider(effectiveTourId));
    final settlementsStream =
        ref.watch(tourSettlementsStreamProvider(effectiveTourId));

    final effectiveTour = tourStream.value ?? (cachedTour?.id == effectiveTourId ? cachedTour : null) ?? cachedTour;
    if (effectiveTour == null && tourStream.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tour = effectiveTour ?? tourStream.value;
    if (tour == null || tour.isDeleted) {
      if (tourStream.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
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

    final cachedMembers = ActiveTourCacheService.getCachedMembers(effectiveTourId);
    final rawMembers = membersStream.value ?? cachedMembers;
    final List<TourMemberModel> members;
    if (rawMembers.isNotEmpty) {
      members = rawMembers;
    } else {
      members = [];
      final ids = tour.memberIds.isNotEmpty
          ? tour.memberIds
          : (currentUserId.isNotEmpty ? [currentUserId] : <String>[]);
      for (final uid in ids) {
        final cached = UserCacheService.getUser(uid);
        members.add(
          TourMemberModel(
            userId: uid,
            displayName: cached?.displayName ??
                (uid == currentUserId ? (user?.displayName ?? 'You') : 'Member'),
            username: cached?.username ?? '',
            email: uid == currentUserId ? (user?.email ?? '') : '',
            photoUrl: cached?.photoUrl ??
                (uid == currentUserId ? user?.photoUrl : null),
            role: tour.isAdmin(uid) ? 'admin' : 'member',
            status: 'active',
            joinedAt: tour.createdAt,
            balance: 0.0,
            isOffline: uid.startsWith('offline_'),
          ),
        );
      }
    }

    ref.watch(localExpensesRefreshProvider);
    final cachedExpenses = ActiveTourCacheService.getCachedExpenses(effectiveTourId);
    final queuedExpenses = ref.watch(offlineExpenseQueueProvider).getQueuedExpenses(tourId: effectiveTourId);
    final deletedIds = ref.watch(offlineExpenseQueueProvider).getQueuedDeletedExpenseIds(tourId: effectiveTourId);
    final streamExpenses = expensesStream.value ?? cachedExpenses;
    final expenses = [
      ...queuedExpenses,
      ...streamExpenses.where((e) => !queuedExpenses.any((q) => q.id == e.id)),
    ].where((e) => !deletedIds.contains(e.id)).toList();

    final settlements = settlementsStream.value ??
        ActiveTourCacheService.getCachedSettlements(effectiveTourId);
    final approvedSettlements = settlements.where((s) => s.isApproved).toList();

    var balances = BalanceService.calculateBalances(members, expenses);
    balances = BalanceService.applySettlements(balances, approvedSettlements);
    final debts = BalanceService.simplifyDebts(balances, members);
    final totalPaidMap = BalanceService.calculateTotalPaid(members, expenses);
    final totalSpentMap = BalanceService.calculateTotalSpent(members, expenses);
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
                      automaticallyImplyLeading: false,
                      toolbarHeight: 64,
                      titleSpacing: 20,
                      title: const Text(
                        'Balances',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: Icon(Icons.handshake_rounded,
                              color: isDark ? Colors.white : const Color(0xFF0F172A)),
                          tooltip: 'Manual Settlement',
                          onPressed: () => ManualSettlementDialog.show(
                            context,
                            ref: ref,
                            tour: tour,
                            members: members,
                            computedBalances: balances,
                            currentUserId: currentUserId,
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
                                currentUserId: currentUserId,
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
                        final totalSpent = totalSpentMap[m.userId] ?? 0.0;
                        return _BalanceCard(
                          member: m,
                          balance: balance,
                          totalPaid: totalPaid,
                          totalSpent: totalSpent,
                          currency: tour.currencySymbol,
                          currentUserId: currentUserId,
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
                                Icon(Icons.check_circle_rounded,
                                    size: 40, color: AppColors.accent),
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
                              currentUserId: currentUserId,
                              onSettle: () => _requestSettlement(
                                  context, ref, effectiveTourId, d, tour.currency),
                            ).animate().fadeIn()),
                    ],
                  ),
                  bottomNavigationBar: TourBottomNavigationBar(
                    tour: tour,
                    isAdmin: tour.isAdmin(currentUserId),
                    currentUser: user,
                    membersCount: members.length,
                    currentIndex: -1,
                    onToursTap: () => context.push('/tours'),
                    onDashboardTap: () {
                      ref.read(activeTourIdOverrideProvider.notifier).state =
                          tour.id;
                      ActiveTourCacheService.setActiveTourId(tour.id);
                      context.go('/home');
                    },
                    onMembersTap: () =>
                        context.push('/tour/members?tourId=${tour.id}'),
                    onSettingsTap: tour.isAdmin(currentUserId)
                        ? () => context.push('/tour/settings?tourId=${tour.id}')
                        : null,
                  ),
                ),
              );
  }

  void _requestSettlement(BuildContext context, WidgetRef ref, String tourId,
      DebtTransaction debt, String currency) async {
    final members = ref.read(tourMembersStreamProvider(tourId)).value ?? [];
    final toMember =
        members.firstWhereOrNull((m) => m.userId == debt.toUserId);
    final isOfflineReceiver =
        toMember?.isOffline == true || debt.toUserId.startsWith('offline_');
    final currentUid = ref.read(currentUserProvider).value?.uid;
    final isReceiver = currentUid == debt.toUserId;
    final shouldAutoApprove = isReceiver || isOfflineReceiver;

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
            autoApprove: shouldAutoApprove,
            resolvedByUserId: currentUid,
          );
      if (context.mounted) {
        final message = isOfflineReceiver
            ? 'Settlement recorded and auto-approved for offline member.'
            : (isReceiver
                ? 'Settlement recorded and approved!'
                : 'Settlement requested. Waiting for ${debt.toUserName} to approve.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
  final double totalSpent;
  final String currency;
  final String currentUserId;

  const _BalanceCard({
    required this.member,
    required this.balance,
    required this.totalPaid,
    required this.totalSpent,
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
    final formattedSpent = totalSpent.toStringAsFixed(0);

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
              userId: member.userId,
              tourMember: member,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: member.userId == currentUserId
                    ? () {
                        HapticFeedback.lightImpact();
                        context.push('/profile');
                      }
                    : null,
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
                    'Paid: $currency$formattedPaid • Spent: $currency$formattedSpent',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: debt.fromUserId == currentUserId
                              ? () {
                                  HapticFeedback.lightImpact();
                                  context.push('/profile');
                                }
                              : null,
                          child: Text(
                            debt.fromUserName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.negative,
                              fontFamily: 'Outfit',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const Text(' owes ',
                          style: TextStyle(fontFamily: 'Outfit')),
                      Flexible(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: debt.toUserId == currentUserId
                              ? () {
                                  HapticFeedback.lightImpact();
                                  context.push('/profile');
                                }
                              : null,
                          child: Text(
                            debt.toUserName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.positive,
                              fontFamily: 'Outfit',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency ${debt.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Outfit',
                      fontSize: 16,
                    ),
                  ),
                ],
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
