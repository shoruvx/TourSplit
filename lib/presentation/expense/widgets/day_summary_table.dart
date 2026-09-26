import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/services/user_cache_service.dart';

class DaySummaryTable extends StatefulWidget {
  final int dayNumber;
  final DateTime date;
  final List<ExpenseModel> expenses;
  final String currencySymbol;
  final Function(ExpenseModel)? onExpenseTap;
  final bool initialExpanded;

  const DaySummaryTable({
    super.key,
    required this.dayNumber,
    required this.date,
    required this.expenses,
    required this.currencySymbol,
    this.onExpenseTap,
    this.initialExpanded = false,
  });

  @override
  State<DaySummaryTable> createState() => _DaySummaryTableState();
}

class _DaySummaryTableState extends State<DaySummaryTable> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  double get _dayTotal => widget.expenses.fold(0.0, (sum, e) => sum + e.amount);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
              HapticFeedback.selectionClick();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'Day ${widget.dayNumber}',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${DateFormat('EEE, MMM d').format(widget.date)})',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${widget.currencySymbol}${_dayTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFCBD5E1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          'Expense Item',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Cost',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Payer',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Added',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...widget.expenses.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final exp = entry.value;
                  final isEven = idx % 2 == 0;
                  final rowBg = isDark
                      ? (isEven
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.03))
                      : (isEven ? Colors.white : const Color(0xFFF8FAFC));

                  final cachedPayer = UserCacheService.getUser(exp.paidByUserId);
                  final effectivePaidByName = (!exp.isMultiPayer &&
                          cachedPayer?.displayName != null &&
                          cachedPayer!.displayName.isNotEmpty)
                      ? cachedPayer.displayName
                      : exp.paidByName;
                  final payerName = effectivePaidByName.split(' ').first;
                  final payerDisplay = exp.isMultiPayer
                      ? 'multi-payer'
                      : payerName.toLowerCase();

                  final cachedAdder = UserCacheService.getUser(exp.addedByUserId);
                  final effectiveAdderName = exp.resolveAddedByName(cachedAdder?.displayName);
                  final adderName = effectiveAdderName.split(' ').first;
                  final adderDisplay = adderName.toLowerCase();

                  return InkWell(
                    onTap: widget.onExpenseTap != null
                        ? () => widget.onExpenseTap!(exp)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: rowBg,
                        border: Border(
                          bottom: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  exp.title,
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.darkText
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                if (exp.isMultiPayer)
                                  Text(
                                    exp.paidByName,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 10,
                                      color: isDark
                                          ? AppColors.primaryTeal.withValues(alpha: 0.8)
                                          : AppColors.primaryTeal,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0F2E28)
                                      : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF10B981)
                                            .withValues(alpha: 0.45)
                                        : const Color(0xFFA7F3D0),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '${widget.currencySymbol}${exp.amount % 1 == 0 ? exp.amount.toStringAsFixed(0) : exp.amount.toStringAsFixed(2)}',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF065F46),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: (!exp.isMultiPayer &&
                                      exp.paidByUserId ==
                                          FirebaseAuth
                                              .instance.currentUser?.uid)
                                  ? () {
                                      HapticFeedback.lightImpact();
                                      context.push('/profile');
                                    }
                                  : null,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    payerDisplay,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 11.5,
                                      color: exp.isMultiPayer
                                          ? AppColors.primaryTeal
                                          : (isDark
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF334155)),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (exp.isMultiPayer)
                                    Text(
                                      '(${exp.payers!.length} people)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 9.5,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: (exp.addedByUserId ==
                                      FirebaseAuth.instance.currentUser?.uid)
                                  ? () {
                                      HapticFeedback.lightImpact();
                                      context.push('/profile');
                                    }
                                  : null,
                              child: Text(
                                adderDisplay,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 11.5,
                                  color: exp.addedByUserId ==
                                          FirebaseAuth
                                              .instance.currentUser?.uid
                                      ? AppColors.primaryTeal
                                      : (isDark
                                          ? const Color(0xFFCBD5E1)
                                          : const Color(0xFF334155)),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
