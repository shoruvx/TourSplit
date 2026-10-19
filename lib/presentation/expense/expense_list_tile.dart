import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/expense_model.dart';
import '../../data/services/user_cache_service.dart';

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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return DateFormat('h:mm a').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MMM d, h:mm a').format(date);
    } else {
      return DateFormat('MMM d, yyyy, h:mm a').format(date);
    }
  }

  IconData _getCategoryIcon(String category, String title) {
    final t = title.toLowerCase();

    // Specific keyword heuristics for common travel expenses
    if (t.contains('coffee') ||
        t.contains('tea') ||
        t.contains('breakfast') ||
        t.contains('cafe') ||
        t.contains('cha ') ||
        t.contains('nasta') ||
        t.contains('bakery')) {
      return Icons.local_cafe_rounded;
    }
    if (t.contains('car') ||
        t.contains('gari') ||
        t.contains('cng') ||
        t.contains('bus') ||
        t.contains('train') ||
        t.contains('uber') ||
        t.contains('pathao') ||
        t.contains('ride') ||
        t.contains('taxi') ||
        t.contains('scooter') ||
        t.contains('bike') ||
        t.contains('chander') ||
        t.contains('nilgiri')) {
      return Icons.directions_car_rounded;
    }
    if (t.contains('boat') ||
        t.contains('launch') ||
        t.contains('ship') ||
        t.contains('ferry') ||
        t.contains('trawler') ||
        t.contains('kayak')) {
      return Icons.directions_boat_rounded;
    }
    if (t.contains('hotel') ||
        t.contains('resort') ||
        t.contains('stay') ||
        t.contains('room') ||
        t.contains('cottage') ||
        t.contains('hostel')) {
      return Icons.hotel_rounded;
    }
    if (t.contains('food') ||
        t.contains('lunch') ||
        t.contains('dinner') ||
        t.contains('restaurant') ||
        t.contains('meal') ||
        t.contains('biryani') ||
        t.contains('khichuri') ||
        t.contains('burger') ||
        t.contains('pizza') ||
        t.contains('meat') ||
        t.contains('fish') ||
        t.contains('sea stone')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('snack') ||
        t.contains('ice cream') ||
        t.contains('juice') ||
        t.contains('water') ||
        t.contains('drinks') ||
        t.contains('beverage')) {
      return Icons.fastfood_rounded;
    }
    if (t.contains('ticket') ||
        t.contains('entry') ||
        t.contains('park') ||
        t.contains('fee') ||
        t.contains('pass')) {
      return Icons.confirmation_number_rounded;
    }
    if (t.contains('fuel') ||
        t.contains('gas') ||
        t.contains('petrol') ||
        t.contains('octane') ||
        t.contains('diesel')) {
      return Icons.local_gas_station_rounded;
    }
    if (t.contains('shop') ||
        t.contains('market') ||
        t.contains('bazaar') ||
        t.contains('gift') ||
        t.contains('souvenir')) {
      return Icons.shopping_bag_rounded;
    }
    if (t.contains('med') ||
        t.contains('pharmacy') ||
        t.contains('doctor') ||
        t.contains('hospital')) {
      return Icons.medical_services_rounded;
    }

    // Category mapping fallback
    switch (category) {
      case 'Food':
      case 'Food & Drinks':
        return Icons.restaurant_rounded;
      case 'Transport':
        return Icons.directions_car_rounded;
      case 'Hotel':
      case 'Accommodation':
        return Icons.hotel_rounded;
      case 'Snacks':
        return Icons.local_cafe_rounded;
      case 'Activities':
        return Icons.attractions_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Fuel':
        return Icons.local_gas_station_rounded;
      case 'Medical':
        return Icons.medical_services_rounded;
      case 'Entry Tickets':
        return Icons.confirmation_number_rounded;
      case 'Miscellaneous':
        return Icons.inventory_2_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cachedName = UserCacheService.getUser(expense.paidByUserId)?.displayName;
    final effectivePaidByName = (!expense.isMultiPayer && cachedName != null && cachedName.isNotEmpty)
        ? cachedName
        : expense.paidByName;
    final displayName = expense.isMultiPayer
        ? effectivePaidByName
        : (effectivePaidByName.trim().isNotEmpty
            ? effectivePaidByName.trim().split(' ').first
            : 'Unknown');

    final memberCount = expense.splitAmong.isNotEmpty ? expense.splitAmong.length : 1;
    final perPerson = expense.amount / memberCount;
    final iconData = _getCategoryIcon(expense.category, expense.title);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3447) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Category icon squircle
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141923) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF232D3F) : const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      iconData,
                      size: 21,
                      color: isDark ? const Color(0xFF2DD4BF) : AppColors.primaryTeal,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Title and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        expense.title,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.lightText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$displayName paid',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              fontSize: 11.5,
                            ),
                          ),
                          Text(
                            _formatDate(expense.date),
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                          if (expense.status != ExpenseStatus.approved) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _statusColor.withValues(alpha: 0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                _statusLabel,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Total amount and per-person split
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$currencySymbol${NumberFormat('#,##0.##').format(expense.amount)}',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.lightText,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$currencySymbol${NumberFormat('#,##0.##').format(perPerson)} / person',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF00BFA5) : const Color(0xFF00897B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
