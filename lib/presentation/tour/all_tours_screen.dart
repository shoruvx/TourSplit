import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/models/tour_model.dart';
import 'widgets/tour_qr_dialog.dart';

class AllToursScreen extends ConsumerStatefulWidget {
  const AllToursScreen({super.key});

  @override
  ConsumerState<AllToursScreen> createState() => _AllToursScreenState();
}

class _AllToursScreenState extends ConsumerState<AllToursScreen> {
  final Set<String> _dismissedTourIds = {};

  Future<void> _confirmDeleteTour(
      BuildContext context, TourModel tour, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded,
                color: AppColors.danger, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Tour',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${tour.name}"?\n\nThis will remove it from your tours list immediately and clean up its data.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _dismissedTourIds.add(tour.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
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

      ref.invalidate(userToursStreamProvider(userId));
      ref.invalidate(tourStreamProvider(tour.id));
      ref.invalidate(currentUserProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${tour.name}" deleted successfully.'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete from server: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
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
          title: const Text('Your Tours'),
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
              icon: const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Join Tour',
              onPressed: () => context.push('/tour/join'),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Create Tour',
              onPressed: () => context.push('/tour/create'),
            ),
          ],
        ),
        body: toursStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (tours) {
            final validTours = tours
                .where((t) =>
                    !_dismissedTourIds.contains(t.id) &&
                    !t.isDeleted &&
                    t.status != TourStatus.deleted)
                .toList();

            if (validTours.isEmpty) {
              return _buildEmptyToursView(context, isDark);
            }

            final activeTours = validTours.where((t) => t.isActive).toList();
            final pastTours = validTours.where((t) => !t.isActive).toList();

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (activeTours.isNotEmpty) ...[
                  _SectionTitle(title: 'Active Tours (${activeTours.length})'),
                  const SizedBox(height: 12),
                  ...activeTours.map((t) => _TourCard(
                        tour: t,
                        isCurrentActive: t.id == user.activeTourId,
                        isAdmin: t.isAdmin(user.uid),
                        onDelete: () => _confirmDeleteTour(context, t, user.uid),
                        onSelect: () async {
                          if (t.isDeleted || t.status == TourStatus.deleted) {
                            _confirmDeleteTour(context, t, user.uid);
                            return;
                          }
                          try {
                            await ref
                                .read(tourRepositoryProvider)
                                .switchActiveTour(user.uid, t.id);
                            HapticFeedback.lightImpact();
                            if (context.mounted) context.go('/home');
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'Could not open tour. It may be corrupted or deleted.'),
                                  action: SnackBarAction(
                                    label: 'Delete',
                                    textColor: Colors.redAccent,
                                    onPressed: () => _confirmDeleteTour(
                                        context, t, user.uid),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      )),
                  const SizedBox(height: 24),
                ],
                if (pastTours.isNotEmpty) ...[
                  _SectionTitle(
                      title: 'Completed Tours (${pastTours.length})'),
                  const SizedBox(height: 12),
                  ...pastTours.map((t) => _TourCard(
                        tour: t,
                        isCurrentActive: t.id == user.activeTourId,
                        isAdmin: t.isAdmin(user.uid),
                        onDelete: () => _confirmDeleteTour(context, t, user.uid),
                        onSelect: () async {
                          if (t.isDeleted || t.status == TourStatus.deleted) {
                            _confirmDeleteTour(context, t, user.uid);
                            return;
                          }
                          try {
                            await ref
                                .read(tourRepositoryProvider)
                                .switchActiveTour(user.uid, t.id);
                            HapticFeedback.lightImpact();
                            if (context.mounted) context.go('/home');
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'Could not open tour. It may be corrupted or deleted.'),
                                  action: SnackBarAction(
                                    label: 'Delete',
                                    textColor: Colors.redAccent,
                                    onPressed: () => _confirmDeleteTour(
                                        context, t, user.uid),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      )),
                ],
              ],
            );
          },
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

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TourCard extends ConsumerWidget {
  final TourModel tour;
  final bool isCurrentActive;
  final bool isAdmin;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _TourCard({
    required this.tour,
    required this.isCurrentActive,
    required this.isAdmin,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentActive
              ? AppColors.primaryTeal
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: isCurrentActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tour.name,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tour.currency} · ${DateFormat('MMM d, yyyy').format(tour.startDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrentActive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 14, color: AppColors.primaryTeal),
                              SizedBox(width: 4),
                              Text(
                                'Active',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 11,
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
                        icon: const Icon(Icons.qr_code_rounded, size: 20),
                        tooltip: 'Share QR Code',
                        onPressed: () => TourQrDialog.show(
                          context,
                          tourName: tour.name,
                          inviteCode: tour.inviteCode,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.danger),
                        tooltip: 'Delete Tour',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${tour.memberIds.length} Members',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      if (isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange),
                          ),
                        ),
                    ],
                  ),
                  if (isAdmin)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () async {
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
                      child: Text(
                        tour.isActive ? 'End Tour' : 'Reactivate',
                        style: TextStyle(
                          fontSize: 12,
                          color: tour.isActive
                              ? AppColors.danger
                              : AppColors.primaryTeal,
                          fontWeight: FontWeight.bold,
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
