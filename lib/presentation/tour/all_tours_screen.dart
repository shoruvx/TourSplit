import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import 'widgets/tour_qr_dialog.dart';
import '../widgets/app_bottom_nav_bar.dart';

class AllToursScreen extends ConsumerStatefulWidget {
  const AllToursScreen({super.key});

  @override
  ConsumerState<AllToursScreen> createState() => _AllToursScreenState();
}

class _AllToursScreenState extends ConsumerState<AllToursScreen> {
  final Set<String> _dismissedTourIds = {};
  bool _activeCategoryExpanded = true;
  bool _completedCategoryExpanded = false;
  final Set<String> _expandedTourIds = {};
  bool _initialExpansionConfigured = false;

  Future<void> _confirmDeleteTour(TourModel tour, String userId) async {
    final isAdmin = tour.isAdmin(userId);
    final title = isAdmin ? 'Delete Tour' : 'Remove Tour';
    final message = isAdmin
        ? 'Are you sure you want to permanently delete "${tour.name}"?\n\nThis will remove it from all members and permanently delete all tour data.'
        : 'Remove "${tour.name}" from your trips?\n\nThis will remove the tour from your list. Other members will still have access to the tour.';
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

      if (ref.read(activeTourIdProvider) == tour.id) {
        ref.read(activeTourIdOverrideProvider.notifier).state = kNoActiveTourId;
        await ActiveTourCacheService.clearCachedActiveTour();
      }

      ref.invalidate(userToursStreamProvider(userId));
      ref.invalidate(tourStreamProvider(tour.id));
      ref.invalidate(currentUserProvider);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tour.id.startsWith('local_')
                  ? '"${tour.name}" deleted successfully.'
                  : 'Tour deleted. Changes will sync when online.',
            ),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not delete tour: $e'),
            backgroundColor: AppColors.danger,
          ),
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            // While Firestore loads, show any local-only tours immediately
            final localTours = _getLocalOnlyTours(user.uid);
            if (localTours.isNotEmpty) {
              return _buildToursList(context, localTours, user, isDark);
            }
            return const Center(child: CircularProgressIndicator());
          },
          error: (e, _) {
            final localTours = _getLocalOnlyTours(user.uid);
            if (localTours.isNotEmpty) {
              return _buildToursList(context, localTours, user, isDark);
            }
            return Center(child: Text('$e'));
          },
          data: (tours) {
            // Merge Firestore tours with any locally-queued offline tours
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
            return _buildToursList(context, allTours, user, isDark);
          },
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

  Future<void> _handleSelectTour(TourModel t, String userId) async {
    if (t.isDeleted || t.status == TourStatus.deleted) {
      _confirmDeleteTour(t, userId);
      return;
    }
    try {
      HapticFeedback.lightImpact();

      // Immediately notify Riverpod and persist in cache
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
      // In offline mode, switchActiveTour may throw from Firestore, but local cache & provider
      // are already updated, so proceed to /home safely
      if (mounted) {
        context.go('/home');
      }
    }
  }

  /// Reads locally-queued tours from the Hive [local_tours] box.
  List<TourModel> _getLocalOnlyTours(String userId) {
    try {
      if (!Hive.isBoxOpen(OfflineTourQueueService.localToursBox)) return [];
      final box = Hive.box(OfflineTourQueueService.localToursBox);
      final tours = <TourModel>[];
      for (final key in box.keys) {
        if (key.toString().startsWith('local_')) {
          final val = box.get(key);
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            final members = (m['members'] as List?)?.cast<String>() ?? [];
            if (!members.contains(userId)) continue;
            tours.add(TourModel(
              id: m['id'] as String? ?? key.toString(),
              name: m['name'] as String? ?? 'Offline Tour',
              description: null,
              currency: m['currency'] as String? ?? 'USD',
              currencySymbol: m['currencySymbol'] as String? ?? '\$',
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

  /// Shared tours-list builder — used by loading, error, and data states.
  Widget _buildToursList(
      BuildContext context, List<TourModel> tours, dynamic user, bool isDark) {
    final queuedDeleted = ref.read(offlineTourQueueProvider).getQueuedDeletedTourIds();
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

    if (!_initialExpansionConfigured && validTours.isNotEmpty) {
      _initialExpansionConfigured = true;
      final latestActive = validTours.firstWhereOrNull((t) => t.isActive);
      if (latestActive != null) {
        _expandedTourIds.add(latestActive.id);
      } else {
        _expandedTourIds.add(validTours.first.id);
      }
    }

    final activeTours = validTours.where((t) => t.isActive).toList();
    final pastTours = validTours.where((t) => !t.isActive).toList();
    final uid = user?.uid as String? ?? '';
    final activeTourId = ref.watch(activeTourIdProvider) ?? (user?.activeTourId as String?);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (activeTours.isNotEmpty) ...[
          _CollapsibleSectionHeader(
            title: 'Active Tours',
            count: activeTours.length,
            isExpanded: _activeCategoryExpanded,
            onToggle: () {
              HapticFeedback.selectionClick();
              setState(() => _activeCategoryExpanded = !_activeCategoryExpanded);
            },
          ),
          if (_activeCategoryExpanded) ...[
            const SizedBox(height: 10),
            ...activeTours.map((t) => _TourCard(
                  tour: t,
                  isCurrentActive: t.id == activeTourId,
                  isAdmin: t.isAdmin(uid),
                  isExpanded: _expandedTourIds.contains(t.id),
                  onToggleExpand: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_expandedTourIds.contains(t.id)) {
                        _expandedTourIds.remove(t.id);
                      } else {
                        _expandedTourIds.add(t.id);
                      }
                    });
                  },
                  onDelete: () => _confirmDeleteTour(t, uid),
                  onSelect: () => _handleSelectTour(t, uid),
                )),
          ],
          const SizedBox(height: 20),
        ],
        if (pastTours.isNotEmpty) ...[
          _CollapsibleSectionHeader(
            title: 'Completed Tours',
            count: pastTours.length,
            isExpanded: _completedCategoryExpanded,
            onToggle: () {
              HapticFeedback.selectionClick();
              setState(
                  () => _completedCategoryExpanded = !_completedCategoryExpanded);
            },
          ),
          if (_completedCategoryExpanded) ...[
            const SizedBox(height: 10),
            ...pastTours.map((t) => _TourCard(
                  tour: t,
                  isCurrentActive: t.id == activeTourId,
                  isAdmin: t.isAdmin(uid),
                  isExpanded: _expandedTourIds.contains(t.id),
                  onToggleExpand: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_expandedTourIds.contains(t.id)) {
                        _expandedTourIds.remove(t.id);
                      } else {
                        _expandedTourIds.add(t.id);
                      }
                    });
                  },
                  onDelete: () => _confirmDeleteTour(t, uid),
                  onSelect: () => _handleSelectTour(t, uid),
                )),
          ],
        ],
      ],
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
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: AppColors.primaryTeal,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Tours Found',
              style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You have not joined or created any tours yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.push('/tour/create'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create a Tour'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CollapsibleSectionHeader({
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryTeal,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: isDark ? Colors.white70 : Colors.black54,
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
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _TourCard({
    required this.tour,
    required this.isCurrentActive,
    required this.isAdmin,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.watch(currentUserProvider).value?.uid;
    final isTourActive = tour.isActive;

    // Collapsed state: Super clean single line showing only tour name & status
    if (!isExpanded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isCurrentActive
                ? AppColors.primaryTeal
                : (isTourActive
                    ? AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.35 : 0.20)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
            width: isCurrentActive ? 1.6 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrentActive
                        ? AppColors.positive
                        : (isTourActive ? AppColors.primaryTeal : Colors.grey),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tour.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15.5,
                      fontWeight:
                          isCurrentActive ? FontWeight.w700 : FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (isCurrentActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryTeal,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                  tooltip: 'Expand Tour Details',
                  onPressed: onToggleExpand,
                ),
              ],
            ),
          ),
        ),
      );
    }

    ref.watch(localExpensesRefreshProvider);
    final expensesAsync = ref.watch(tourExpensesStreamProvider(tour.id));
    final expenses = expensesAsync.value ?? ref.read(expenseRepositoryProvider).getLocalExpenses(tour.id);
    final approvedExpenses = expenses.where((e) => e.isApproved).toList();
    final totalSpent = approvedExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final expenseCount = expenses.length;
    final memberCount = tour.memberIds.length;
    final mySpending = currentUserId != null
        ? approvedExpenses.fold(
            0.0,
            (sum, e) => sum + (e.splits[currentUserId] ?? 0.0),
          )
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isCurrentActive
              ? AppColors.primaryTeal
              : (isTourActive
                  ? AppColors.primaryTeal
                      .withValues(alpha: isDark ? 0.44 : 0.30)
                  : AppColors.primaryTeal
                      .withValues(alpha: isDark ? 0.25 : 0.18)),
          width: isCurrentActive ? 1.8 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryTeal.withValues(
                alpha: isCurrentActive
                    ? (isDark ? 0.22 : 0.14)
                    : (isDark ? 0.12 : 0.05)),
            blurRadius: isCurrentActive ? 12 : 8,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tour.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tour.currency} · ${DateFormat('MMM d, yyyy').format(tour.startDate)}',
                          style: TextStyle(
                            fontSize: 11.5,
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
                      if (currentUserId != null &&
                          (tour.isPastMember(currentUserId) ||
                              !tour.memberIds.contains(currentUserId))) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Archived',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (isCurrentActive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 13, color: AppColors.primaryTeal),
                              SizedBox(width: 3.5),
                              Text(
                                'Active',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.qr_code_rounded, size: 19),
                        tooltip: 'Share QR Code',
                        onPressed: () => TourQrDialog.show(
                          context,
                          tourName: tour.name,
                          inviteCode: tour.inviteCode,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 19, color: AppColors.danger),
                        tooltip: 'Delete Tour',
                        onPressed: onDelete,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded,
                            size: 22),
                        tooltip: 'Collapse Tour Details',
                        onPressed: onToggleExpand,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _TourMetricsStrip(
                currencySymbol: tour.currencySymbol,
                totalSpent: totalSpent,
                yourSpending: mySpending,
                memberCount: memberCount,
                expenseCount: expenseCount,
                isLoading:
                    expensesAsync.isLoading && expensesAsync.value == null,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isAdmin)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () async {
                            if (tour.isActive) {
                              await ref
                                  .read(tourRepositoryProvider)
                                  .completeTour(tour.id);
                            } else {
                              await ref
                                  .read(tourRepositoryProvider)
                                  .reopenTour(tour.id);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tour.isActive
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.replay_rounded,
                                  size: 13,
                                  color: tour.isActive
                                      ? AppColors.danger
                                      : AppColors.primaryTeal,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tour.isActive ? 'End Tour' : 'Reactivate',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 11,
                                    color: tour.isActive
                                        ? AppColors.danger
                                        : AppColors.primaryTeal,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  FilledButton.icon(
                    onPressed: onSelect,
                    icon: Icon(
                      isCurrentActive
                          ? Icons.check_circle_rounded
                          : Icons.login_rounded,
                      size: 14,
                    ),
                    label: Text(
                      isCurrentActive ? 'Active (Open)' : 'Open Tour',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: isCurrentActive
                          ? AppColors.positive
                          : AppColors.primaryTeal,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourMetricsStrip extends StatelessWidget {
  final String currencySymbol;
  final double totalSpent;
  final double yourSpending;
  final int memberCount;
  final int expenseCount;
  final bool isLoading;

  const _TourMetricsStrip({
    required this.currencySymbol,
    required this.totalSpent,
    required this.yourSpending,
    required this.memberCount,
    required this.expenseCount,
    this.isLoading = false,
  });

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '$currencySymbol${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 100000) {
      return '$currencySymbol${(amount / 1000).toStringAsFixed(0)}k';
    } else {
      return '$currencySymbol${amount.toStringAsFixed(0)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.35 : 0.20),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Total Spending Pill
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal
                            .withValues(alpha: isDark ? 0.20 : 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 14,
                        color: AppColors.primaryTeal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'TOTAL SPENT',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isLoading ? '...' : _formatAmount(totalSpent),
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 28,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.8)
                    : AppColors.lightBorder,
              ),
              // Your Spending Hero Pill
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal
                            .withValues(alpha: isDark ? 0.25 : 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.pie_chart_rounded,
                        size: 14,
                        color: AppColors.primaryTeal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'YOUR SPENDING',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isLoading ? '...' : _formatAmount(yourSpending),
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Sub-chips row: Members & Expenses
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$memberCount members',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$expenseCount expenses',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

