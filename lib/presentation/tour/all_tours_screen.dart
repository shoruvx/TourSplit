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

class AllToursScreen extends ConsumerWidget {
  const AllToursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (tours.isEmpty) {
            return _buildEmptyToursView(context, isDark);
          }

          final activeTours = tours.where((t) => t.isActive).toList();
          final pastTours = tours.where((t) => !t.isActive).toList();

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
                      onSelect: () async {
                        await ref
                            .read(tourRepositoryProvider)
                            .switchActiveTour(user.uid, t.id);
                        HapticFeedback.lightImpact();
                        if (context.mounted) context.go('/home');
                      },
                    )),
                const SizedBox(height: 24),
              ],
              if (pastTours.isNotEmpty) ...[
                _SectionTitle(title: 'Completed Tours (${pastTours.length})'),
                const SizedBox(height: 12),
                ...pastTours.map((t) => _TourCard(
                      tour: t,
                      isCurrentActive: t.id == user.activeTourId,
                      isAdmin: t.isAdmin(user.uid),
                      onSelect: () async {
                        await ref
                            .read(tourRepositoryProvider)
                            .switchActiveTour(user.uid, t.id);
                        HapticFeedback.lightImpact();
                        if (context.mounted) context.go('/home');
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

  const _TourCard({
    required this.tour,
    required this.isCurrentActive,
    required this.isAdmin,
    required this.onSelect,
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
                  if (isCurrentActive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.15),
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
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.qr_code_rounded, size: 20),
                      onPressed: () => TourQrDialog.show(
                        context,
                        tourName: tour.name,
                        inviteCode: tour.inviteCode,
                      ),
                    ),
                  ],
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt_outlined, size: 16),
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
