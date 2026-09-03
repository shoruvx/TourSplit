import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/models/settlement_model.dart';

class SettlementScreen extends ConsumerWidget {
  const SettlementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }
    final tourId = user.activeTourId!;

    final tourStream = ref.watch(tourStreamProvider(tourId));
    final settlementsStream =
        ref.watch(tourSettlementsStreamProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();
        final isAdmin = tour.adminId == user.uid;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settlements'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => context.pop(),
            ),
          ),
          body: settlementsStream.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (settlements) {
              if (settlements.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('💸',
                          style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text('No settlements yet',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'Go to Balances → Settle Up to request one',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              // Group into pending and resolved
              final pending =
                  settlements.where((s) => s.isPending).toList();
              final resolved =
                  settlements.where((s) => !s.isPending).toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (pending.isNotEmpty) ...[
                    _SectionLabel(
                        label: 'Pending',
                        color: AppColors.warning,
                        count: pending.length),
                    const SizedBox(height: 8),
                    ...pending.map((s) => _SettlementCard(
                          settlement: s,
                          isAdmin: isAdmin,
                          currentUserId: user.uid,
                          currency: tour.currencySymbol,
                          onApprove: () => _resolve(context, ref,
                              tourId, s, SettlementStatus.approved),
                          onReject: () => _resolve(context, ref,
                              tourId, s, SettlementStatus.rejected),
                        ).animate().fadeIn()),
                    const SizedBox(height: 20),
                  ],
                  if (resolved.isNotEmpty) ...[
                    _SectionLabel(
                        label: 'History',
                        color: AppColors.accent,
                        count: resolved.length),
                    const SizedBox(height: 8),
                    ...resolved.map((s) => _SettlementCard(
                          settlement: s,
                          isAdmin: isAdmin,
                          currentUserId: user.uid,
                          currency: tour.currencySymbol,
                        ).animate().fadeIn()),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _resolve(BuildContext context, WidgetRef ref, String tourId,
      SettlementModel s, SettlementStatus status) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    await ref.read(settlementRepositoryProvider).resolveSettlement(
          tourId: tourId,
          settlementId: s.id,
          status: status,
          resolvedByUserId: user.uid,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == SettlementStatus.approved
                ? 'Settlement approved!'
                : 'Settlement rejected.',
          ),
          backgroundColor: status == SettlementStatus.approved
              ? AppColors.positive
              : AppColors.negative,
        ),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _SectionLabel(
      {required this.label, required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettlementCard extends StatelessWidget {
  final SettlementModel settlement;
  final bool isAdmin;
  final String currentUserId;
  final String currency;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _SettlementCard({
    required this.settlement,
    required this.isAdmin,
    required this.currentUserId,
    required this.currency,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    String statusText;
    switch (settlement.status) {
      case SettlementStatus.requested:
        statusColor = AppColors.warning;
        statusText = 'Pending';
      case SettlementStatus.approved:
        statusColor = AppColors.positive;
        statusText = '✓ Approved';
      case SettlementStatus.rejected:
        statusColor = AppColors.negative;
        statusText = '✗ Rejected';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
                      RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: settlement.fromUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.negative,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            const TextSpan(text: ' → '),
                            TextSpan(
                              text: settlement.toUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.positive,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$currency ${settlement.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Requested ${DateFormat('MMM d, y').format(settlement.requestedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (settlement.resolvedAt != null)
              Text(
                'Resolved ${DateFormat('MMM d, y').format(settlement.resolvedAt!)}',
                style: theme.textTheme.bodySmall,
              ),

            // Admin or recipient approve/reject buttons
            if ((isAdmin || settlement.toUserId == currentUserId) && settlement.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        side:
                            const BorderSide(color: AppColors.negative),
                        minimumSize: const Size(0, 38),
                      ),
                      child: const Text('Reject',
                          style: TextStyle(
                              color: AppColors.negative,
                              fontFamily: 'Outfit')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.positive,
                        minimumSize: const Size(0, 38),
                      ),
                      child: const Text('Approve',
                          style: TextStyle(fontFamily: 'Outfit')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
