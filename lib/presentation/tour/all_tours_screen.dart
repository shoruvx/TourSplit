import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/tour_model.dart';
import 'widgets/tour_qr_dialog.dart';

class AllToursScreen extends ConsumerStatefulWidget {
  const AllToursScreen({super.key});

  @override
  ConsumerState<AllToursScreen> createState() => _AllToursScreenState();
}

class _AllToursScreenState extends ConsumerState<AllToursScreen> {
  final Set<String> _dismissedTourIds = {};

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

      ref.invalidate(userToursStreamProvider(userId));
      ref.invalidate(tourStreamProvider(tour.id));
      ref.invalidate(currentUserProvider);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('"${tour.name}" deleted successfully.'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
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
                        onDelete: () => _confirmDeleteTour(t, user.uid),
                        onSelect: () async {
                          if (t.isDeleted || t.status == TourStatus.deleted) {
                            _confirmDeleteTour(t, user.uid);
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
                                        t, user.uid),
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
                        onDelete: () => _confirmDeleteTour(t, user.uid),
                        onSelect: () async {
                          if (t.isDeleted || t.status == TourStatus.deleted) {
                            _confirmDeleteTour(t, user.uid);
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
                                        t, user.uid),
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
    final currentUserId = ref.watch(currentUserProvider).value?.uid;
    final isTourActive = tour.isActive;

    final expensesAsync = ref.watch(tourExpensesStreamProvider(tour.id));
    final expenses = expensesAsync.value ?? const [];
    final approvedExpenses = expenses.where((e) => e.isApproved).toList();
    final totalSpent = approvedExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final expenseCount = expenses.length;
    final memberCount = tour.memberIds.length;
    final perPerson = totalSpent / (memberCount > 0 ? memberCount : 1);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isCurrentActive
              ? AppColors.primaryTeal
              : (isTourActive
                  ? AppColors.primaryTeal.withValues(alpha: isDark ? 0.38 : 0.28)
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
          width: isCurrentActive ? 1.8 : 1.0,
        ),
        boxShadow: [
          if (isCurrentActive)
            BoxShadow(
              color:
                  AppColors.primaryTeal.withValues(alpha: isDark ? 0.20 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          else if (isTourActive)
            BoxShadow(
              color:
                  AppColors.primaryTeal.withValues(alpha: isDark ? 0.08 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
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
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _TourMetricsStrip(
                currencySymbol: tour.currencySymbol,
                totalSpent: totalSpent,
                perPerson: perPerson,
                memberCount: memberCount,
                expenseCount: expenseCount,
                isLoading:
                    expensesAsync.isLoading && expensesAsync.value == null,
              ),
              if (isAdmin) ...[
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                ),
              ],
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
  final double perPerson;
  final int memberCount;
  final int expenseCount;
  final bool isLoading;

  const _TourMetricsStrip({
    required this.currencySymbol,
    required this.totalSpent,
    required this.perPerson,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6.5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.6)
              : AppColors.lightBorder,
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          _MiniMetric(
            label: 'Total',
            value: _formatAmount(totalSpent),
            valueColor: AppColors.primaryTeal,
            isLoading: isLoading,
          ),
          _MiniDivider(isDark: isDark),
          _MiniMetric(
            label: 'Per Person',
            value: _formatAmount(perPerson),
            valueColor: AppColors.primaryTeal,
            isLoading: isLoading,
          ),
          _MiniDivider(isDark: isDark),
          _MiniMetric(
            label: 'Members',
            value: '$memberCount',
            icon: Icons.groups_rounded,
            isLoading: false,
          ),
          _MiniDivider(isDark: isDark),
          _MiniMetric(
            label: 'Expenses',
            value: '$expenseCount',
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final bool isLoading;

  const _MiniMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final effectiveColor = valueColor ?? defaultColor;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isLoading)
            Container(
              width: 28,
              height: 13,
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: effectiveColor),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: effectiveColor,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 1.5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              letterSpacing: 0.1,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDivider extends StatelessWidget {
  final bool isDark;
  const _MiniDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: isDark
          ? AppColors.darkBorder.withValues(alpha: 0.6)
          : AppColors.lightBorder,
    );
  }
}

