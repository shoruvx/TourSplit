import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/tour_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/balance_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../../data/services/tour_lifecycle_service.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/login_required_dialog.dart';
import 'widgets/tour_qr_dialog.dart';
import '../widgets/app_notification_sheet.dart';

enum _TourTabFilter { active, completed, all }

class AllToursScreen extends ConsumerStatefulWidget {
  const AllToursScreen({super.key});

  @override
  ConsumerState<AllToursScreen> createState() => _AllToursScreenState();
}

class _AllToursScreenState extends ConsumerState<AllToursScreen> {
  final Set<String> _dismissedTourIds = {};
  _TourTabFilter _selectedFilter = _TourTabFilter.active;

  Future<void> _confirmDeleteTour(TourModel tour, String userId) async {
    final isAdmin = tour.isAdmin(userId);
    final title = isAdmin ? 'Delete Tour' : 'Remove Tour';
    final message = isAdmin
        ? 'Are you sure you want to permanently delete "${tour.name}"?\n\nThis will remove it from all members and permanently delete all tour data.'
        : 'Remove "${tour.name}" from your tours?\n\nThis will remove the tour from your list. Other members will still have access to the tour.';
    final deleteButtonText = isAdmin ? 'Delete' : 'Remove';

    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isMatch = confirmCtrl.text.trim() == tour.name.trim();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.dialog),
            ),
            title: Row(
              children: [
                const Icon(Icons.delete_forever_rounded,
                    color: AppColors.danger, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                      children: [
                        const TextSpan(text: 'Type '),
                        TextSpan(
                          text: '"${tour.name}"',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.danger,
                          ),
                        ),
                        const TextSpan(text: ' to confirm:'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: tour.name,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: isMatch ? () => Navigator.pop(ctx, true) : null,
                child: Text(
                  deleteButtonText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _dismissedTourIds.add(tour.id);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text('Deleting "${tour.name}"...'),
          ],
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      await ref
          .read(tourRepositoryProvider)
          .deleteTour(tour.id, currentUserId: userId);

      ActiveTourCacheService.removeTourCache(tour.id);
      if (ref.read(activeTourIdProvider) == tour.id ||
          ActiveTourCacheService.getActiveTourId() == tour.id) {
        ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
        await ActiveTourCacheService.clearCachedActiveTour();
        await ActiveTourCacheService.clearActiveTourId();
        if (userId.isNotEmpty) {
          await ref.read(tourRepositoryProvider).clearUserActiveTour(userId);
        }
      }

      ref.invalidate(userToursStreamProvider(userId));
      ref.invalidate(tourStreamProvider(tour.id));
      ref.invalidate(currentUserProvider);

      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Tour Deleted',
          message: tour.id.startsWith('local_')
              ? '"${tour.name}" deleted successfully.'
              : 'Tour deleted. Changes will sync when back online.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Delete Failed',
          message: 'Could not delete tour: $e',
          primaryButtonText: 'Dismiss',
        );
      }
    }
  }

  Future<void> _navigateBackToMain() async {
    ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
    await ActiveTourCacheService.clearActiveTourId();
    if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _handleSelectTour(TourModel t, String userId) async {
    if (t.isDeleted || t.status == TourStatus.deleted) {
      _confirmDeleteTour(t, userId);
      return;
    }
    try {
      HapticFeedback.lightImpact();

      ref.read(activeTourIdOverrideProvider.notifier).state = t.id;
      await ActiveTourCacheService.setActiveTourId(t.id);
      await ActiveTourCacheService.cacheActiveTour(tour: t);

      if (t.id.startsWith('local_')) {
        if (mounted) context.go('/home');
        return;
      }
      await ref.read(tourRepositoryProvider).switchActiveTour(userId, t.id, tour: t);
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        context.go('/home');
      }
    }
  }

  void _showTourOptionsMenu(BuildContext context, TourModel tour, String userId) {
    final isAdmin = tour.isAdmin(userId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  tour.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.qr_code_rounded,
                      color: AppColors.primaryTeal, size: 20),
                ),
                title: const Text('QR & Invite Code',
                    style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                subtitle: Text('Invite code: ${tour.inviteCode}',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                onTap: () {
                  Navigator.pop(ctx);
                  TourQrDialog.show(
                    context,
                    tourName: tour.name,
                    inviteCode: tour.inviteCode,
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded,
                      color: AppColors.primaryTeal, size: 20),
                ),
                title: const Text('Expense Report',
                    style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                subtitle: const Text('Download or share PDF summary',
                    style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/reports?tourId=${tour.id}');
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (tour.isActive ? AppColors.warning : AppColors.primaryTeal)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      tour.isActive ? Icons.check_circle_outline_rounded : Icons.replay_rounded,
                      color: tour.isActive ? AppColors.warning : AppColors.primaryTeal,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    tour.isActive ? 'Mark as Completed' : 'Reactivate Tour',
                    style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    tour.isActive ? 'Close active expenses' : 'Reopen for new expenses',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (tour.isActive) {
                      await ref.read(tourRepositoryProvider).completeTour(tour.id);
                    } else {
                      await ref.read(tourRepositoryProvider).reopenTour(tour.id);
                    }
                  },
                ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 20),
                ),
                title: Text(
                  isAdmin ? 'Delete Tour' : 'Remove Tour',
                  style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger),
                ),
                subtitle: Text(
                  isAdmin ? 'Permanently delete this tour' : 'Remove from your list',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteTour(tour, userId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TourModel> _getLocalOnlyTours(String userId) {
    try {
      if (!Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) return [];
      final box = Hive.box(OfflineTourQueueService.localToursBox);
      final tours = <TourModel>[];
      for (final key in box.keys) {
        final val = box.get(key);
        if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          final members = (m['memberIds'] as List?)?.cast<String>() ?? [];
          if (m['adminId'] == userId || members.contains(userId)) {
            tours.add(TourModel(
              id: m['id'] as String? ?? key.toString(),
              name: m['name'] as String? ?? 'Offline Tour',
              currency: m['currency'] as String? ?? 'BDT',
              currencySymbol: m['currencySymbol'] as String? ?? '৳',
              adminId: m['adminId'] as String? ?? userId,
              inviteCode: m['inviteCode'] as String? ?? '',
              status: TourStatus.active,
              startDate: m['startDate'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(m['startDate'] as int)
                  : DateTime.now(),
              endDate: m['endDate'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(m['endDate'] as int)
                  : DateTime.now().add(const Duration(days: 7)),
              memberIds: members,
              createdAt: m['createdAt'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int)
                  : DateTime.now(),
            ));
          }
        }
      }
      return tours;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _navigateBackToMain();
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 64,
            titleSpacing: 20,
            title: const Text(
              'Tours',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: AppColors.primaryTeal,
                height: 1.1,
              ),
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.qr_code_scanner_rounded,
                            color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        tooltip: 'Join Tour',
                        onPressed: () => showLoginRequiredDialog(context,
                            action: 'join a tour'),
                      ),
                      IconButton(
                        icon: Icon(Icons.add_rounded,
                            color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        tooltip: 'Create Tour',
                        onPressed: () => showLoginRequiredDialog(context,
                            action: 'create a tour'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.luggage_outlined,
                      color: AppColors.primaryTeal,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Explore Tours on TourSplit',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You are currently exploring TourSplit in guest mode. Sign in or create an account to start tours, invite friends with QR codes, and sync expenses seamlessly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      height: 1.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 220,
                    child: ElevatedButton(
                      onPressed: () => context.push('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Sign In or Register',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: HomeBottomNavigationBar(
            currentIndex: 1,
            activeToursCount: 0,
            currentUser: null,
            onHomeTap: _navigateBackToMain,
            onToursTap: () {},
            onProfileTap: () => showLoginRequiredDialog(context,
                action: 'view your profile'),
          ),
        ),
      );
    }

    final toursStream = ref.watch(userToursStreamProvider(user.uid));
    final activeCount = toursStream.value?.where((t) => t.isActive).length ?? 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _navigateBackToMain();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          titleSpacing: 20,
          title: const Text(
            'Tours',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.primaryTeal,
              height: 1.1,
            ),
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner_rounded,
                          color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      tooltip: 'Join Tour',
                      onPressed: () => context.push('/tour/join'),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_rounded,
                          color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      tooltip: 'Create Tour',
                      onPressed: () => context.push('/tour/create'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: toursStream.when(
          loading: () {
            final localTours = _getLocalOnlyTours(user.uid);
            if (localTours.isNotEmpty) {
              return _buildToursBody(context, localTours, user, isDark);
            }
            return const Center(child: CircularProgressIndicator());
          },
          error: (e, _) {
            final localTours = _getLocalOnlyTours(user.uid);
            if (localTours.isNotEmpty) {
              return _buildToursBody(context, localTours, user, isDark);
            }
            return Center(child: Text('$e'));
          },
          data: (tours) {
            TourLifecycleService.instance.checkOncePerSession(tours);
            final localTours = _getLocalOnlyTours(user.uid);
            final merged = <String, TourModel>{};
            for (final t in localTours) {
              merged[t.id] = t;
            }
            for (final t in tours) {
              merged[t.id] = t;
            }
            final allTours = merged.values.toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return _buildToursBody(context, allTours, user, isDark);
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/tour/create'),
          backgroundColor: AppColors.primaryTeal,
          foregroundColor: Colors.white,
          elevation: 3,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text(
            'New Tour',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        bottomNavigationBar: HomeBottomNavigationBar(
          currentIndex: 1,
          activeToursCount: activeCount,
          currentUser: user,
          onHomeTap: _navigateBackToMain,
          onToursTap: () {},
          onProfileTap: () => context.push('/profile'),
        ),
      ),
    );
  }

  Widget _buildToursBody(
      BuildContext context, List<TourModel> tours, dynamic user, bool isDark) {
    final queuedDeleted =
        ref.read(offlineTourQueueProvider).getQueuedDeletedTourIds();
    final validTours = tours
        .where((t) =>
            !_dismissedTourIds.contains(t.id) &&
            !queuedDeleted.contains(t.id) &&
            !t.isDeleted &&
            t.status != TourStatus.deleted)
        .toList();

    if (validTours.isEmpty) {
      return _buildEmptyToursView(context, isDark);
    }

    final activeTours = validTours.where((t) => t.isActive).toList();
    final completedTours = validTours.where((t) => !t.isActive).toList();

    final List<TourModel> displayedTours;
    switch (_selectedFilter) {
      case _TourTabFilter.all:
        displayedTours = validTours;
        break;
      case _TourTabFilter.active:
        displayedTours = activeTours;
        break;
      case _TourTabFilter.completed:
        displayedTours = completedTours;
        break;
    }

    final uid = user?.uid as String? ?? '';
    final activeTourId =
        ref.watch(activeTourIdProvider) ?? (user?.activeTourId as String?);

    return Column(
      children: [
        _buildFilterTabs(
          allCount: validTours.length,
          activeCount: activeTours.length,
          completedCount: completedTours.length,
          isDark: isDark,
        ),
        Expanded(
          child: displayedTours.isEmpty
              ? _buildTabEmptyState(context, _selectedFilter, isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: displayedTours.length,
                  itemBuilder: (ctx, index) {
                    final t = displayedTours[index];
                    return _TourCard(
                      tour: t,
                      isCurrentActive: t.id == activeTourId,
                      isAdmin: t.isAdmin(uid),
                      currentUserId: uid,
                      onSelect: () => _handleSelectTour(t, uid),
                      onDelete: () => _confirmDeleteTour(t, uid),
                      onShowOptions: () =>
                          _showTourOptionsMenu(context, t, uid),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs({
    required int allCount,
    required int activeCount,
    required int completedCount,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          _buildFilterPill(
            label: 'Active',
            count: activeCount,
            isSelected: _selectedFilter == _TourTabFilter.active,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFilter = _TourTabFilter.active);
            },
            isDark: isDark,
          ),
          _buildFilterPill(
            label: 'Completed',
            count: completedCount,
            isSelected: _selectedFilter == _TourTabFilter.completed,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFilter = _TourTabFilter.completed);
            },
            isDark: isDark,
          ),
          _buildFilterPill(
            label: 'All Tours',
            count: allCount,
            isSelected: _selectedFilter == _TourTabFilter.all,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFilter = _TourTabFilter.all);
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.primaryTeal.withValues(alpha: 0.22)
                    : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: isSelected && isDark
                ? Border.all(
                    color: AppColors.primaryTeal.withValues(alpha: 0.5),
                    width: 1)
                : null,
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? (isDark ? Colors.white : AppColors.primaryTeal)
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryTeal
                          .withValues(alpha: isDark ? 0.35 : 0.15)
                      : (isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppColors.primaryTeal
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabEmptyState(
      BuildContext context, _TourTabFilter filter, bool isDark) {
    final String title;
    final String subtitle;
    final IconData icon;

    switch (filter) {
      case _TourTabFilter.active:
        title = 'No Active Tours';
        subtitle = 'Start a new tour or join with an invite code.';
        icon = Icons.flight_takeoff_rounded;
        break;
      case _TourTabFilter.completed:
        title = 'No Completed Tours';
        subtitle = 'Tours you mark as completed will appear here.';
        icon = Icons.task_alt_rounded;
        break;
      case _TourTabFilter.all:
        title = 'No Tours Found';
        subtitle = 'Create your first tour to track shared trip expenses.';
        icon = Icons.travel_explore_rounded;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppColors.primaryTeal,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 13.5,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            if (filter != _TourTabFilter.completed) ...[
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => context.push('/tour/create'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Create Tour',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyToursView(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: AppColors.primaryTeal,
                size: 46,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Tours Found',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have not joined or created any tours yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/tour/create'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Create a Tour',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourCard extends ConsumerWidget {
  final TourModel tour;
  final bool isCurrentActive;
  final bool isAdmin;
  final String? currentUserId;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final VoidCallback onShowOptions;

  const _TourCard({
    required this.tour,
    required this.isCurrentActive,
    required this.isAdmin,
    required this.currentUserId,
    required this.onSelect,
    required this.onDelete,
    required this.onShowOptions,
  });

  String _formatDateSpan(DateTime start, DateTime? end) {
    final startStr = DateFormat('MMM d').format(start);
    if (end == null) {
      return DateFormat('MMM d, yyyy').format(start);
    }
    if (start.year == end.year) {
      if (start.month == end.month) {
        return '$startStr – ${DateFormat('d, yyyy').format(end)}';
      }
      return '$startStr – ${DateFormat('MMM d, yyyy').format(end)}';
    }
    return '${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.watch(localExpensesRefreshProvider);
    final expensesAsync = ref.watch(tourExpensesStreamProvider(tour.id));
    final expenses = expensesAsync.value ??
        ref.read(expenseRepositoryProvider).getLocalExpenses(tour.id);
    final approvedExpenses = expenses.where((e) => e.isApproved).toList();
    final totalSpent = approvedExpenses.fold(0.0, (sum, e) => sum + e.amount);

    final membersAsync = ref.watch(tourMembersStreamProvider(tour.id));
    final members = membersAsync.value ?? [];

    final settlementsAsync = ref.watch(tourSettlementsStreamProvider(tour.id));
    final settlements = settlementsAsync.value ?? [];
    final approvedSettlements =
        settlements.where((s) => s.isApproved).toList();

    double? myNetBalance;
    if (currentUserId != null && members.isNotEmpty) {
      final rawBalances =
          BalanceService.calculateBalances(members, approvedExpenses);
      final finalBalances =
          BalanceService.applySettlements(rawBalances, approvedSettlements);
      myNetBalance = finalBalances[currentUserId] ?? 0.0;
    }

    final isTourActive = tour.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentActive
              ? AppColors.primaryTeal
              : (isTourActive
                  ? AppColors.primaryTeal
                      .withValues(alpha: isDark ? 0.35 : 0.20)
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
          width: isCurrentActive ? 1.8 : 1.0,
        ),
        boxShadow: [
          if (isCurrentActive)
            BoxShadow(
              color: AppColors.primaryTeal
                  .withValues(alpha: isDark ? 0.20 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          onLongPress: onShowOptions,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row: Name, Date & Status Chip
                Row(
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
                                  tour.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 17,
                                    fontWeight: isCurrentActive
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                    letterSpacing: -0.2,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (isCurrentActive) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryTeal
                                        .withValues(alpha: isDark ? 0.25 : 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.primaryTeal
                                          .withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.positive,
                                        ),
                                      ),
                                      const SizedBox(width: 3.5),
                                      const Text(
                                        'Current',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryTeal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatDateSpan(tour.startDate, tour.endDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatusChip(isTourActive, isDark),
                        const SizedBox(width: 2),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          tooltip: 'Tour Options',
                          onPressed: onShowOptions,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Middle Row: Companion Initials Avatars & Admin Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _MemberAvatarBubbles(
                        members: members,
                        totalCount: tour.memberIds.length,
                        isDark: isDark,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber
                              .withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                if (tour.isPendingAutoDeletion) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            color: AppColors.danger, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Auto-deletes in ${tour.daysUntilAutoDeletion}d due to inactivity.',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              context.push('/reports?tourId=${tour.id}'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                          ),
                          child: const Text(
                            'PDF',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Bottom Financial Status Pill
                _TourFinancialStatusPill(
                  currencySymbol: tour.currencySymbol,
                  totalSpent: totalSpent,
                  netBalance: myNetBalance,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive, bool isDark) {
    final color = isActive
        ? AppColors.primaryTeal
        : (isDark ? Colors.white60 : Colors.black45);
    final bg = isActive
        ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.20 : 0.10)
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isActive ? 'Active' : 'Completed',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MemberAvatarBubbles extends StatelessWidget {
  final List<TourMemberModel> members;
  final int totalCount;
  final bool isDark;

  const _MemberAvatarBubbles({
    required this.members,
    required this.totalCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_rounded,
            size: 15,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$totalCount ${totalCount == 1 ? 'member' : 'members'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      );
    }

    final displayMembers = members.take(4).toList();
    final remaining = members.length > 4 ? members.length - 4 : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < displayMembers.length; i++)
                Align(
                  widthFactor: 0.76,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          _avatarColor(displayMembers[i].displayName, isDark),
                      backgroundImage: (displayMembers[i].photoUrl != null &&
                              displayMembers[i].photoUrl!.isNotEmpty)
                          ? NetworkImage(displayMembers[i].photoUrl!)
                          : null,
                      child: (displayMembers[i].photoUrl == null ||
                              displayMembers[i].photoUrl!.isEmpty)
                          ? Text(
                              displayMembers[i].initials,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (remaining > 0)
                Align(
                  widthFactor: 0.76,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          isDark ? Colors.white24 : Colors.black12,
                      child: Text(
                        '+$remaining',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${members.length} ${members.length == 1 ? 'member' : 'members'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ),
      ],
    );
  }

  static Color _avatarColor(String name, bool isDark) {
    const colors = [
      Color(0xFF0D9488), // Teal
      Color(0xFF2563EB), // Blue
      Color(0xFF7C3AED), // Purple
      Color(0xFFDB2777), // Pink
      Color(0xFFEA580C), // Orange
      Color(0xFF059669), // Green
    ];
    final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }
}

class _TourFinancialStatusPill extends StatelessWidget {
  final String currencySymbol;
  final double totalSpent;
  final double? netBalance;
  final bool isDark;

  const _TourFinancialStatusPill({
    required this.currencySymbol,
    required this.totalSpent,
    required this.netBalance,
    required this.isDark,
  });

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '$currencySymbol${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 100000) {
      return '$currencySymbol${(amount / 1000).toStringAsFixed(0)}k';
    } else {
      return '$currencySymbol${NumberFormat('#,##0').format(amount.round())}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = netBalance ?? 0.0;
    final isOwed = balance > 0.5;
    final owes = balance < -0.5;
    final isSettled = totalSpent > 0 && !isOwed && !owes;

    Color pillBg;
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (totalSpent == 0) {
      pillBg = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04);
      statusColor = isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary;
      statusText = 'No expenses yet';
      statusIcon = Icons.receipt_long_outlined;
    } else if (isOwed) {
      pillBg = AppColors.positive.withValues(alpha: isDark ? 0.16 : 0.10);
      statusColor = AppColors.positive;
      statusText = 'You are owed: +${_formatAmount(balance)}';
      statusIcon = Icons.arrow_downward_rounded;
    } else if (owes) {
      pillBg = AppColors.warning.withValues(alpha: isDark ? 0.16 : 0.10);
      statusColor = AppColors.warning;
      statusText = 'You owe: -${_formatAmount(balance.abs())}';
      statusIcon = Icons.arrow_upward_rounded;
    } else if (isSettled) {
      pillBg = AppColors.primaryTeal.withValues(alpha: isDark ? 0.15 : 0.08);
      statusColor = AppColors.primaryTeal;
      statusText = 'All Settled Up';
      statusIcon = Icons.check_circle_rounded;
    } else {
      pillBg = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04);
      statusColor = isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary;
      statusText = 'Settled';
      statusIcon = Icons.check_circle_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: Text(
              'Total: ${_formatAmount(totalSpent)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.lightText,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(statusIcon, size: 13, color: statusColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    statusText,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
