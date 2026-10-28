import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../widgets/app_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/theme_switch_toggle.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/app_notification_sheet.dart';

class TourSettingsScreen extends ConsumerStatefulWidget {
  final String? tourId;
  const TourSettingsScreen({super.key, this.tourId});

  @override
  ConsumerState<TourSettingsScreen> createState() => _TourSettingsScreenState();
}

class _TourSettingsScreenState extends ConsumerState<TourSettingsScreen> {
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;
  TourModel? _lastTour;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveChanges(String tourId) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(tourRepositoryProvider).updateTour(tourId, {
        'name': _nameCtrl.text.trim(),
      });
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Tour Updated',
          message: 'Tour settings have been saved successfully.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Update Failed',
          message: 'Failed to update tour: $e',
          primaryButtonText: 'Dismiss',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _endTour(String tourId) async {
    final confirm = await showAppConfirmationSheet(
      context,
      icon: Icons.flag_rounded,
      iconColor: AppColors.warning,
      title: 'End Tour?',
      message:
          'This will mark the tour as completed. Members won\'t be able to add new expenses.',
      confirmText: 'End Tour',
      confirmColor: AppColors.danger,
    );
    if (confirm == true) {
      await ref.read(tourRepositoryProvider).completeTour(tourId);
      if (mounted) context.go('/home');
    }
  }

  Future<void> _deleteTour(String tourId, String tourName) async {
    final proceed = await showAppConfirmationSheet(
      context,
      icon: Icons.delete_forever_rounded,
      iconColor: AppColors.danger,
      title: 'Delete Tour?',
      message:
          'This will permanently delete "$tourName" including ALL expenses, settlements, and member data.\n\nThis CANNOT be undone!',
      confirmText: 'Proceed',
      confirmColor: AppColors.danger,
    );
    if (proceed != true || !mounted) return;

    final confirmCtrl = TextEditingController();
    final typed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirm Deletion',
              style: TextStyle(color: AppColors.danger)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type the tour name "$tourName" to confirm:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: tourName,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmCtrl.text.trim() == tourName
                    ? AppColors.danger
                    : Colors.grey,
              ),
              onPressed: confirmCtrl.text.trim() == tourName
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );

    if (typed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final currentUserId = ref.read(currentUserProvider).value?.uid;
      await ref
          .read(tourRepositoryProvider)
          .deleteTour(tourId, currentUserId: currentUserId);

      ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
      await ActiveTourCacheService.clearCachedActiveTour();
      await ActiveTourCacheService.clearActiveTourId();
      await ActiveTourCacheService.removeTourCache(tourId);
      if (currentUserId != null) {
        await ref.read(tourRepositoryProvider).clearUserActiveTour(currentUserId);
      }

      if (currentUserId != null) {
        ref.invalidate(userToursStreamProvider(currentUserId));
      }
      ref.invalidate(tourStreamProvider(tourId));
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      }
      context.go('/home');

      final homeCtx = rootNavigatorKey.currentContext;
      if (homeCtx != null && homeCtx.mounted) {
        showAppNotificationSheet(
          homeCtx,
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Tour Deleted',
          message: tourId.startsWith('local_')
              ? 'Tour deleted permanently.'
              : 'Tour deleted. Changes will sync when back online.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppNotificationSheet(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'Delete Failed',
        message: 'Could not delete tour: $e',
        primaryButtonText: 'Dismiss',
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveTour(String tourId, String tourName) async {
    final confirm = await showAppConfirmationSheet(
      context,
      icon: Icons.logout_rounded,
      iconColor: AppColors.danger,
      title: 'Leave Tour?',
      message:
          'Are you sure you want to leave "$tourName"?\n\n'
          '• If you have 0 contribution and spending, you will be completely removed from everywhere in the tour.\n'
          '• If you have recorded expenses or splits, your history will stay intact for tour math and you will be listed as a left member.\n\n'
          'You can rejoin anytime using the tour invite code.',
      confirmText: 'Leave Tour',
      confirmColor: AppColors.danger,
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final currentUserId = ref.read(currentUserProvider).value?.uid;
      bool preservedAsPast = false;
      if (currentUserId != null) {
        preservedAsPast = await ref
            .read(tourRepositoryProvider)
            .leaveTourWithAudit(tourId, currentUserId);
        ref.invalidate(userToursStreamProvider(currentUserId));
      }
      if (ref.read(activeTourIdProvider) == tourId) {
        ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
        await ActiveTourCacheService.clearCachedActiveTour();
        await ActiveTourCacheService.clearActiveTourId();
      }
      ref.invalidate(tourStreamProvider(tourId));
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      }
      context.go('/home');

      final homeCtx = rootNavigatorKey.currentContext;
      if (homeCtx != null && homeCtx.mounted) {
        showAppNotificationSheet(
          homeCtx,
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.primaryTeal,
          title: 'Left Tour',
          message: preservedAsPast
              ? 'You have left the tour. Financial records remain intact.'
              : 'You have been completely removed from the tour.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppNotificationSheet(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'Failed to Leave Tour',
        message: 'Could not leave tour: $e',
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeTourFromList(String tourId, String tourName) async {
    final confirm = await showAppConfirmationSheet(
      context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.danger,
      title: 'Remove Tour?',
      message:
          'Remove "$tourName" from your tour list? You will no longer see this tour in your list.',
      confirmText: 'Remove',
      confirmColor: AppColors.danger,
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final currentUserId = ref.read(currentUserProvider).value?.uid;
      if (currentUserId != null) {
        await ref
            .read(tourRepositoryProvider)
            .removeTourForUser(tourId, currentUserId);
        ref.invalidate(userToursStreamProvider(currentUserId));
      }
      ref.invalidate(tourStreamProvider(tourId));
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      }
      context.go('/home');

      final homeCtx = rootNavigatorKey.currentContext;
      if (homeCtx != null && homeCtx.mounted) {
        showAppNotificationSheet(
          homeCtx,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Tour Removed',
          message: 'Tour was removed from your list.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppNotificationSheet(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'Remove Failed',
        message: 'Could not remove tour: $e',
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final activeTourId = ref.watch(activeTourIdProvider);
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final effectiveTourId = widget.tourId ??
        activeTourId ??
        user?.activeTourId ??
        cachedTour?.id ??
        ActiveTourCacheService.getActiveTourId();

    if (effectiveTourId == null) {
      if (userAsync.isLoading) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      });
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final currentUserId =
        user?.uid ?? ref.watch(authStateProvider).value?.uid ?? '';
    final tourStream = ref.watch(tourStreamProvider(effectiveTourId));

    return tourStream.when(
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: Text('$e')),
      ),
      data: (rawTour) {
        if (rawTour != null && !rawTour.isDeleted && rawTour.status != TourStatus.deleted) {
          _lastTour = rawTour;
        }

        final activeTour = (rawTour != null && !rawTour.isDeleted && rawTour.status != TourStatus.deleted)
            ? rawTour
            : (_isLoading ? _lastTour : null);

        if (activeTour == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            }
          });
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final tour = activeTour;

        final isAdmin = currentUserId.isNotEmpty &&
            (tour.creatorId == currentUserId || tour.isAdmin(currentUserId));
        final isPastMember =
            currentUserId.isNotEmpty && tour.isPastMember(currentUserId);

        if (!_initialized) {
          _nameCtrl.text = tour.name;
          _initialized = true;
        }

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
          child: LoadingOverlay(
            isLoading: _isLoading,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: 64,
                titleSpacing: 20,
                title: const Text(
                  'Tour Settings',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: AppColors.primaryTeal,
                  ),
                ),
                actions: [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: ThemeSwitchToggle(height: 36, width: 62),
                    ),
                  ),
                ],
              ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPastMember)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_clock_rounded,
                              color: Colors.amber, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You have left or were removed from this tour. Settings are read-only.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  AppTextField(
                    controller: _nameCtrl,
                    label: 'Tour Name',
                    prefixIcon: Icons.map_rounded,
                    textCapitalization: TextCapitalization.words,
                    enabled: !isPastMember && isAdmin,
                  ).animate().fadeIn(delay: 100.ms),
                  if (!isPastMember && isAdmin) ...[
                    const SizedBox(height: 24),
                    GradientButton(
                      onPressed: () => _saveChanges(tour.id),
                      label: 'Save Changes',
                      icon: Icons.save_rounded,
                    ).animate().fadeIn(delay: 200.ms),
                  ],
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Danger Zone',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (isPastMember)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _removeTourFromList(tour.id, tour.name),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger),
                      label: const Text('Remove from My Tours',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                    ).animate().fadeIn(delay: 250.ms)
                  else if (!isAdmin) ...[
                    OutlinedButton.icon(
                      onPressed: () => _leaveTour(tour.id, tour.name),
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.danger),
                      label: const Text('Leave Tour',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                    ).animate().fadeIn(delay: 250.ms),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _removeTourFromList(tour.id, tour.name),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger),
                      label: const Text('Remove from My Tours',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                  ] else ...[
                    if (!tour.isActive)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(tourRepositoryProvider)
                              .reopenTour(tour.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tour reactivated!'),
                                backgroundColor: AppColors.accent,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.accent),
                        label: const Text('Reactivate Tour',
                            style: TextStyle(color: AppColors.accent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.accent, width: 1.5),
                        ),
                      ).animate().fadeIn(delay: 250.ms)
                    else
                      OutlinedButton.icon(
                        onPressed: () => _endTour(tour.id),
                        icon: const Icon(Icons.flag_rounded,
                            color: AppColors.danger),
                        label: const Text('End Tour',
                            style: TextStyle(color: AppColors.danger)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.5),
                        ),
                      ).animate().fadeIn(delay: 250.ms),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _deleteTour(tour.id, tour.name),
                      icon: const Icon(Icons.delete_forever_rounded,
                          color: AppColors.danger),
                      label: const Text('Delete Tour Permanently',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                  ],
                ],
              ),
            ),
            bottomNavigationBar: TourBottomNavigationBar(
              tour: tour,
              isAdmin: isAdmin,
              currentUser: user,
              membersCount: tour.memberIds.length,
              currentIndex: 3,
              onToursTap: () => context.push('/tours'),
              onDashboardTap: () {
                ref.read(activeTourIdOverrideProvider.notifier).state = tour.id;
                ActiveTourCacheService.setActiveTourId(tour.id);
                context.go('/home');
              },
              onMembersTap: () =>
                  context.pushReplacement('/tour/members?tourId=${tour.id}'),
              onSettingsTap: () {},
            ),
          ),
        ),
      );
      },
    );
  }
}
