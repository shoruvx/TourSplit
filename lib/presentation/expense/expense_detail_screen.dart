import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/expense_model.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final String expenseId;
  const ExpenseDetailScreen({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('Not available')));
    }

    final tourId = user.activeTourId!;
    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));
    final expenseStream = ref.watch(singleExpenseStreamProvider((tourId: tourId, expenseId: expenseId)));

    return expenseStream.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (expense) {
        if (expense == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Expense not found or deleted')),
          );
        }

        return tourStream.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (tour) {
            if (tour == null) return const Scaffold();
            if (!tour.memberIds.contains(user.uid)) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text('You are no longer a member of this tour.')),
              );
            }
            final isAdmin = tour.isAdmin(user.uid);
            final canEdit = isAdmin || expense.paidByUserId == user.uid || expense.addedByUserId == user.uid;

            return membersStream.when(
              loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
              error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
              data: (members) {
                final memberMap = {
                  for (final m in members) m.userId: m.displayName
                };

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Expense Details'),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => context.pop(),
                    ),
                    actions: [
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, color: AppColors.primaryTeal),
                          tooltip: 'Edit Expense',
                          onPressed: () => context.push('/expense/edit', extra: expense),
                        ),
                      if (isAdmin && expense.isPending)
                        PopupMenuButton<String>(
                          onSelected: (v) =>
                              _handleAction(context, ref, tourId, expense, v),
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'approve',
                              child: Row(children: [
                                Icon(Icons.check_circle_outline,
                                    color: AppColors.positive),
                                SizedBox(width: 8),
                                Text('Approve'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'reject',
                              child: Row(children: [
                                Icon(Icons.cancel_outlined,
                                    color: AppColors.negative),
                                SizedBox(width: 8),
                                Text('Reject'),
                              ]),
                            ),
                          ],
                        ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
                          tooltip: 'Delete Expense',
                          onPressed: () => _confirmDelete(context, ref, tourId, expense),
                        ),
                    ],
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Amount card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${tour.currencySymbol} ${expense.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                expense.title,
                                style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    color: Colors.white70,
                                    fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              _StatusBadge(expense: expense),
                            ],
                          ),
                        ).animate().fadeIn().scale(),
                        const SizedBox(height: 24),

                        _InfoRow(label: 'Category', value: expense.category),
                        _InfoRow(
                            label: 'Date',
                            value: DateFormat('EEEE, MMM d, y')
                                .format(expense.date)),
                        _InfoRow(
                            label: 'Paid By', value: expense.paidByName),
                        _InfoRow(
                            label: 'Split Type',
                            value: _splitLabel(expense.splitType)),
                        if (expense.description != null)
                          _InfoRow(
                              label: 'Note',
                              value: expense.description!),
                        const Divider(height: 32),

                        if (expense.isMultiPayer) ...[
                          Text('Payment Contributions',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          ...expense.contributions.entries.map((entry) {
                            final name = memberMap[entry.key] ?? entry.key;
                            return _SplitRow(
                              name: name,
                              amount: entry.value,
                              symbol: tour.currencySymbol,
                            ).animate().fadeIn(delay: 30.ms);
                          }),
                          const Divider(height: 32),
                        ],

                        Text('Split Breakdown',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...expense.splits.entries.map((entry) {
                          final name =
                              memberMap[entry.key] ?? entry.key;
                          return _SplitRow(
                            name: name,
                            amount: entry.value,
                            symbol: tour.currencySymbol,
                          ).animate().fadeIn(delay: 50.ms);
                        }),

                        if (isAdmin && expense.isPending) ...[
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _handleAction(context,
                                      ref, tourId, expense, 'reject'),
                                  icon: const Icon(Icons.close_rounded,
                                      color: AppColors.negative),
                                  label: const Text('Reject',
                                      style: TextStyle(
                                          color: AppColors.negative)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: AppColors.negative),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _handleAction(context,
                                      ref, tourId, expense, 'approve'),
                                  icon: const Icon(
                                      Icons.check_rounded),
                                  label: const Text('Approve'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.positive,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (canEdit) ...[
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/expense/edit', extra: expense),
                              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                              label: Text(
                                isAdmin ? 'Edit Expense (Admin)' : 'Edit My Expense',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryTeal,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _splitLabel(SplitType type) {
    switch (type) {
      case SplitType.equal:
        return 'Equal among all';
      case SplitType.selected:
        return 'Equal among selected';
      case SplitType.custom:
        return 'Custom amounts';
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String tourId, ExpenseModel expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Are you sure you want to delete "${expense.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(expenseRepositoryProvider).deleteExpense(tourId, expense.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted successfully'), backgroundColor: AppColors.negative),
        );
        context.pop();
      }
    }
  }

  void _handleAction(BuildContext context, WidgetRef ref, String tourId,
      ExpenseModel expense, String action) async {
    final status = action == 'approve'
        ? ExpenseStatus.approved
        : ExpenseStatus.rejected;
    await ref
        .read(expenseRepositoryProvider)
        .updateExpenseStatus(tourId, expense.id, status);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve'
              ? 'Expense approved!'
              : 'Expense rejected.'),
          backgroundColor:
              action == 'approve' ? AppColors.positive : AppColors.negative,
        ),
      );
      context.pop();
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final ExpenseModel expense;
  const _StatusBadge({required this.expense});

  @override
  Widget build(BuildContext context) {
    final color = expense.isApproved
        ? AppColors.positive
        : expense.isRejected
            ? AppColors.negative
            : AppColors.warning;
    final label = expense.isApproved
        ? '✓ Approved'
        : expense.isRejected
            ? '✗ Rejected'
            : '⏳ Pending Approval';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Outfit',
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                )),
          ),
          Expanded(
              child: Text(value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final String name;
  final double amount;
  final String symbol;
  const _SplitRow(
      {required this.name,
      required this.amount,
      required this.symbol});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name,
              style: const TextStyle(fontFamily: 'Outfit', fontSize: 14)),
          Text(
            '$symbol ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
