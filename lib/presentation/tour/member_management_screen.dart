import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/models/tour_model.dart';
import '../widgets/member_avatar.dart';
import 'widgets/tour_qr_dialog.dart';

class MemberManagementScreen extends ConsumerWidget {
  const MemberManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final tourId = user.activeTourId!;
    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));
    final joinRequestsStream = ref.watch(tourPendingJoinRequestsProvider(tourId));

    return tourStream.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();
        if (!tour.memberIds.contains(user.uid)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Members')),
            body: const Center(child: Text('You are no longer a member of this tour.')),
          );
        }
        final isAdmin = tour.isAdmin(user.uid);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Members'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.person_add_rounded),
                  onPressed: () =>
                      _showInviteDialog(context, ref, tour, user.displayName),
                  tooltip: 'Invite Member',
                ),
            ],
          ),
          body: Column(
            children: [
              // Invite code banner
              _InviteCodeBanner(
                tourName: tour.name,
                inviteCode: tour.inviteCode,
              ),

              // Pending Join Requests (Admins only)
              if (isAdmin)
                joinRequestsStream.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (requests) {
                    if (requests.isEmpty) return const SizedBox();
                    return _PendingRequestsCard(
                      tourId: tour.id,
                      requests: requests,
                    );
                  },
                ),

              // Members list
              Expanded(
                child: membersStream.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (members) {
                    if (members.isEmpty) {
                      return const Center(child: Text('No members yet'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: members.length,
                      itemBuilder: (context, i) {
                        final member = members[i];
                        final isCreator = member.userId == tour.adminId;
                        final isMemberAdmin = tour.isAdmin(member.userId);

                        return _MemberCard(
                          member: member,
                          isCreator: isCreator,
                          isMemberAdmin: isMemberAdmin,
                          isAdmin: isAdmin,
                          currentUserId: user.uid,
                          currencySymbol: tour.currencySymbol,
                          onToggleAdmin: isAdmin && !isCreator
                              ? () => _toggleAdminRole(context, ref, tour.id, member, isMemberAdmin)
                              : null,
                          onRemove: isAdmin && !isCreator && member.userId != user.uid
                              ? () => _removeMember(context, ref, tourId, member)
                              : null,
                        ).animate().fadeIn(
                            delay: Duration(milliseconds: i * 60),
                            duration: 300.ms);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleAdminRole(BuildContext context, WidgetRef ref, String tourId,
      TourMemberModel member, bool currentlyAdmin) {
    final newRole = currentlyAdmin ? 'member' : 'admin';
    final actionText = currentlyAdmin ? 'Revoke Admin' : 'Make Admin';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(actionText),
        content: Text(currentlyAdmin
            ? 'Demote ${member.displayName} to regular member?'
            : 'Promote ${member.displayName} to tour admin? They will be able to approve joins, expenses, and manage members.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(tourRepositoryProvider)
                  .setMemberRole(tourId: tourId, userId: member.userId, role: newRole);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${member.displayName} is now an $newRole!'),
                    backgroundColor: AppColors.accent,
                  ),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref,
      TourModel tour, String inviterName) {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Member',
            style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Invite by email or share the tour code:',
                style: TextStyle(fontFamily: 'Outfit')),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'member@example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (emailCtrl.text.trim().isNotEmpty) {
                await ref.read(tourRepositoryProvider).inviteMemberByEmail(
                      tourId: tour.id,
                      email: emailCtrl.text.trim(),
                      inviterName: inviterName,
                    );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Invite sent!'),
                        backgroundColor: AppColors.accent),
                  );
                }
              }
            },
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }

  void _removeMember(BuildContext context, WidgetRef ref, String tourId,
      TourMemberModel member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content:
            Text('Remove ${member.displayName} from this tour?\n\nNote: All expenses previously paid or shared by this member will remain intact in the tour ledger.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger),
            onPressed: () async {
              try {
                await ref
                    .read(tourRepositoryProvider)
                    .removeMember(tourId, member.userId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${member.displayName} removed from tour'),
                    ),
                  );
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

/// Pending Join Requests Card for Admins
class _PendingRequestsCard extends ConsumerWidget {
  final String tourId;
  final List<JoinRequestModel> requests;

  const _PendingRequestsCard({
    required this.tourId,
    required this.requests,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryTeal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primaryTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                'Join Requests (${requests.length})',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.primaryTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...requests.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    MemberAvatar(
                      initials: r.displayName.isNotEmpty ? r.displayName[0] : '?',
                      photoUrl: r.photoUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            r.email,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 22),
                      tooltip: 'Reject',
                      onPressed: () => ref
                          .read(tourRepositoryProvider)
                          .rejectJoinRequest(tourId: tourId, userId: r.userId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.positive, size: 22),
                      tooltip: 'Approve',
                      onPressed: () => ref
                          .read(tourRepositoryProvider)
                          .approveJoinRequest(tourId: tourId, request: r),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _InviteCodeBanner extends StatelessWidget {
  final String tourName;
  final String inviteCode;

  const _InviteCodeBanner({
    required this.tourName,
    required this.inviteCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOUR INVITE CODE',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  inviteCode,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                onPressed: () => TourQrDialog.show(
                  context,
                  tourName: tourName,
                  inviteCode: inviteCode,
                ),
                tooltip: 'Show QR Code',
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copied!')),
                  );
                },
                tooltip: 'Copy Code',
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () {
                  Share.share(
                    'Join my tour on TourSplit!\nInvite code: $inviteCode',
                  );
                },
                tooltip: 'Share Code',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final TourMemberModel member;
  final bool isCreator;
  final bool isMemberAdmin;
  final bool isAdmin;
  final String currentUserId;
  final String currencySymbol;
  final VoidCallback? onToggleAdmin;
  final VoidCallback? onRemove;

  const _MemberCard({
    required this.member,
    required this.isCreator,
    required this.isMemberAdmin,
    required this.isAdmin,
    required this.currentUserId,
    required this.currencySymbol,
    this.onToggleAdmin,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCurrentUser = member.userId == currentUserId;

    Color balanceColor = member.balance > 0
        ? AppColors.positive
        : member.balance < 0
            ? AppColors.negative
            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            MemberAvatar(
              initials: member.initials,
              photoUrl: member.photoUrl,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        member.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primaryTeal,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (isCreator) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Creator',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ] else if (isMemberAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.teal,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  member.balance >= 0
                      ? '+$currencySymbol${member.balance.toStringAsFixed(0)}'
                      : '-$currencySymbol${(-member.balance).toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: balanceColor,
                  ),
                ),
                Text(
                  member.balance > 0
                      ? 'gets back'
                      : member.balance < 0
                          ? 'owes'
                          : 'settled',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 10,
                    color: balanceColor,
                  ),
                ),
              ],
            ),
            if (isAdmin && !isCreator && !isCurrentUser) ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (val) {
                  if (val == 'role') {
                    onToggleAdmin?.call();
                  } else if (val == 'remove') {
                    onRemove?.call();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'role',
                    child: Text(isMemberAdmin ? 'Revoke Admin' : 'Make Admin'),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove Member', style: TextStyle(color: AppColors.danger)),
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
