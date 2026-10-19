import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/balance_service.dart';
import '../../data/models/tour_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/user_cache_service.dart';
import '../widgets/member_avatar.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/app_notification_sheet.dart';

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
    final streamExpenses = expensesStream.value ?? [];

    final Map<String, ExpenseModel> allExpensesMap = {};
    for (final e in queuedExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap[e.id] = e;
      }
    }
    for (final e in cachedExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap.putIfAbsent(e.id, () => e);
      }
    }
    for (final e in streamExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap[e.id] = e;
      }
    }
    final expenses = allExpensesMap.values.where((e) => e.isApproved).toList();

    ref.watch(localSettlementsRefreshProvider);
    final cachedSettlements = ActiveTourCacheService.getCachedSettlements(effectiveTourId);
    final streamSettlements = settlementsStream.value ?? [];
    final Map<String, SettlementModel> settlementsMap = {};
    for (final s in streamSettlements) {
      settlementsMap[s.id] = s;
    }
    for (final s in cachedSettlements) {
      settlementsMap[s.id] = s;
    }
    final settlements = settlementsMap.values.toList();
    final approvedSettlements = settlements.where((s) => s.isApproved).toList();

    var balances = BalanceService.calculateBalances(members, expenses);
    balances = BalanceService.applySettlements(balances, approvedSettlements);
    final debts = BalanceService.simplifyDebts(balances, members);
    final totalPaidMap =
        BalanceService.calculateTotalPaid(members, expenses, approvedSettlements);
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : AppColors.lightBorder,
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Member Balances',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => ManualSettlementDialog.show(
                                    context,
                                    ref: ref,
                                    tour: tour,
                                    members: members,
                                    computedBalances: balances,
                                    currentUserId: currentUserId,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add_rounded, size: 14, color: AppColors.primaryTeal),
                                        SizedBox(width: 2),
                                        Text(
                                          'Manual Settle',
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryTeal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            for (int i = 0; i < members.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : const Color(0xFFF1F5F9),
                                ),
                              Builder(builder: (context) {
                                final m = members[i];
                                final balance = balances[m.userId] ?? 0.0;
                                final totalPaid = totalPaidMap[m.userId] ?? 0.0;
                                final isPositive = balance > 0.01;
                                final isNegative = balance < -0.01;
                                final isSettled = !isPositive && !isNegative;
                                final balanceAbsFormatted = balance.abs().toStringAsFixed(0);
                                final formattedPaid = totalPaid.toStringAsFixed(0);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  child: Row(
                                    children: [
                                      MemberAvatar(
                                        initials: m.initials,
                                        photoUrl: m.photoUrl,
                                        radius: 19,
                                        userId: m.userId,
                                        tourMember: m,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: m.userId == currentUserId
                                              ? () {
                                                  HapticFeedback.lightImpact();
                                                  context.push('/profile');
                                                }
                                              : null,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                m.displayName + (m.userId == currentUserId ? ' (You)' : ''),
                                                style: const TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14.5,
                                                  letterSpacing: -0.2,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Paid ${tour.currencySymbol}$formattedPaid',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? AppColors.darkTextSecondary
                                                      : AppColors.lightTextSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (isSettled)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.05)
                                                : Colors.black.withValues(alpha: 0.04),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.08)
                                                  : Colors.black.withValues(alpha: 0.06),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 5,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isDark ? Colors.white38 : Colors.black38,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                'Settled',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white70 : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (isPositive)
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '+${tour.currencySymbol}$balanceAbsFormatted',
                                              style: const TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.positive,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'GETS BACK',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                                color: AppColors.positive,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '-${tour.currencySymbol}$balanceAbsFormatted',
                                              style: const TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.negative,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'OWES',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                                color: AppColors.negative,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : AppColors.lightBorder,
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Who Owes Whom',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (debts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 34,
                                        color: isDark ? Colors.white38 : Colors.black38,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'All Settled Up',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'No outstanding debts between members',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 12,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              for (int i = 0; i < debts.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFF1F5F9),
                                  ),
                                Builder(builder: (context) {
                                  final d = debts[i];
                                  final formattedAmt = d.amount % 1 == 0
                                      ? d.amount.toStringAsFixed(0)
                                      : d.amount.toStringAsFixed(2);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.05)
                                                : const Color(0xFFF1F5F9),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.08)
                                                  : const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: const Icon(Icons.swap_horiz_rounded,
                                              size: 20, color: AppColors.primaryTeal),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      d.fromUserName,
                                                      style: const TextStyle(
                                                        fontFamily: 'Outfit',
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 14,
                                                        letterSpacing: -0.2,
                                                        color: AppColors.negative,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5),
                                                    child: Icon(
                                                      Icons.arrow_forward_rounded,
                                                      size: 12,
                                                      color: isDark ? Colors.white38 : Colors.black38,
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      d.toUserName,
                                                      style: const TextStyle(
                                                        fontFamily: 'Outfit',
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 14,
                                                        letterSpacing: -0.2,
                                                        color: AppColors.primaryTeal,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${tour.currencySymbol}$formattedAmt to settle',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? AppColors.darkTextSecondary
                                                      : AppColors.lightTextSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        InkWell(
                                          onTap: () => _requestSettlement(
                                              context, ref, effectiveTourId, d, tour.currency),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryTeal,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'Settle',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                          ],
                        ),
                      ),
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
    final cached = ActiveTourCacheService.getCachedSettlements(tourId);
    final isAlreadyPending = cached.any((s) =>
        s.fromUserId == debt.fromUserId &&
        s.toUserId == debt.toUserId &&
        s.status == SettlementStatus.requested);
    if (isAlreadyPending) {
      showAppNotificationSheet(
        context,
        icon: Icons.hourglass_top_rounded,
        iconColor: AppColors.warning,
        title: 'Settlement In Progress',
        message:
            'A settlement between ${debt.fromUserName} and ${debt.toUserName} is already being processed.',
      );
      return;
    }

    final currentUid = ref.read(currentUserProvider).value?.uid;

    final confirm = await showAppConfirmationSheet(
      context,
      icon: Icons.payments_rounded,
      iconColor: AppColors.primaryTeal,
      title: 'Request Settlement',
      message:
          '${debt.fromUserName} will pay ${debt.toUserName} the amount shown ($currency ${debt.amount.toStringAsFixed(0)}). Request settlement?',
      confirmText: 'Request',
    );

    if (confirm == true) {
      const shouldAutoApprove = true;
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
      ref.read(localSettlementsRefreshProvider.notifier).bump();
      if (context.mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Settlement Approved',
          message: 'Settlement recorded and approved! Balances adjusted.',
          primaryButtonText: 'Done',
        );
      }
    }
  }
}
