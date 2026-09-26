import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_cache_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/tour_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/services/balance_service.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/welcome_greeting_service.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/chat_sync_service.dart';
import '../widgets/member_avatar.dart';
import '../widgets/theme_switch_toggle.dart';
import '../expense/expense_list_tile.dart';
import '../expense/widgets/day_summary_table.dart';
import '../tour/widgets/tour_qr_dialog.dart';
import '../widgets/first_time_guide_dialog.dart';
import '../widgets/whats_new_dialog.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';
import '../settlement/widgets/receiver_payment_accounts_view.dart';
import '../chat/widgets/messenger_chat_head.dart';
import '../widgets/app_bottom_nav_bar.dart';

/// Bump this to force _ActiveTourBody to re-read getCachedMembers() from Hive.
/// Used after adding an offline member locally so the UI reflects the change immediately.
class _LocalMembersRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final localMembersRefreshProvider =
    NotifierProvider<_LocalMembersRefreshNotifier, int>(_LocalMembersRefreshNotifier.new);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirstTimeGuideDialog.checkAndShow(context);
      WhatsNewDialog.checkAndShow(context);
    });

    final updateInfo = ref.watch(effectiveUpdateInfoProvider);
    final packageInfo = ref.watch(currentAppVersionProvider).value;
    if (updateInfo != null && packageInfo != null) {
      AppUpdateService.promptUpdateIfNeeded(
          context, updateInfo, packageInfo.version);
    }

    final currentUser = ref.watch(currentUserProvider);
    final authUser = ref.watch(authServiceProvider).currentUser;
    final activeTourId = ref.watch(activeTourIdProvider);

    return currentUser.when(
      loading: () {
        final effId = activeTourId;
        if (effId != null && authUser != null) {
          return _ActiveTourDashboard(
            key: ValueKey(effId),
            tourId: effId,
            userId: authUser.uid,
          );
        }
        // Offline + no cached tour: Firebase Auth has the user locally,
        // so show the landing screen instead of spinning forever.
        if (authUser != null) {
          final name = (authUser.displayName ?? '').split(' ').first;
          return _NoActiveTourScreen(
            displayName: name.isNotEmpty ? name : 'Explorer',
          );
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
      error: (e, _) {
        final effId = activeTourId;
        if (effId != null && authUser != null) {
          return _ActiveTourDashboard(
            key: ValueKey(effId),
            tourId: effId,
            userId: authUser.uid,
          );
        }
        if (authUser != null) {
          final name = (authUser.displayName ?? '').split(' ').first;
          return _NoActiveTourScreen(
            displayName: name.isNotEmpty ? name : 'Explorer',
          );
        }
        return Scaffold(body: Center(child: Text('Error: $e')));
      },
      data: (user) {
        if (user == null) {
          final effId = activeTourId;
          if (effId != null && authUser != null) {
            return _ActiveTourDashboard(
              key: ValueKey(effId),
              tourId: effId,
              userId: authUser.uid,
            );
          }
          if (authUser != null) {
            final name = (authUser.displayName ?? '').split(' ').first;
            return _NoActiveTourScreen(
              displayName: name.isNotEmpty ? name : 'Explorer',
            );
          }
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

        final effectiveTourId = activeTourId;
        if (effectiveTourId == null) {
          return _NoActiveTourScreen(displayName: user.firstName);
        }

        return _ActiveTourDashboard(
          key: ValueKey(effectiveTourId),
          tourId: effectiveTourId,
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
      'Ready for the next trip, $clean?',
      'Adventure awaits, $clean!',
      'Where to next, $clean?',
      'Pack your bags, $clean!',
      'Wanderlust calling, $clean!',
      'Great to see you, $clean!',
      'Split smart, travel far, $clean!',
      'New memories await, $clean!',
      'Hey there, $clean!',
      'Howdy, $clean!',
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
    final toursStream = currentUser != null
        ? ref.watch(userToursStreamProvider(currentUser.uid))
        : null;
    final activeToursCount =
        toursStream?.value?.where((t) => t.isActive).length ?? 0;
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'TourSplit',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.primaryTeal,
                      height: 1.1,
                    ),
                  ),
                  const ThemeSwitchToggle(height: 36, width: 62),
                ],
              ),
              const Spacer(flex: 2),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/tour/create'),
                        icon: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 20),
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
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 1.0,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
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
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
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
                        icon: const Icon(Icons.luggage_rounded, size: 20),
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
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                          side: BorderSide(
                            color:
                                isDark ? AppColors.darkBorder : Colors.black,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 350.ms),
                  ],
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
      bottomNavigationBar: HomeBottomNavigationBar(
        currentIndex: 0,
        activeToursCount: activeToursCount,
        currentUser: currentUser,
        onHomeTap: () {},
        onToursTap: () => context.push('/tours'),
        onProfileTap: () => context.push('/profile'),
      ),
    );
  }
}

class _ActiveTourDashboard extends ConsumerStatefulWidget {
  final String tourId;
  final String userId;

  const _ActiveTourDashboard({
    super.key,
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
                  'New Member Request',
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
                        userId: request.userId,
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
                                    'Approved! ${request.displayName} is now a member.'),
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
    final currentUser = ref.watch(currentUserProvider).value;
    final syncService = ref.watch(chatSyncServiceProvider);
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final effectiveTour = tourStream.value ??
        (cachedTour?.id == widget.tourId ? cachedTour : null) ??
        ref.read(tourRepositoryProvider).getLocalTour(widget.tourId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncService.setActiveTour(widget.tourId,
          tourName: effectiveTour?.name);
    });

    if (effectiveTour == null) {
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
        data: (_) => const Scaffold(),
      );
    }

    final tour = effectiveTour;
    if (tour.isDeleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(tourRepositoryProvider).clearUserActiveTour(widget.userId);
      });
      return _NoActiveTourScreen(
        displayName:
            ref.read(currentUserProvider).value?.firstName ?? 'User',
        noticeMessage: 'The selected tour is no longer available.',
      );
    }

    final isMember = tour.memberIds.contains(widget.userId) || tour.isAdmin(widget.userId);
    final isPastMember = tour.isPastMember(widget.userId) ||
        (!isMember &&
            membersStream.maybeWhen(
              data: (members) =>
                  members.any((m) => m.userId == widget.userId),
              orElse: () => false,
            ));
    final isReadOnly = !isMember && isPastMember;

    if (!isMember && !isPastMember) {
      if (tourStream.value != null && !membersStream.isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(tourRepositoryProvider).clearUserActiveTour(widget.userId);
        });
        return _NoActiveTourScreen(
          displayName:
              ref.read(currentUserProvider).value?.firstName ?? 'User',
          noticeMessage: 'You are no longer a member of "${tour.name}".',
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAdmin = tour.isAdmin(widget.userId);
    final joinRequestsStream =
        ref.watch(tourPendingJoinRequestsProvider(widget.tourId));

    // Watch the local refresh counter — bumped when an offline member is added
    ref.watch(localMembersRefreshProvider);

    final cachedMembers = ActiveTourCacheService.getCachedMembers(widget.tourId);

    // Build the effective member list by merging the Firestore stream with the Hive cache.
    // The stream is the authoritative source when online, but it won't include members that
    // were added offline (queued in Hive). We always append cached-only members on top so
    // offline-queued members appear immediately after being added.
    final streamMembers = membersStream.maybeWhen(
      data: (members) => members,
      orElse: () => <TourMemberModel>[],
    );
    final List<TourMemberModel> rawMembers;
    if (streamMembers.isNotEmpty) {
      // Start with stream data; append any cached member not already in the stream
      // (covers offline-queued members whose Firestore write is pending)
      final extra = cachedMembers
          .where((c) => !streamMembers.any((s) => s.userId == c.userId))
          .toList();
      rawMembers = [...streamMembers, ...extra];
    } else {
      // Fully offline: use Hive cache (includes offline-queued members)
      rawMembers = cachedMembers;
    }

    final List<TourMemberModel> membersList;
    if (rawMembers.isNotEmpty) {
      membersList = rawMembers;
    } else {
      membersList = [];
      final ids = tour.memberIds.isNotEmpty
          ? tour.memberIds
          : (widget.userId.isNotEmpty ? [widget.userId] : <String>[]);

      // Build a lookup map of queued offline member names so we can resolve
      // proper display names even when cache and stream are both empty
      final queuedMemberNames = <String, String>{};
      try {
        final queueService = ref.read(offlineTourQueueProvider);
        for (final qm in queueService.getQueuedMembersForTour(widget.tourId)) {
          queuedMemberNames[qm.userId] = qm.displayName;
        }
      } catch (_) {}

      for (final uid in ids) {
        final cached = UserCacheService.getUser(uid);
        membersList.add(
          TourMemberModel(
            userId: uid,
            displayName: cached?.displayName ??
                queuedMemberNames[uid] ??
                (uid == widget.userId
                    ? (currentUser?.displayName ?? 'You')
                    : (uid.startsWith('offline_') ? 'Offline Friend' : 'Member')),
            username: cached?.username ?? '',
            email: uid == widget.userId ? (currentUser?.email ?? '') : '',
            photoUrl: cached?.photoUrl ??
                (uid == widget.userId ? currentUser?.photoUrl : null),
            role: tour.isAdmin(uid) ? 'admin' : 'member',
            status: 'active',
            joinedAt: tour.createdAt,
            balance: 0.0,
            isOffline: uid.startsWith('offline_'),
          ),
        );
      }
      if (membersList.isEmpty && widget.userId.isNotEmpty) {
        membersList.add(
          TourMemberModel(
            userId: widget.userId,
            displayName: currentUser?.displayName ?? 'You',
            username: currentUser?.username ?? '',
            email: currentUser?.email ?? '',
            photoUrl: currentUser?.photoUrl,
            role: 'admin',
            status: 'active',
            joinedAt: tour.createdAt,
          ),
        );
      }
    }

    ref.watch(localExpensesRefreshProvider);

    final streamExpenses = expensesStream.value ?? ActiveTourCacheService.getCachedExpenses(widget.tourId);
    final queuedExpenses = ref.watch(offlineExpenseQueueProvider).getQueuedExpenses(tourId: widget.tourId);
    final deletedIds = ref.watch(offlineExpenseQueueProvider).getQueuedDeletedExpenseIds(tourId: widget.tourId);

    final Map<String, ExpenseModel> allExpensesMap = {};
    for (final e in queuedExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap[e.id] = e;
      }
    }
    for (final e in streamExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap.putIfAbsent(e.id, () => e);
      }
    }
    final allExpenses = allExpensesMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final approvedExpenses = allExpenses.where((e) => e.isApproved).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ActiveTourCacheService.cacheActiveTour(
        tour: tour,
        members: membersList.isNotEmpty ? membersList : null,
        expenses: approvedExpenses,
      );
    });

    final approvedSettlements = settlementsStream.maybeWhen(
      data: (settlements) =>
          settlements.where((s) => s.isApproved).toList(),
      orElse: () => ActiveTourCacheService.getCachedSettlements(widget.tourId),
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
        final expenseCount = allExpenses.length;
        final mySpending = approvedExpenses.fold(
          0.0,
          (sum, e) => sum + (e.splits[widget.userId] ?? 0.0),
        );
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
            await ActiveTourCacheService.clearActiveTourId();
            if (context.mounted) {
              context.go('/home');
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                CustomScrollView(
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
                      tourId: tour.id,
                      currencySymbol: tour.currencySymbol,
                      totalSpent: totalSpent,
                      yourSpending: mySpending,
                      memberCount: memberCount,
                      expenseCount: expenseCount,
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 10),
                    _MyBalanceCard(
                      balance: myNetBalance,
                      currencySymbol: tour.currencySymbol,
                      onSettleUp: () =>
                          context.push('/settlement?tourId=${tour.id}'),
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
                          onTap: () =>
                              context.push('/reports?tourId=${tour.id}'),
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
                              onPressed: () =>
                                  context.push('/expense/add?tourId=${tour.id}'),
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
                          allExpenses, tour.currencySymbol, tour.startDate,
                          isLoading: expensesStream.isLoading && allExpenses.isEmpty),
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
          MessengerChatHead(
            tourId: tour.id,
            tourName: tour.name,
            userId: widget.userId,
          ),
        ],
      ),
      bottomNavigationBar: TourBottomNavigationBar(
        tour: tour,
        isAdmin: isAdmin,
        currentUser: currentUser,
        membersCount: membersList.length,
        currentIndex: 1,
        onToursTap: () => context.push('/tours'),
        onDashboardTap: () {},
        onMembersTap: () => context.push('/tour/members?tourId=${tour.id}'),
        onSettingsTap: () => context.push('/tour/settings?tourId=${tour.id}'),
      ),
    ),
  );
  }

  Widget _buildExpensesTab(
    List<ExpenseModel> list,
    String currencySymbol,
    DateTime tourStartDate, {
    bool isLoading = false,
  }) {
    if (isLoading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return _EmptyExpensesCard(tourId: widget.tourId);
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
                        ? 'Expenses'
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
                onPressed: () =>
                    context.push('/tour/members?tourId=${widget.tourId}'),
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

            final liveProfile = !m.isOffline
                ? ref.watch(userProfileProvider(m.userId)).value
                : null;
            final cached =
                !m.isOffline ? ref.watch(userBoxProvider(m.userId)) : null;

            final name = liveProfile?.displayName.isNotEmpty == true
                ? liveProfile!.displayName
                : (m.displayName.isNotEmpty
                    ? m.displayName
                    : (cached?.displayName ?? 'Member'));

            final photo =
                liveProfile?.photoUrl ?? m.photoUrl ?? cached?.photoUrl;

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
                    photoUrl: photo,
                    radius: 20,
                    userId: m.userId,
                    tourMember: m.copyWith(
                      displayName: name,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: m.userId == widget.userId
                          ? () {
                              HapticFeedback.lightImpact();
                              context.push('/profile');
                            }
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                        'Settlements',
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
                    onPressed: () =>
                        context.push('/settlement?tourId=${tour.id}'),
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
      final members =
          ref.read(tourMembersStreamProvider(widget.tourId)).value ?? [];
      final toMember =
          members.firstWhereOrNull((m) => m.userId == debt.toUserId);
      final isOfflineReceiver =
          toMember?.isOffline == true || debt.toUserId.startsWith('offline_');
      final currentUid = ref.read(currentUserProvider).value?.uid;
      final isReceiver = currentUid == debt.toUserId;
      final shouldAutoApprove = isReceiver || isOfflineReceiver;

      final repo = ref.read(settlementRepositoryProvider);
      await repo.requestSettlement(
        tourId: widget.tourId,
        fromUserId: debt.fromUserId,
        fromUserName: debt.fromUserName,
        toUserId: debt.toUserId,
        toUserName: debt.toUserName,
        amount: debt.amount,
        currency: currencySymbol,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
        autoApprove: shouldAutoApprove,
        resolvedByUserId: currentUid ?? widget.userId,
      );

      if (mounted) {
        final message = isOfflineReceiver
            ? 'Settlement recorded and auto-approved for offline member.'
            : (isReceiver
                ? 'Settlement recorded and approved!'
                : 'Payment submitted! Waiting for ${debt.toUserName} to approve.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
  final String? tourId;
  final String currencySymbol;
  final double totalSpent;
  final double yourSpending;
  final int memberCount;
  final int expenseCount;

  const _ConsolidatedMetricsCard({
    this.tourId,
    required this.currencySymbol,
    required this.totalSpent,
    required this.yourSpending,
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
          color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.40 : 0.28),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryTeal
                .withValues(alpha: isDark ? 0.12 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          _MetricColumn(
            value: '$currencySymbol${totalSpent.toStringAsFixed(0)}',
            label: 'Total',
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          _MetricDivider(isDark: isDark),
          _MetricColumn(
            value: '$currencySymbol${yourSpending.toStringAsFixed(0)}',
            label: 'Your Spending',
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          _MetricDivider(isDark: isDark),
          _MetricColumn(
            label: 'Members',
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            onTap: () => context.push('/tour/members${tourId != null ? '?tourId=$tourId' : ''}'),
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

    return Tooltip(
      message: tooltip,
      child: InkWell(
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
          child: Icon(
            icon,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            size: 22,
          ),
        ),
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
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      titleSpacing: 16,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      title: InkWell(
        onTap: () => context.push('/tours'),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${tour.status == TourStatus.active ? 'Active' : 'Completed'} · ${tour.currency} · ${DateFormat('MMM d').format(tour.startDate)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                fontWeight: FontWeight.normal,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.qr_code_2_rounded),
                  tooltip: 'Invite & QR Code',
                  onPressed: () => TourQrDialog.show(
                    context,
                    tourName: tour.name,
                    inviteCode: tour.inviteCode,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Profile',
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/profile');
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(2.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryTeal,
                          width: 2.0,
                        ),
                      ),
                      child: MemberAvatar(
                        initials: (currentUser != null &&
                                currentUser.initials.isNotEmpty)
                            ? currentUser.initials
                            : 'U',
                        photoUrl: currentUser?.photoUrl,
                        userId: currentUser?.uid,
                        radius: 15,
                        enableTap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyExpensesCard extends StatelessWidget {
  final String? tourId;
  const _EmptyExpensesCard({this.tourId});

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
            onPressed: () => context.push(tourId != null
                ? '/expense/add?tourId=$tourId'
                : '/expense/add'),
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
                          onPressed: () async {
                            await ref
                                .read(expenseRepositoryProvider)
                                .updateExpenseStatus(
                                    tourId, e.id, ExpenseStatus.approved);
                            ref.invalidate(pendingExpensesStreamProvider(tourId));
                            ref.invalidate(approvedExpensesStreamProvider(tourId));
                            ref.invalidate(tourExpensesStreamProvider(tourId));
                            ref.read(localExpensesRefreshProvider.notifier).bump();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined,
                              color: AppColors.negative),
                          onPressed: () async {
                            await ref
                                .read(expenseRepositoryProvider)
                                .updateExpenseStatus(
                                    tourId, e.id, ExpenseStatus.rejected);
                            ref.invalidate(pendingExpensesStreamProvider(tourId));
                            ref.invalidate(approvedExpensesStreamProvider(tourId));
                            ref.invalidate(tourExpensesStreamProvider(tourId));
                            ref.read(localExpensesRefreshProvider.notifier).bump();
                          },
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
                      userId: r.userId,
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



