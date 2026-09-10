import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';

class ReceiverPaymentAccountsView extends ConsumerStatefulWidget {
  final String toUserId;
  final String toUserName;

  const ReceiverPaymentAccountsView({
    super.key,
    required this.toUserId,
    required this.toUserName,
  });

  @override
  ConsumerState<ReceiverPaymentAccountsView> createState() =>
      _ReceiverPaymentAccountsViewState();
}

class _ReceiverPaymentAccountsViewState
    extends ConsumerState<ReceiverPaymentAccountsView> {
  String? _copiedAccountId;
  Timer? _copiedResetTimer;

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  Color _badgeColor(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('bkash')) return const Color(0xFFE2136E);
    if (lower.contains('nagad')) return const Color(0xFFF7941D);
    if (lower.contains('rocket')) return const Color(0xFF8C3494);
    if (lower.contains('bank')) return AppColors.primaryBlue;
    return AppColors.primaryTeal;
  }

  void _copyAccount(PaymentAccount acc) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: acc.accountNumber));

    _copiedResetTimer?.cancel();
    setState(() => _copiedAccountId = acc.id);
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedAccountId = null);
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primaryTeal, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Copied ${acc.type} number (${acc.accountNumber})',
                style: const TextStyle(fontFamily: 'Outfit'),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider(widget.toUserId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return userAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (user) {
        final accounts = user?.paymentAccounts ?? [];
        if (accounts.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(AppRadius.container),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No payout method shared by ${widget.toUserName}.',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11.5,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface
                : AppColors.primaryTeal.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.container),
            border: Border.all(
              color: AppColors.primaryTeal.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: AppColors.primaryTeal),
                  const SizedBox(width: 6),
                  Text(
                    'Pay ${widget.toUserName} via:',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.primaryTeal,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to copy',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 10.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...accounts.map((acc) {
                final badgeCol = _badgeColor(acc.type);
                final isCopied = _copiedAccountId == acc.id;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _copyAccount(acc),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    splashColor: badgeCol.withValues(alpha: 0.15),
                    highlightColor: badgeCol.withValues(alpha: 0.08),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCopied
                            ? AppColors.primaryTeal.withValues(alpha: 0.1)
                            : (isDark
                                ? AppColors.darkBg.withValues(alpha: 0.6)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        border: Border.all(
                          color: isCopied
                              ? AppColors.primaryTeal
                              : (isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder),
                          width: isCopied ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeCol.withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.chip),
                              border: Border.all(
                                color: badgeCol.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              acc.type.toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: badgeCol,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  acc.accountNumber,
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                if (acc.note != null && acc.note!.isNotEmpty)
                                  Text(
                                    acc.note!,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 10.5,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isCopied
                                ? Container(
                                    key: const ValueKey('copied'),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryTeal
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.chip),
                                      border: Border.all(
                                          color: AppColors.primaryTeal),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_rounded,
                                            size: 13,
                                            color: AppColors.primaryTeal),
                                        SizedBox(width: 3),
                                        Text(
                                          'Copied!',
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryTeal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    key: const ValueKey('copy'),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badgeCol.withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.chip),
                                      border: Border.all(
                                          color:
                                              badgeCol.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.copy_rounded,
                                            size: 11, color: badgeCol),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap to Copy',
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: badgeCol,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
