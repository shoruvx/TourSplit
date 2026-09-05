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
    final user = ref.watch(currentUserProvider).value;

    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final tourId = user.activeTourId!;
    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));
    final joinRequestsStream =
        ref.watch(tourPendingJoinRequestsProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();
        if (!tour.memberIds.contains(user.uid)) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Members'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
            body: const Center(
                child: Text('You are no longer a member of this tour.')),
          );
        }
        final isAdmin = tour.isAdmin(user.uid);

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
              title: const Text('Members'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            actions: [
              if (isAdmin) ...[
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  onPressed: () =>
                      _showAddOfflineMemberDialog(context, ref, tour.id),
                  tooltip: 'Add Offline Friend',
                ),
                IconButton(
                  icon: const Icon(Icons.mail_outline_rounded),
                  onPressed: () =>
                      _showInviteDialog(context, ref, tour, user.displayName),
                  tooltip: 'Invite by Email',
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              _InviteCodeBanner(
                tourName: tour.name,
                inviteCode: tour.inviteCode,
              ),
              if (isAdmin)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showAddOfflineMemberDialog(context, ref, tour.id),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: const Text(
                        'Add Offline Friend (Name Only)',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryTeal,
                        side: BorderSide(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
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
                          onToggleAdmin: isAdmin && !isCreator && !member.isOffline
                              ? () => _toggleAdminRole(
                                  context, ref, tour.id, member, isMemberAdmin)
                              : null,
                          onRename: isAdmin && member.isOffline
                              ? () => _showRenameOfflineMemberDialog(
                                  context, ref, tourId, member)
                              : null,
                          onRemove: isAdmin &&
                                  !isCreator &&
                                  member.userId != user.uid
                              ? () =>
                                  _removeMember(context, ref, tourId, member)
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
              await ref.read(tourRepositoryProvider).setMemberRole(
                  tourId: tourId, userId: member.userId, role: newRole);
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

  void _showInviteDialog(
      BuildContext context, WidgetRef ref, TourModel tour, String inviterName) {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Member',
            style:
                TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700)),
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

  void _showAddOfflineMemberDialog(
      BuildContext context, WidgetRef ref, String tourId) {
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: AppColors.primaryTeal, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Add Offline Friend',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a friend using only their name. No phone, email, or device needed. You can track expenses & splits for them, and they will be visible to all members in this tour.',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Friend\'s Name',
                  hintText: 'e.g. Alex, Rahim, John',
                  prefixIcon: const Icon(Icons.badge_outlined),
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
            ],
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() == true) {
                final name = nameCtrl.text.trim();
                Navigator.pop(ctx);
                try {
                  await ref.read(tourRepositoryProvider).addOfflineMember(
                        tourId: tourId,
                        name: name,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Offline friend "$name" added to tour!'),
                        backgroundColor: AppColors.positive,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add offline member: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text(
              'Add to Tour',
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

  void _showRenameOfflineMemberDialog(BuildContext context, WidgetRef ref,
      String tourId, TourMemberModel member) {
    final ctrl = TextEditingController(text: member.displayName);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
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
                  borderRadius: BorderRadius.circular(14)),
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
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Renamed to "$newName"'),
                        backgroundColor: AppColors.accent,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to rename: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
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

  void _removeMember(BuildContext context, WidgetRef ref, String tourId,
      TourMemberModel member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
            'Remove ${member.displayName} from this tour?\n\nNote: All expenses previously paid or shared by this member will remain intact in the tour ledger.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
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
              const Icon(Icons.person_add_alt_1_rounded,
                  color: AppColors.primaryTeal, size: 20),
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
                      initials:
                          r.displayName.isNotEmpty ? r.displayName[0] : '?',
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            r.email,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppColors.danger, size: 22),
                      tooltip: 'Reject',
                      onPressed: () => ref
                          .read(tourRepositoryProvider)
                          .rejectJoinRequest(tourId: tourId, userId: r.userId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded,
                          color: AppColors.positive, size: 22),
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
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  const _MemberCard({
    required this.member,
    required this.isCreator,
    required this.isMemberAdmin,
    required this.isAdmin,
    required this.currentUserId,
    required this.currencySymbol,
    this.onToggleAdmin,
    this.onRename,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCurrentUser = member.userId == currentUserId;

    final isSettled = member.balance.abs() < 0.01;
    Color balanceColor = isSettled
        ? (isDark
            ? AppColors.darkTextSecondary
            : AppColors.lightTextSecondary)
        : member.balance > 0
            ? AppColors.positive
            : AppColors.negative;

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
              backgroundColor: member.isOffline
                  ? Colors.blueGrey.withValues(alpha: 0.2)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (member.isOffline) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.blueGrey.withValues(alpha: 0.35)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  size: 10, color: Colors.blueGrey),
                              SizedBox(width: 3),
                              Text(
                                'Offline',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueGrey,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.15),
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
                      if (member.isLeft) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            member.status == 'removed' ? 'Removed' : 'Left',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.isOffline
                        ? 'Offline friend · Visible to all members'
                        : member.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                      fontStyle:
                          member.isOffline ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isSettled
                      ? '$currencySymbol 0'
                      : member.balance > 0
                          ? '+$currencySymbol${(member.balance % 1 == 0 ? member.balance.toStringAsFixed(0) : member.balance.toStringAsFixed(2))}'
                          : '-$currencySymbol${((-member.balance) % 1 == 0 ? (-member.balance).toStringAsFixed(0) : (-member.balance).toStringAsFixed(2))}',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: balanceColor,
                  ),
                ),
                Text(
                  isSettled
                      ? 'settled'
                      : member.balance > 0
                          ? 'gets back'
                          : 'owes',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 10,
                    color: balanceColor,
                  ),
                ),
              ],
            ),
            if (isAdmin && !isCreator && !isCurrentUser && !member.isLeft) ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (val) {
                  if (val == 'role') {
                    onToggleAdmin?.call();
                  } else if (val == 'rename') {
                    onRename?.call();
                  } else if (val == 'remove') {
                    onRemove?.call();
                  }
                },
                itemBuilder: (ctx) => [
                  if (!member.isOffline)
                    PopupMenuItem(
                      value: 'role',
                      child: Text(isMemberAdmin ? 'Revoke Admin' : 'Make Admin'),
                    ),
                  if (member.isOffline)
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Rename Friend'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.danger),
                        SizedBox(width: 8),
                        Text('Remove Member',
                            style: TextStyle(color: AppColors.danger)),
                      ],
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
