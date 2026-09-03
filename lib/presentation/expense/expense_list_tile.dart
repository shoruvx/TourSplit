import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/expense_model.dart';

class ExpenseListTile extends StatelessWidget {
  final ExpenseModel expense;
  final String currencySymbol;
  final VoidCallback? onTap;

  const ExpenseListTile({
    super.key,
    required this.expense,
    required this.currencySymbol,
    this.onTap,
  });

  Color get _statusColor {
    switch (expense.status) {
      case ExpenseStatus.approved:
        return AppColors.positive;
      case ExpenseStatus.rejected:
        return AppColors.negative;
      case ExpenseStatus.pendingApproval:
        return AppColors.warning;
    }
  }

  String get _statusLabel {
    switch (expense.status) {
      case ExpenseStatus.approved:
        return 'Approved';
      case ExpenseStatus.rejected:
        return 'Rejected';
      case ExpenseStatus.pendingApproval:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _getCategoryEmoji(expense.category),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        expense.category,
                        style: theme.textTheme.bodySmall,
                      ),
                      const Text(' · ',
                          style: TextStyle(color: Colors.grey)),
                      Text(
                        'Paid by ${expense.paidByName.split(' ').first}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM d · h:mm a').format(expense.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Glowing High-Contrast Amount Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFF0F2E28),
                              const Color(0xFF064E3B),
                            ]
                          : [
                              const Color(0xFFECFDF5),
                              const Color(0xFFD1FAE5),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : const Color(0xFF10B981).withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currencySymbol,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        NumberFormat('#,##0.##').format(expense.amount),
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF064E3B),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                // Status Indicator with colored dot
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: isDark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _statusColor.withValues(alpha: isDark ? 0.35 : 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryEmoji(String category) {
    const map = {
      'Food & Drinks': '🍽️',
      'Transport': '🚗',
      'Accommodation': '🏨',
      'Activities': '🎭',
      'Shopping': '🛍️',
      'Fuel': '⛽',
      'Medical': '💊',
      'Entry Tickets': '🎟️',
      'Miscellaneous': '📦',
    };
    return map[category] ?? '📦';
  }
}
