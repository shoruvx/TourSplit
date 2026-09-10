import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/tour_model.dart';
import '../../../data/models/settlement_model.dart';
import '../../../data/repositories/settlement_repository.dart';

class ManualSettlementDialog {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    required TourModel tour,
    required List<TourMemberModel> members,
    required Map<String, double> computedBalances,
    required String currentUserId,
    String? initialPayerId,
    String? initialRecipientId,
    double? initialAmount,
  }) async {
    if (members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least 2 tour members required for settlement')),
      );
      return;
    }

    // Default payer: pre-selected initialPayerId, or current user if in members, or first member
    String fromUid = initialPayerId ??
        (members.any((m) => m.userId == currentUserId)
            ? currentUserId
            : members.first.userId);

    // Default recipient: pre-selected or first member different from fromUid
    String toUid = initialRecipientId ??
        members
            .firstWhere((m) => m.userId != fromUid, orElse: () => members.last)
            .userId;

    final amountCtrl = TextEditingController(
      text: initialAmount != null && initialAmount > 0
          ? initialAmount.toStringAsFixed(initialAmount.truncateToDouble() == initialAmount ? 0 : 2)
          : '',
    );
    final noteCtrl = TextEditingController(text: 'Cash / Mobile Payment');

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final payerBalance = computedBalances[fromUid] ?? 0.0;
          final payerOwes = payerBalance < -0.01 ? -payerBalance : 0.0;

          final fromMember = members.firstWhere((m) => m.userId == fromUid,
              orElse: () => members.first);
          final toMember = members.firstWhere((m) => m.userId == toUid,
              orElse: () => members.last);

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.handshake_rounded,
                      color: AppColors.primaryTeal, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Manual Settlement',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payer (Who is paying?):',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: fromUid,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: members.map((m) {
                      final bal = computedBalances[m.userId] ?? 0.0;
                      final balText = bal < -0.01
                          ? ' (Owes ${tour.currencySymbol}${(-bal) % 1 == 0 ? (-bal).toStringAsFixed(0) : (-bal).toStringAsFixed(2)})'
                          : (bal > 0.01
                              ? ' (Gets back ${tour.currencySymbol}${bal % 1 == 0 ? bal.toStringAsFixed(0) : bal.toStringAsFixed(2)})'
                              : ' (Settled)');
                      return DropdownMenuItem(
                        value: m.userId,
                        child: Text(
                          '${m.displayName}$balText',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setS(() {
                          fromUid = val;
                          if (toUid == fromUid) {
                            toUid = members
                                .firstWhere((m) => m.userId != fromUid,
                                    orElse: () => members.last)
                                .userId;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Recipient (Who receives?):',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: toUid,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: members.where((m) => m.userId != fromUid).map((m) {
                      final bal = computedBalances[m.userId] ?? 0.0;
                      final balText = bal > 0.01
                          ? ' (Gets back ${tour.currencySymbol}${bal % 1 == 0 ? bal.toStringAsFixed(0) : bal.toStringAsFixed(2)})'
                          : (bal < -0.01
                              ? ' (Owes ${tour.currencySymbol}${(-bal) % 1 == 0 ? (-bal).toStringAsFixed(0) : (-bal).toStringAsFixed(2)})'
                              : ' (Settled)');
                      return DropdownMenuItem(
                        value: m.userId,
                        child: Text(
                          '${m.displayName}$balText',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setS(() => toUid = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Helper banner if payer has outstanding total debt
                  if (payerOwes > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primaryTeal.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 16, color: AppColors.primaryTeal),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${fromMember.displayName} owes ${tour.currencySymbol}${payerOwes % 1 == 0 ? payerOwes.toStringAsFixed(0) : payerOwes.toStringAsFixed(2)} in total across the tour.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              setS(() {
                                amountCtrl.text = payerOwes.toStringAsFixed(
                                    payerOwes.truncateToDouble() == payerOwes
                                        ? 0
                                        : 2);
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.bolt_rounded,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Pay Full Due (${tour.currencySymbol}${payerOwes % 1 == 0 ? payerOwes.toStringAsFixed(0) : payerOwes.toStringAsFixed(2)}) to ${toMember.displayName}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Text(
                    'Amount (${tour.currencySymbol}):',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '${tour.currencySymbol} ',
                      hintText: '0.00',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Payment Note / Method:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. bKash, Cash, Nagad, Bank',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'ℹ️ Note: Paying one person your full due will automatically adjust and recalculate the remaining debts across other members.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final amt = double.tryParse(amountCtrl.text.trim());
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount')),
                    );
                    return;
                  }
                  if (fromUid == toUid) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Payer and Recipient must be different')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Record Settlement'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
      final fromMember = members.firstWhere((m) => m.userId == fromUid);
      final toMember = members.firstWhere((m) => m.userId == toUid);

      final repo = ref.read(settlementRepositoryProvider);
      final settlement = await repo.requestSettlement(
        tourId: tour.id,
        fromUserId: fromUid,
        fromUserName: fromMember.displayName,
        toUserId: toUid,
        toUserName: toMember.displayName,
        amount: amt,
        currency: tour.currency,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );

      final isReceiver = currentUserId == toUid;
      if (isReceiver) {
        await repo.resolveSettlement(
          tourId: tour.id,
          settlementId: settlement.id,
          status: SettlementStatus.approved,
          resolvedByUserId: currentUserId,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isReceiver
                  ? 'Settlement recorded and approved! Balances adjusted.'
                  : 'Settlement recorded. Waiting for ${toMember.displayName} to approve.',
            ),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    }
  }
}
