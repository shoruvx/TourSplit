import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_model.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_cache_service.dart';
import '../../data/services/balance_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../widgets/member_avatar.dart';
import '../settlement/widgets/manual_settlement_dialog.dart';
import '../tour/widgets/replace_offline_member_dialog.dart';

class MemberProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final TourMemberModel? member;

  const MemberProfileScreen({
    super.key,
    required this.userId,
    this.member,
  });

  @override
  ConsumerState<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends ConsumerState<MemberProfileScreen> {
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

  void _copyToClipboard(String text, String label) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: text));
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
                'Copied $label ($text)',
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

  void _copyAccount(PaymentAccount acc) {
    _copyToClipboard(acc.accountNumber, '${acc.type} account');
    _copiedResetTimer?.cancel();
    setState(() => _copiedAccountId = acc.id);
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedAccountId = null);
    });
  }


  void _showRenameOfflineDialog(
      BuildContext parentContext, String tourId, TourMemberModel member) {
    final ctrl = TextEditingController(text: member.displayName);
    final formKey = GlobalKey<FormState>();
    final messenger = ScaffoldMessenger.of(parentContext);

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Rename Offline Friend',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Friend\'s Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Colors.white, width: 1.0),
              ),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() == true) {
                final newName = ctrl.text.trim();
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(tourRepositoryProvider)
                      .updateOfflineMemberName(
                        tourId: tourId,
                        memberId: member.userId,
                        newName: newName,
                      );
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Renamed to "$newName"'),
                      backgroundColor: AppColors.primaryTeal,
                    ),
                  );
                  if (mounted) setState(() {});
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to rename: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentUser = ref.watch(currentUserProvider).value;
    final isCurrentSelf = currentUser?.uid == widget.userId;

    final activeTourId = ref.watch(activeTourIdProvider) ?? currentUser?.activeTourId;

    // Load user doc if online
    final isOffline = widget.member?.isOffline == true ||
        widget.userId.startsWith('offline_');
    final userProfileAsync = isOffline
        ? const AsyncValue<UserModel?>.data(null)
        : ref.watch(userProfileProvider(widget.userId));

    // Load active tour if available
    final tourAsync = activeTourId != null
        ? ref.watch(tourStreamProvider(activeTourId))
        : null;
    final membersAsync = activeTourId != null
        ? ref.watch(tourMembersStreamProvider(activeTourId))
        : null;
    final expensesAsync = activeTourId != null
        ? ref.watch(tourExpensesStreamProvider(activeTourId))
        : null;
    final settlementsAsync = activeTourId != null
        ? ref.watch(tourSettlementsStreamProvider(activeTourId))
        : null;

    final tour = tourAsync?.value;
    final allMembers = membersAsync?.value ?? [];
    final currentTourMember = allMembers.firstWhereOrNull(
          (m) => m.userId == widget.userId,
        ) ??
        widget.member;

    final onlineUser = userProfileAsync.value;
    final cachedUser =
        !isOffline ? ref.watch(userBoxProvider(widget.userId)) : null;

    final resolvedUsername =
        (isCurrentSelf && currentUser?.username.isNotEmpty == true)
            ? currentUser!.username
            : (onlineUser?.username.isNotEmpty == true
                ? onlineUser!.username
                : (currentTourMember?.username.isNotEmpty == true
                    ? currentTourMember!.username
                    : (cachedUser?.username.isNotEmpty == true
                        ? cachedUser!.username
                        : '')));

    final displayName =
        (isCurrentSelf && currentUser?.displayName.isNotEmpty == true)
            ? currentUser!.displayName
            : (currentTourMember?.displayName.isNotEmpty == true
                ? currentTourMember!.displayName
                : (onlineUser?.displayName.isNotEmpty == true
                    ? onlineUser!.displayName
                    : (cachedUser?.displayName.isNotEmpty == true
                        ? cachedUser!.displayName
                        : (onlineUser?.email.isNotEmpty == true
                            ? onlineUser!.email.split('@').first
                            : 'Member'))));

    final email = currentTourMember?.email.isNotEmpty == true
        ? currentTourMember!.email
        : (onlineUser?.email.isNotEmpty == true
            ? onlineUser!.email
            : (isCurrentSelf ? (currentUser?.email ?? '') : ''));

    final usernameHandle = resolvedUsername.isNotEmpty
        ? resolvedUsername
        : (email.contains('@') ? email.split('@').first : '');

    final photoUrl = (isCurrentSelf &&
            currentUser?.photoUrl != null &&
            currentUser!.photoUrl!.isNotEmpty)
        ? currentUser.photoUrl
        : (currentTourMember?.photoUrl ??
            onlineUser?.photoUrl ??
            cachedUser?.photoUrl);

    final initials = currentTourMember?.initials ??
        (onlineUser?.initials.isNotEmpty == true
            ? onlineUser!.initials
            : (displayName.isNotEmpty ? displayName[0].toUpperCase() : '?'));

    final isCreator = tour != null && tour.adminId == widget.userId;
    final isCurrentAdmin =
        tour != null && currentUser != null && tour.isAdmin(currentUser.uid);

    // Compute active tour stats for this member
    double totalPaid = 0.0;
    double totalSpent = 0.0;
    double netBalance = currentTourMember?.balance ?? 0.0;

    if (tour != null && allMembers.isNotEmpty && expensesAsync?.value != null) {
      final approvedExpenses =
          expensesAsync!.value!.where((e) => e.isApproved).toList();
      final paidMap =
          BalanceService.calculateTotalPaid(allMembers, approvedExpenses);
      final spentMap =
          BalanceService.calculateTotalSpent(allMembers, approvedExpenses);

      totalPaid = paidMap[widget.userId] ?? 0.0;
      totalSpent = spentMap[widget.userId] ?? 0.0;

      var bals = BalanceService.calculateBalances(allMembers, approvedExpenses);
      if (settlementsAsync?.value != null) {
        final approvedSettlements =
            settlementsAsync!.value!.where((s) => s.isApproved).toList();
        bals = BalanceService.applySettlements(bals, approvedSettlements);
      }
      netBalance = bals[widget.userId] ?? 0.0;
    }

    final isPositive = netBalance > 0.01;
    final isNegative = netBalance < -0.01;

    final balanceColor = isPositive
        ? AppColors.positive
        : (isNegative
            ? AppColors.negative
            : (isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Profile'),
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
          if (isCurrentSelf) ...[
            IconButton(
              icon: Icon(Icons.edit_rounded,
                  color: isDark ? Colors.white : const Color(0xFF0F172A)),
              tooltip: 'Edit My Profile',
              onPressed: () => context.push('/profile'),
            ),
            if (tour != null && !isCreator && currentTourMember != null && !currentTourMember.isLeft)
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                tooltip: 'Leave Tour',
                onPressed: () => _confirmLeaveTour(
                    context, tour.id, tour.name, currentUser!.uid),
              ),
          ]
          else if (isCurrentAdmin && !isCurrentSelf && !isCreator && currentTourMember != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Manage Member',
              onSelected: (val) {
                if (val == 'rename') {
                  _showRenameOfflineDialog(context, tour.id, currentTourMember);
                } else if (val == 'link') {
                  ReplaceOfflineMemberDialog.show(
                    context,
                    tourId: tour.id,
                    offlineMember: currentTourMember,
                    allMembers: allMembers,
                  );
                } else if (val == 'remove') {
                  _confirmRemoveMember(context, tour.id, currentTourMember);
                }
              },
              itemBuilder: (ctx) => [
                if (isOffline && !currentTourMember.isLeft) ...[
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Rename Offline Friend'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'link',
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded,
                            size: 18, color: AppColors.primaryTeal),
                        SizedBox(width: 8),
                        Text('Link Online Friend'),
                      ],
                    ),
                  ),
                ],
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(Icons.person_remove_rounded,
                          size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Text(
                        currentTourMember.isLeft
                            ? 'Remove Completely'
                            : 'Remove Member',
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Hero Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.40 : 0.28),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.12 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOffline
                                ? Colors.blueGrey
                                : AppColors.primaryTeal,
                            width: 2.5,
                          ),
                        ),
                        child: MemberAvatar(
                          initials: initials,
                          photoUrl: photoUrl,
                          userId: widget.userId,
                          radius: 44,
                          enableTap: false,
                          backgroundColor: isOffline
                              ? Colors.blueGrey.withValues(alpha: 0.18)
                              : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isOffline ? Colors.blueGrey : AppColors.positive,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? AppColors.darkSurface : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          isOffline
                              ? Icons.cloud_off_rounded
                              : Icons.verified_user_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isOffline && usernameHandle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () =>
                          _copyToClipboard('@$usernameHandle', 'username'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$usernameHandle',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (isOffline)
                        _buildStatusChip(
                          label: 'Offline Companion',
                          icon: Icons.cloud_off_rounded,
                          color: Colors.blueGrey,
                        )
                      else
                        _buildStatusChip(
                          label: 'Online Member',
                          icon: Icons.check_circle_rounded,
                          color: AppColors.positive,
                        ),
                      if (isCreator)
                        _buildStatusChip(
                          label: 'Tour Creator',
                          icon: Icons.star_rounded,
                          color: Colors.amber,
                        ),
                      if (isCurrentSelf)
                        _buildStatusChip(
                          label: 'You',
                          icon: Icons.account_circle_rounded,
                          color: AppColors.primaryTeal,
                        ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 14),

            // "This is You" banner if visiting self
            if (isCurrentSelf)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.primaryTeal.withValues(alpha: 0.45),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.primaryTeal, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'This is how other members view your profile in TourSplit.',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.white, width: 1.0),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => context.push('/profile'),
                      child: const Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Tour Financial Activity Card (if active tour)
            if (tour != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.40 : 0.28),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryTeal
                          .withValues(alpha: isDark ? 0.10 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined,
                            size: 18, color: AppColors.primaryTeal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Activity in "${tour.name}"',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (currentTourMember?.joinedAt != null)
                          Text(
                            'Joined ${DateFormat('MMM yyyy').format(currentTourMember!.joinedAt)}',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            context: context,
                            title: 'Total Paid',
                            amount:
                                '${tour.currencySymbol}${totalPaid.toStringAsFixed(0)}',
                            subtitle: 'Out of pocket',
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            context: context,
                            title: 'Share / Spent',
                            amount:
                                '${tour.currencySymbol}${totalSpent.toStringAsFixed(0)}',
                            subtitle: 'Own expense share',
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            context: context,
                            title: 'Net Balance',
                            amount:
                                '${isPositive ? '+' : (isNegative ? '-' : '')}${tour.currencySymbol}${netBalance.abs().toStringAsFixed(0)}',
                            subtitle: isPositive
                                ? 'Gets back'
                                : (isNegative ? 'Owes' : 'Settled'),
                            color: balanceColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 250.ms, delay: 50.ms),
              const SizedBox(height: 14),
            ],

            // Preferred Payout Methods Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.primaryTeal
                      .withValues(alpha: isDark ? 0.40 : 0.28),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.10 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          size: 18, color: AppColors.primaryTeal),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Preferred Payout Methods',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (!isOffline &&
                          onlineUser?.paymentAccounts.isNotEmpty == true)
                        Text(
                          'Tap account to copy',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isOffline) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueGrey.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline companions do not have digital payout methods. Please settle balances directly in cash or through the tour organizer.',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (userProfileAsync.isLoading) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ] else if (onlineUser?.paymentAccounts.isEmpty ?? true) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No payout methods shared by $displayName yet.',
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ...onlineUser!.paymentAccounts.map((acc) {
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
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isCopied
                                  ? AppColors.primaryTeal.withValues(alpha: 0.1)
                                  : (isDark
                                      ? AppColors.darkBg.withValues(alpha: 0.6)
                                      : Colors.white),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
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
                                      horizontal: 8, vertical: 3.5),
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
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: badgeCol,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        acc.accountNumber,
                                        style: const TextStyle(
                                          fontFamily: 'Outfit',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      if (acc.note != null &&
                                          acc.note!.isNotEmpty)
                                        Text(
                                          acc.note!,
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 11,
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
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryTeal
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.chip),
                                            border: Border.all(
                                                color: AppColors.primaryTeal),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_rounded,
                                                  size: 13,
                                                  color: AppColors.primaryTeal),
                                              SizedBox(width: 4),
                                              Text(
                                                'Copied',
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
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                badgeCol.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.chip),
                                            border: Border.all(
                                                color: badgeCol
                                                    .withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.copy_rounded,
                                                  size: 11, color: badgeCol),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Copy',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontSize: 11,
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
                ],
              ),
            ).animate().fadeIn(duration: 250.ms, delay: 100.ms),

            const SizedBox(height: 16),

            // Quick Actions section (if not self)
            if (!isCurrentSelf) ...[
              if (tour != null && allMembers.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        side: const BorderSide(color: Colors.white, width: 1.0),
                      ),
                    ),
                    onPressed: () {
                      final computedBals = BalanceService.calculateBalances(
                        allMembers,
                        (expensesAsync?.value ?? [])
                            .where((e) => e.isApproved)
                            .toList(),
                      );
                      final approvedSets = (settlementsAsync?.value ?? [])
                          .where((s) => s.isApproved)
                          .toList();
                      final finalBals = BalanceService.applySettlements(
                          computedBals, approvedSets);

                      ManualSettlementDialog.show(
                        context,
                        ref: ref,
                        tour: tour,
                        members: allMembers,
                        computedBalances: finalBals,
                        currentUserId: currentUser?.uid ?? '',
                      );
                    },
                    icon: const Icon(Icons.handshake_rounded, size: 18),
                    label: const Text(
                      'Record Settlement with Member',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

              if (isOffline && isCurrentAdmin && currentTourMember != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryTeal,
                          side: BorderSide(
                            color: AppColors.primaryTeal.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () => _showRenameOfflineDialog(
                            context, tour.id, currentTourMember),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text(
                          'Rename Offline Friend',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.white, width: 1.0),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () => ReplaceOfflineMemberDialog.show(
                          context,
                          tourId: tour.id,
                          offlineMember: currentTourMember,
                          allMembers: allMembers,
                        ),
                        icon: const Icon(Icons.link_rounded, size: 16),
                        label: const Text(
                          'Link Online Friend',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required String title,
    required String amount,
    required String subtitle,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 10,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeaveTour(
    BuildContext context,
    String tourId,
    String tourName,
    String userId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Leave Tour?'),
          ],
        ),
        content: Text(
          'Are you sure you want to leave "$tourName"?\n\n'
          '• If you have 0 contribution and spending, you will be completely removed from everywhere in the tour.\n'
          '• If you have recorded expenses or splits, your history will stay intact for tour math and you will be listed as a left member.\n\n'
          'You can rejoin anytime using the tour invite code.',
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
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave Tour'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      final preservedAsPast = await ref
          .read(tourRepositoryProvider)
          .leaveTourWithAudit(tourId, userId);

      ref.invalidate(userToursStreamProvider(userId));
      ref.invalidate(tourStreamProvider(tourId));
      ref.invalidate(currentUserProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              preservedAsPast
                  ? 'You left the tour. Financial records remain intact.'
                  : 'You have been completely removed from the tour.',
            ),
            backgroundColor: AppColors.accent,
          ),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/all-tours');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave tour: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _confirmRemoveMember(
      BuildContext context, String tourId, TourMemberModel member) async {
    final hasTransactions = await ref
        .read(tourRepositoryProvider)
        .hasMemberTransactions(tourId, member.userId);

    if (!context.mounted) return;

    if (hasTransactions) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Member Cannot Be Removed'),
          content: Text(
            '${member.displayName} has recorded contributions, expenses, or settlements in this tour.\n\nTo preserve mathematical integrity of tour balances, members with recorded spending or splits cannot be completely removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove Member'),
        content: Text(
          'Remove "${member.displayName}" from this tour?\n\nSince this member has no contributions or expenses, they will be completely removed from tour calculations, member lists, and the tour card.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await ref.read(tourRepositoryProvider).removeMistakenMember(
                      tourId: tourId,
                      userId: member.userId,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${member.displayName} removed from tour'),
                      backgroundColor: AppColors.positive,
                    ),
                  );
                  context.pop();
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove member: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
