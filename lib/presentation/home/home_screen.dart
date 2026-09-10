import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/tour_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/services/balance_service.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/welcome_greeting_service.dart';
import '../../data/repositories/settlement_repository.dart';
import '../widgets/member_avatar.dart';
import '../expense/expense_list_tile.dart';
import '../expense/widgets/day_summary_table.dart';
import '../tour/widgets/tour_qr_dialog.dart';
import '../widgets/first_time_guide_dialog.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';
import '../settlement/widgets/receiver_payment_accounts_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirstTimeGuideDialog.checkAndShow(context);
    });

    final updateInfo = ref.watch(effectiveUpdateInfoProvider);
    final packageInfo = ref.watch(currentAppVersionProvider).value;
    if (updateInfo != null && packageInfo != null) {
      AppUpdateService.promptUpdateIfNeeded(
          context, updateInfo, packageInfo.version);
    }

    final currentUser = ref.watch(currentUserProvider);

    return currentUser.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (user) {
        if (user == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Setting up your account...'),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => ref.read(authServiceProvider).signOut(),
                      child: const Text('Back to Login'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (user.activeTourId == null) {
          return _NoActiveTourScreen(displayName: user.firstName);
        }

        return _ActiveTourDashboard(
          tourId: user.activeTourId!,
          userId: user.uid,
        );
      },
    );
  }
}

class _NoActiveTourScreen extends ConsumerStatefulWidget {
  final String displayName;
  final String? noticeMessage;

  const _NoActiveTourScreen({
    required this.displayName,
    this.noticeMessage,
  });

  @override
  ConsumerState<_NoActiveTourScreen> createState() => _NoActiveTourScreenState();
}

class _NoActiveTourScreenState extends ConsumerState<_NoActiveTourScreen> {
  int _greetingIndex = 0;

  List<String> _getGreetings(String name) {
    final clean = name.trim().isNotEmpty ? name.trim() : 'Explorer';
    final hour = DateTime.now().hour;
    final timeGreeting = (hour >= 5 && hour < 12)
        ? 'Good morning, $clean!'
        : (hour >= 12 && hour < 17)
            ? 'Good afternoon, $clean!'
            : (hour >= 17 && hour < 22)
                ? 'Good evening, $clean!'
                : 'Good evening, $clean!';

    return [
      timeGreeting,
      'Welcome, $clean!',
      'Hey there, $clean! 👋',
      'Ready for the next trip, $clean! 🎒',
      'Howdy, $clean! 🤠',
    ];
  }

  @override
  void initState() {
    super.initState();
    _greetingIndex = WelcomeGreetingService.sessionGreetingIndex;
    // Fallback if not initialized yet
    if (_greetingIndex == 0) {
      WelcomeGreetingService.advanceSessionGreeting().then((val) {
        if (mounted && _greetingIndex != val) {
          setState(() {
            _greetingIndex = val;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider).value;
    final greetings = _getGreetings(widget.displayName);
    final currentGreeting = greetings[_greetingIndex % greetings.length];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.noticeMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.noticeMessage!,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Trips',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => context.push('/profile'),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryTeal.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: MemberAvatar(
                            initials: currentUser?.initials.isNotEmpty == true
                                ? currentUser!.initials
                                : (widget.displayName.isNotEmpty
                                    ? widget.displayName[0].toUpperCase()
                                    : 'U'),
                            photoUrl: currentUser?.photoUrl,
                            radius: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_location_alt_rounded,
                        color: AppColors.primaryTeal,
                        size: 64,
                      ),
                    ).animate().fadeIn().scale(),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _greetingIndex++;
                        });
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.2),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          currentGreeting,
                          key: ValueKey<String>(currentGreeting),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Split expenses easily and keep the memories.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                        height: 1.4,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/tour/create'),
                        icon:
                            const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'Create Tour',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ).animate().fadeIn(delay: 250.ms),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 220,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/tour/join'),
                        icon:
                            const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text(
                          'Join Tour',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                          side: const BorderSide(
                              color: AppColors.primaryTeal, width: 1.5),
                        ),
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 220,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/tours'),
                        icon:
                            const Icon(Icons.luggage_rounded, size: 20),
                        label: const Text(
                          'View All Tours',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? AppColors.darkText
                              : AppColors.lightText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                          side: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 350.ms),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveTourDashboard extends ConsumerStatefulWidget {
  final String tourId;
  final String userId;

  const _ActiveTourDashboard({
    required this.tourId,
    required this.userId,
  });

  @override
  ConsumerState<_ActiveTourDashboard> createState() =>
      _ActiveTourDashboardState();
}

class _ActiveTourDashboardState extends ConsumerState<_ActiveTourDashboard> {
  int _selectedPillTab = 0;
  bool _showSpreadsheetView = true;
  String? _lastNotifiedJoinRequestId;
  bool _isJoinDialogActive = false;

  void _showFullScreenJoinRequestPopup(
    BuildContext context,
    TourModel tour,
    JoinRequestModel request,
  ) {
    setState(() => _isJoinDialogActive = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryTeal.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.primaryTeal,
                    size: 38,
                  ),
                ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 18),
                const Text(
                  'New Member Request! 👥',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'A traveler wants to join "${tour.name}"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    children: [
                      MemberAvatar(
                        initials: request.initials,
                        photoUrl: request.photoUrl,
                        radius: 26,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.displayName,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              request.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Pending Admin Approval',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryTeal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: OutlinedButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.of(ctx).pop();
                          await ref
                              .read(tourRepositoryProvider)
                              .rejectJoinRequest(
                                tourId: tour.id,
                                userId: request.userId,
                              );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Declined request from ${request.displayName}'),
                                backgroundColor: AppColors.negative,
                              ),
                            );
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.negative),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            color: AppColors.negative,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.of(ctx).pop();
                          await ref
                              .read(tourRepositoryProvider)
                              .approveJoinRequest(
                                tourId: tour.id,
                                request: request,
                              );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Approved! ${request.displayName} is now a member 🎉'),
                                backgroundColor: AppColors.positive,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 20),
                        label: const Text(
                          'Approve',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Decide Later',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isJoinDialogActive = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tourStream = ref.watch(tourStreamProvider(widget.tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(widget.tourId));
    final expensesStream = ref.watch(tourExpensesStreamProvider(widget.tourId));
    final settlementsStream =
        ref.watch(tourSettlementsStreamProvider(widget.tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                Text('Could not load tour: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => ref
                      .read(tourRepositoryProvider)
                      .clearUserActiveTour(widget.userId),
                  child: const Text('Return to Trips'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (tour) {
        if (tour == null || tour.isDeleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(tourRepositoryProvider).clearUserActiveTour(widget.userId);
          });
          return _NoActiveTourScreen(
            displayName:
                ref.read(currentUserProvider).value?.firstName ?? 'User',
            noticeMessage: 'The selected tour is no longer available.',
          );
        }

        final isMember = tour.memberIds.contains(widget.userId);
        final isPastMember = tour.isPastMember(widget.userId) ||
            (!isMember &&
                membersStream.maybeWhen(
                  data: (members) =>
                      members.any((m) => m.userId == widget.userId),
                  orElse: () => false,
                ));
        final isReadOnly = !isMember && isPastMember;

        if (!isMember && !isPastMember) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(tourRepositoryProvider).clearUserActiveTour(widget.userId);
          });
          return _NoActiveTourScreen(
            displayName:
                ref.read(currentUserProvider).value?.firstName ?? 'User',
            noticeMessage: 'You are no longer a member of "${tour.name}".',
          );
        }

        final isAdmin = tour.isAdmin(widget.userId);
        final joinRequestsStream =
            ref.watch(tourPendingJoinRequestsProvider(widget.tourId));

        final approvedExpenses = expensesStream.maybeWhen(
          data: (expenses) => expenses.where((e) => e.isApproved).toList(),
          orElse: () => <ExpenseModel>[],
        );

        final membersList = membersStream.maybeWhen(
          data: (members) => members,
          orElse: () => <TourMemberModel>[],
        );

        final approvedSettlements = settlementsStream.maybeWhen(
          data: (settlements) =>
              settlements.where((s) => s.isApproved).toList(),
          orElse: () => <SettlementModel>[],
        );

        var computedBalances =
            BalanceService.calculateBalances(membersList, approvedExpenses);
        computedBalances = BalanceService.applySettlements(
            computedBalances, approvedSettlements);
        final myNetBalance = computedBalances[widget.userId] ?? 0.0;

        final pendingRequests = joinRequestsStream.value ?? [];
        if (isAdmin &&
            pendingRequests.isNotEmpty &&
            !_isJoinDialogActive &&
            pendingRequests.first.id != _lastNotifiedJoinRequestId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isJoinDialogActive) {
              _lastNotifiedJoinRequestId = pendingRequests.first.id;
              _showFullScreenJoinRequestPopup(
                  context, tour, pendingRequests.first);
            }
          });
        }

        final updateInfo = ref.watch(effectiveUpdateInfoProvider);
        final packageInfo = ref.watch(currentAppVersionProvider).value;
        if (updateInfo != null && packageInfo != null) {
          AppUpdateService.promptUpdateIfNeeded(
              context, updateInfo, packageInfo.version);
        }

        final totalSpent =
            approvedExpenses.fold(0.0, (sum, e) => sum + e.amount);
        final memberCount = membersList.length;
        final expenseCount = expensesStream.maybeWhen(
          data: (expenses) => expenses.length,
          orElse: () => 0,
        );
        final perPerson = totalSpent / (memberCount > 0 ? memberCount : 1);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await ref
                .read(tourRepositoryProvider)
                .clearUserActiveTour(widget.userId);
          },
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                _TourDashboardAppBar(
                  tour: tour,
                  isAdmin: isAdmin,
                ),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (isAdmin) ...[
                      joinRequestsStream.when(
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                        data: (requests) {
                          if (requests.isEmpty) return const SizedBox();
                          return _PendingJoinRequestsDashboardCard(
                            tourId: tour.id,
                            requests: requests,
                          );
                        },
                      ),
                    ],
                    if (isReadOnly) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history_rounded,
                                color: AppColors.warning, size: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Archived Tour (Read-Only)',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'You are no longer an active member. Tour details remain visible until you delete it from your trips.',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Tour from List?'),
                                    content: Text(
                                        'Remove "${tour.name}" from your trips? You will no longer see this tour.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.danger),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ref
                                      .read(tourRepositoryProvider)
                                      .removeTourForUser(
                                          tour.id, widget.userId);
                                  ref
                                      .read(tourRepositoryProvider)
                                      .clearUserActiveTour(widget.userId);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.danger,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _ConsolidatedMetricsCard(
                      currencySymbol: tour.currencySymbol,
                      totalSpent: totalSpent,
                      perPerson: perPerson,
                      memberCount: memberCount,
                      expenseCount: expenseCount,
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 10),
                    _MyBalanceCard(
                      balance: myNetBalance,
                      currencySymbol: tour.currencySymbol,
                      onSettleUp: () => context.push('/settlement'),
                    ).animate().fadeIn(delay: 120.ms),
                    if (tour.budget != null && tour.budget! > 0) ...[
                      const SizedBox(height: 12),
                      _BudgetProgressBar(
                        budget: tour.budget!,
                        spent: totalSpent,
                        currencySymbol: tour.currencySymbol,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _SquareActionButton(
                          icon: Icons.description_outlined,
                          tooltip: 'Reports & PDF',
                          onTap: () => context.push('/reports'),
                        ),
                        const SizedBox(width: 8),
                        _SquareActionButton(
                          icon: Icons.qr_code_rounded,
                          tooltip: 'Tour QR',
                          onTap: () => TourQrDialog.show(
                            context,
                            tourName: tour.name,
                            inviteCode: tour.inviteCode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isReadOnly)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.lock_outline_rounded,
                                      size: 16, color: Colors.grey),
                                  SizedBox(width: 6),
                                  Text(
                                    'Read-Only Tour',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/expense/add'),
                              icon: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 20),
                              label: const Text(
                                'Add Expense',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryTeal,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),
                      ],
                    ).animate().fadeIn(delay: 150.ms),
                    const SizedBox(height: 16),
                    _PillTabBar(
                      selectedIndex: _selectedPillTab,
                      onTabChanged: (i) => setState(() => _selectedPillTab = i),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 16),
                    if (_selectedPillTab == 0) ...[
                      if (isAdmin) ...[
                        _PendingApprovalsSection(
                          tourId: widget.tourId,
                          currency: tour.currencySymbol,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildExpensesTab(
                          expensesStream, tour.currencySymbol, tour.startDate),
                    ] else if (_selectedPillTab == 1) ...[
                      _buildBalancesTab(membersList, computedBalances,
                          tour.currencySymbol, approvedExpenses),
                    ] else ...[
                      _buildSettlementsTab(membersList, computedBalances,
                          tour.currencySymbol, tour,
                          isReadOnly: isReadOnly),
                    ],
                    const SizedBox(height: 60),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
    },
    );
  }

  Widget _buildExpensesTab(AsyncValue expensesStream, String currencySymbol,
      DateTime tourStartDate) {
    return expensesStream.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (expenses) {
        final list = expenses as List<ExpenseModel>;
        if (list.isEmpty) {
          return _EmptyExpensesCard();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _showSpreadsheetView
                        ? 'Daily Expense Ledger'
                        : 'All Expenses',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFCBD5E1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewToggleButton(
                          icon: Icons.table_chart_rounded,
                          label: 'Sheet',
                          isSelected: _showSpreadsheetView,
                          onTap: () =>
                              setState(() => _showSpreadsheetView = true),
                        ),
                        _ViewToggleButton(
                          icon: Icons.view_agenda_rounded,
                          label: 'Cards',
                          isSelected: !_showSpreadsheetView,
                          onTap: () =>
                              setState(() => _showSpreadsheetView = false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_showSpreadsheetView) ...[
              ..._groupExpensesByDay(list, tourStartDate).map((group) {
                return DaySummaryTable(
                  dayNumber: group.dayNumber,
                  date: group.date,
                  expenses: group.expenses,
                  currencySymbol: currencySymbol,
                  onExpenseTap: (exp) => context.push('/expense/${exp.id}'),
                );
              }),
            ] else ...[
              ...list.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExpenseListTile(
                    expense: e,
                    currencySymbol: currencySymbol,
                    onTap: () => context.push('/expense/${e.id}'),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  List<({int dayNumber, DateTime date, List<ExpenseModel> expenses})>
      _groupExpensesByDay(List<ExpenseModel> expenses, DateTime tourStartDate) {
    final baseDate =
        DateTime(tourStartDate.year, tourStartDate.month, tourStartDate.day);
    final map = <DateTime, List<ExpenseModel>>{};

    for (final exp in expenses) {
      final d = DateTime(exp.date.year, exp.date.month, exp.date.day);
      map.putIfAbsent(d, () => []).add(exp);
    }

    final sortedDates = map.keys.toList()..sort();
    final result =
        <({int dayNumber, DateTime date, List<ExpenseModel> expenses})>[];

    for (final date in sortedDates) {
      final diffDays = date.difference(baseDate).inDays;
      final dayNumber = diffDays >= 0 ? diffDays + 1 : 1;
      final dayExpenses = map[date]!..sort((a, b) => a.date.compareTo(b.date));

      result.add((dayNumber: dayNumber, date: date, expenses: dayExpenses));
    }

    return result;
  }

  Widget _buildBalancesTab(
    List<TourMemberModel> list,
    Map<String, double> computedBalances,
    String currencySymbol,
    List<ExpenseModel> approvedExpenses,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalPaidMap =
        BalanceService.calculateTotalPaid(list, approvedExpenses);
    final totalSpentMap =
        BalanceService.calculateTotalSpent(list, approvedExpenses);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Member Balances',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Outfit',
                ),
              ),
              TextButton(
                onPressed: () => context.push('/tour/members'),
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Format: Total Paid (±Net Balance). Negative (-) owes, positive (+) gets back.',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white60 : Colors.black54,
              fontFamily: 'Outfit',
            ),
          ),
          const Divider(height: 20),
          ...list.map((m) {
            final totalPaid = totalPaidMap[m.userId] ?? 0.0;
            final totalSpent = totalSpentMap[m.userId] ?? 0.0;
            final balance = computedBalances[m.userId] ?? 0.0;
            final isPositive = balance > 0.01;
            final isNegative = balance < -0.01;
            final color = isPositive
                ? AppColors.positive
                : (isNegative
                    ? AppColors.negative
                    : (isDark ? Colors.white70 : Colors.black54));

            final balanceSign = isNegative ? '-' : (isPositive ? '+' : '');
            final balanceAbsFormatted = balance.abs().toStringAsFixed(0);
            final formattedPaid = totalPaid.toStringAsFixed(0);
            final formattedSpent = totalSpent.toStringAsFixed(0);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  MemberAvatar(
                    initials: m.initials,
                    photoUrl: m.photoUrl,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.displayName,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Paid: $currencySymbol$formattedPaid • Spent: $currencySymbol$formattedSpent',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$currencySymbol$formattedPaid ($balanceSign$currencySymbol$balanceAbsFormatted)',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPositive
                              ? 'Gets Back $currencySymbol$balanceAbsFormatted'
                              : (isNegative
                                  ? 'Owes $currencySymbol$balanceAbsFormatted'
                                  : 'Settled'),
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSettlementsTab(
    List<TourMemberModel> list,
    Map<String, double> computedBalances,
    String currencySymbol,
    TourModel tour, {
    bool isReadOnly = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final debts = BalanceService.simplifyDebts(computedBalances, list);

    final settlements =
        ref.watch(tourSettlementsStreamProvider(widget.tourId)).value ?? [];
    final pendingSettlements = settlements.where((s) => s.isPending).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.handshake_outlined,
                          size: 18, color: AppColors.primaryTeal),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Smart Settlements',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isReadOnly) ...[
                    InkWell(
                      onTap: () => ManualSettlementDialog.show(
                        context,
                        ref: ref,
                        tour: tour,
                        members: list,
                        computedBalances: computedBalances,
                        currentUserId: widget.userId,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 14, color: AppColors.primaryTeal),
                            SizedBox(width: 2),
                            Text(
                              'Manual',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => context.push('/settlement'),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryTeal,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            size: 15, color: AppColors.primaryTeal),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          if (pendingSettlements.isNotEmpty) ...[
            InkWell(
              onTap: () => context.push('/settlement'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${pendingSettlements.length} settlement${pendingSettlements.length > 1 ? 's' : ''} waiting for approval',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: AppColors.warning),
                  ],
                ),
              ),
            ),
          ],
          if (debts.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.positive, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All debts settled up',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...debts.map((d) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
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
                                  d.fromUserName,
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: AppColors.negative,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded,
                                    size: 13, color: Colors.grey),
                              ),
                              Flexible(
                                child: Text(
                                  d.toUserName,
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: AppColors.positive,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$currencySymbol${d.amount % 1 == 0 ? d.amount.toStringAsFixed(0) : d.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryTeal,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isReadOnly) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => _quickSettleDebt(d, currencySymbol),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          minimumSize: const Size(68, 34),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Settle',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/settlement'),
                icon: const Icon(Icons.sync_alt_rounded, size: 18),
                label: const Text('Record or Approve Settlements'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _quickSettleDebt(DebtTransaction debt, String currencySymbol) async {
    final noteCtrl = TextEditingController(text: 'Cash');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dialog)),
        title: const Text('Record Settlement'),
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
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      Text(
                        '$currencySymbol${debt.amount % 1 == 0 ? debt.amount.toStringAsFixed(0) : debt.amount.toStringAsFixed(2)}',
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
                ReceiverPaymentAccountsView(
                  toUserId: debt.toUserId,
                  toUserName: debt.toUserName,
                ),
                const SizedBox(height: 10),
                const Text('Note:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. bKash, Cash, Reference',
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
        tourId: widget.tourId,
        fromUserId: debt.fromUserId,
        fromUserName: debt.fromUserName,
        toUserId: debt.toUserId,
        toUserName: debt.toUserName,
        amount: debt.amount,
        currency: currencySymbol,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );

      final currentUid = ref.read(currentUserProvider).value?.uid;
      final isReceiver = currentUid == debt.toUserId;
      if (isReceiver) {
        await repo.resolveSettlement(
          tourId: widget.tourId,
          settlementId: settlement.id,
          status: SettlementStatus.approved,
          resolvedByUserId: currentUid ?? widget.userId,
        );
      }

      if (mounted) {
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
}

class _MyBalanceCard extends StatelessWidget {
  final double balance;
  final String currencySymbol;
  final VoidCallback onSettleUp;

  const _MyBalanceCard({
    required this.balance,
    required this.currencySymbol,
    required this.onSettleUp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPositive = balance > 0.01;
    final isNegative = balance < -0.01;

    final color = isPositive
        ? AppColors.positive
        : (isNegative ? AppColors.negative : AppColors.primaryTeal);

    final statusText = isPositive
        ? 'You are owed / To get back'
        : (isNegative ? 'You owe others / To pay' : 'All Settled Up (৳0)');

    final amountText = isPositive
        ? '+$currencySymbol${balance.toStringAsFixed(0)}'
        : (isNegative
            ? '-$currencySymbol${(-balance).toStringAsFixed(0)}'
            : '${currencySymbol}0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive
                  ? Icons.arrow_upward_rounded
                  : (isNegative
                      ? Icons.arrow_downward_rounded
                      : Icons.check_circle_outline_rounded),
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Net Balance',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              amountText,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsolidatedMetricsCard extends StatelessWidget {
  final String currencySymbol;
  final double totalSpent;
  final double perPerson;
  final int memberCount;
  final int expenseCount;

  const _ConsolidatedMetricsCard({
    required this.currencySymbol,
    required this.totalSpent,
    required this.perPerson,
    required this.memberCount,
    required this.expenseCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _MetricColumn(
            value: '$currencySymbol${totalSpent.toStringAsFixed(0)}',
            label: 'Total',
            color: AppColors.primaryTeal,
          ),
          _MetricDivider(isDark: isDark),
          _MetricColumn(
            value: '$currencySymbol${perPerson.toStringAsFixed(0)}',
            label: 'Per Person',
            color: AppColors.primaryTeal,
          ),
          _MetricDivider(isDark: isDark),
          _MetricColumn(
            label: 'Members',
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            onTap: () => context.push('/tour/members'),
            valueWidget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 17,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                const SizedBox(width: 4),
                Text(
                  '$memberCount',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          _MetricDivider(isDark: isDark),
          _MetricColumn(
            value: '$expenseCount',
            label: 'Expenses',
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String? value;
  final Widget? valueWidget;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _MetricColumn({
    this.value,
    this.valueWidget,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Column(
      children: [
        if (valueWidget != null)
          valueWidget!
        else
          Text(
            value ?? '',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );

    if (onTap != null) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: content,
            ),
          ),
        ),
      );
    }

    return Expanded(child: content);
  }
}

class _MetricDivider extends StatelessWidget {
  final bool isDark;
  const _MetricDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
    );
  }
}

class _BudgetProgressBar extends StatelessWidget {
  final double budget;
  final double spent;
  final String currencySymbol;

  const _BudgetProgressBar({
    required this.budget,
    required this.spent,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (spent / budget).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget: $currencySymbol${budget.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}% Spent',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ratio > 0.9 ? AppColors.danger : AppColors.primaryTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor:
                  isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio > 0.9 ? AppColors.danger : AppColors.primaryTeal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SquareActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Icon(icon, color: AppColors.primaryTeal, size: 22),
      ),
    );
  }
}

class _PillTabBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabChanged;

  const _PillTabBar({
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabs = ['Expenses', 'Balances', 'Settlements'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final title = entry.value;
          final isSelected = selectedIndex == i;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onTabChanged(i);
                HapticFeedback.selectionClick();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppColors.primaryTeal : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primaryTeal.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TourDashboardAppBar extends ConsumerWidget {
  final TourModel tour;
  final bool isAdmin;

  const _TourDashboardAppBar({
    required this.tour,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider).value;

    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        tooltip: 'Back to Home',
        onPressed: () async {
          if (currentUser != null) {
            await ref
                .read(tourRepositoryProvider)
                .clearUserActiveTour(currentUser.uid);
          }
        },
      ),
      title: InkWell(
        onTap: () => context.push('/tours'),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tour.name,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ),
              Text(
                '${tour.status == TourStatus.active ? '🟢 Active' : '⚪ Completed'} · ${tour.currency} · ${DateFormat('MMM d').format(tour.startDate)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.groups_rounded),
          tooltip: 'Members',
          onPressed: () => context.push('/tour/members'),
        ),
        if (isAdmin)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Tour Settings',
            onPressed: () => context.push('/tour/settings'),
          ),
        InkWell(
          onTap: () => context.push('/profile'),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 14),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryTeal.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: MemberAvatar(
                initials: currentUser?.initials.isNotEmpty == true
                    ? currentUser!.initials
                    : 'U',
                photoUrl: currentUser?.photoUrl,
                radius: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyExpensesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primaryTeal,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Expenses Yet',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => context.push('/expense/add'),
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            label: const Text('Add Expense',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingApprovalsSection extends ConsumerWidget {
  final String tourId;
  final String currency;

  const _PendingApprovalsSection({
    required this.tourId,
    required this.currency,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingStream = ref.watch(pendingExpensesStreamProvider(tourId));

    return pendingStream.when(
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
      data: (pending) {
        if (pending.isEmpty) return const SizedBox();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.pending_actions_rounded,
                      color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text(
                    '${pending.length} Pending Approval',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...pending.take(3).map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${e.title} ($currency${e.amount.toStringAsFixed(0)}) by ${e.paidByName}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline,
                              color: AppColors.positive),
                          onPressed: () => ref
                              .read(expenseRepositoryProvider)
                              .updateExpenseStatus(
                                  tourId, e.id, ExpenseStatus.approved),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined,
                              color: AppColors.negative),
                          onPressed: () => ref
                              .read(expenseRepositoryProvider)
                              .updateExpenseStatus(
                                  tourId, e.id, ExpenseStatus.rejected),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _PendingJoinRequestsDashboardCard extends ConsumerWidget {
  final String tourId;
  final List<JoinRequestModel> requests;

  const _PendingJoinRequestsDashboardCard({
    required this.tourId,
    required this.requests,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppColors.primaryTeal.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded,
                  color: AppColors.primaryTeal, size: 22),
              const SizedBox(width: 8),
              Text(
                '${requests.length} Join Request${requests.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.primaryTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...requests.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    MemberAvatar(
                      initials:
                          r.displayName.isNotEmpty ? r.displayName[0] : '?',
                      photoUrl: r.photoUrl,
                      radius: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          Text(
                            r.email,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.danger),
                      tooltip: 'Reject',
                      onPressed: () => ref
                          .read(tourRepositoryProvider)
                          .rejectJoinRequest(tourId: tourId, userId: r.userId),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => ref
                          .read(tourRepositoryProvider)
                          .approveJoinRequest(tourId: tourId, request: r),
                      icon: const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white),
                      label: const Text('Approve',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewToggleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
