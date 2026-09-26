import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_cache_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../home/home_screen.dart' show localMembersRefreshProvider;
import '../widgets/member_avatar.dart';
import 'widgets/tour_qr_dialog.dart';
import 'widgets/replace_offline_member_dialog.dart';
import 'widgets/add_member_dialog.dart';
import '../widgets/app_bottom_nav_bar.dart';

class MemberManagementScreen extends ConsumerWidget {
  final String? tourId;
  const MemberManagementScreen({super.key, this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final activeTourId = ref.watch(activeTourIdProvider);
    final effectiveTourId = tourId ??
        activeTourId ??
        user?.activeTourId ??
        cachedTour?.id ??
        ActiveTourCacheService.getActiveTourId();

    if (effectiveTourId == null) {
      if (userAsync.isLoading) {
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      }
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final currentUserId =
        user?.uid ?? ref.watch(authStateProvider).value?.uid ?? '';
    final tourStream = ref.watch(tourStreamProvider(effectiveTourId));
    final membersStream = ref.watch(tourMembersStreamProvider(effectiveTourId));
    final joinRequestsStream =
        ref.watch(tourPendingJoinRequestsProvider(effectiveTourId));

    final effectiveTour = tourStream.value ?? (cachedTour?.id == effectiveTourId ? cachedTour : null) ?? cachedTour;
    if (effectiveTour == null && tourStream.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tour = effectiveTour ?? tourStream.value;
    if (tour == null) {
      return tourStream.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        data: (_) => const Scaffold(),
      );
    }
    if (currentUserId.isNotEmpty &&
        !tour.memberIds.contains(currentUserId)) {
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
        final isAdmin = tour.isAdmin(currentUserId);
        final inviterName = user?.displayName.isNotEmpty == true
            ? user!.displayName
            : 'A friend';
        final isDark = Theme.of(context).brightness == Brightness.dark;

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
              automaticallyImplyLeading: false,
              toolbarHeight: 64,
              titleSpacing: 20,
              title: const Text(
                'Members',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppColors.primaryTeal,
                ),
              ),
              actions: [
                if (isAdmin)
                  IconButton(
                    icon: Icon(Icons.person_add_alt_1_rounded,
                        color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    onPressed: () {
                      final members = membersStream.value ?? [];
                      AddMemberDialog.show(
                        context,
                        tourId: tour.id,
                        inviterName: inviterName,
                        currentMembers: members,
                      );
                    },
                    tooltip: 'Add Member',
                  ),
                if (currentUserId != tour.adminId && currentUserId.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                    onPressed: () => _showLeaveTourDialog(
                        context, ref, tour.id, tour.name, currentUserId),
                    tooltip: 'Leave Tour',
                  ),
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
                      onPressed: () {
                        final members = membersStream.value ?? [];
                        AddMemberDialog.show(
                          context,
                          tourId: tour.id,
                          inviterName: inviterName,
                          currentMembers: members,
                        );
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: const Text(
                        'Add Member (Username, Email, or Offline)',
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
                child: Builder(
                  builder: (context) {
                    // Watch refresh counter — bumped when an offline member is added via dialog
                    ref.watch(localMembersRefreshProvider);

                    final cachedMembers = ActiveTourCacheService.getCachedMembers(tour.id);

                    // Merge stream + cache so offline-queued members always appear.
                    // Stream is authoritative base; cached extras (offline-queued) are appended.
                    final streamMembers = membersStream.maybeWhen(
                      data: (m) => m,
                      orElse: () => <TourMemberModel>[],
                    );
                    final List<TourMemberModel> effectiveMembers;
                    if (streamMembers.isNotEmpty) {
                      final extra = cachedMembers
                          .where((c) => !streamMembers.any((s) => s.userId == c.userId))
                          .toList();
                      effectiveMembers = [...streamMembers, ...extra];
                    } else if (cachedMembers.isNotEmpty) {
                      effectiveMembers = cachedMembers;
                    } else {
                      // Deep fallback: resolve from offline queue names
                      final queuedNames = <String, String>{};
                      try {
                        for (final qm in ref.read(offlineTourQueueProvider).getQueuedMembersForTour(tour.id)) {
                          queuedNames[qm.userId] = qm.displayName;
                        }
                      } catch (_) {}

                      effectiveMembers = tour.memberIds.map((uid) {
                        final cached = UserCacheService.getUser(uid);
                        return TourMemberModel(
                          userId: uid,
                          displayName: cached?.displayName ??
                              queuedNames[uid] ??
                              (uid == currentUserId
                                  ? (user?.displayName ?? 'You')
                                  : (uid.startsWith('offline_') ? 'Offline Friend' : 'Member')),
                          username: cached?.username ?? '',
                          email: uid == currentUserId ? (user?.email ?? '') : '',
                          photoUrl: cached?.photoUrl ??
                              (uid == currentUserId ? user?.photoUrl : null),
                          role: tour.isAdmin(uid) ? 'admin' : 'member',
                          status: 'active',
                          joinedAt: tour.createdAt,
                          balance: 0.0,
                          isOffline: uid.startsWith('offline_'),
                        );
                      }).toList();
                    }

                    if (effectiveMembers.isEmpty && membersStream.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (effectiveMembers.isEmpty) {
                      return const Center(child: Text('No members yet'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: effectiveMembers.length,
                      itemBuilder: (context, i) {
                        final member = effectiveMembers[i];
                        final isCreator = member.userId == tour.adminId;
                        final isMemberAdmin = tour.isAdmin(member.userId);

                        return _MemberCard(
                          member: member,
                          isCreator: isCreator,
                          isMemberAdmin: isMemberAdmin,
                          isAdmin: isAdmin,
                          currentUserId: currentUserId,
                          currencySymbol: tour.currencySymbol,
                          onToggleAdmin: isAdmin && !isCreator && !member.isOffline
                              ? () => _toggleAdminRole(
                                  context, ref, tour.id, member, isMemberAdmin)
                              : null,
                          onReplaceWithOnline: isAdmin && member.isOffline
                              ? () => _showReplaceOfflineMemberDialog(
                                  context, ref, effectiveTourId, member, effectiveMembers)
                              : null,
                          onRename: isAdmin && member.isOffline
                              ? () => _showRenameOfflineMemberDialog(
                                  context, ref, effectiveTourId, member)
                              : null,
                          onRemove: isAdmin &&
                                  !isCreator &&
                                  member.userId != currentUserId
                              ? () =>
                                  _removeMember(context, ref, effectiveTourId, member)
                              : null,
                          onLeave: (currentUserId != tour.adminId &&
                                  member.userId == currentUserId &&
                                  !member.isLeft)
                              ? () => _showLeaveTourDialog(
                                  context, ref, tour.id, tour.name, currentUserId)
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
          bottomNavigationBar: TourBottomNavigationBar(
            tour: tour,
            isAdmin: isAdmin,
            currentUser: user,
            membersCount: membersStream.value?.length ?? tour.memberIds.length,
            currentIndex: 2,
            onToursTap: () => context.push('/tours'),
            onDashboardTap: () {
              ref.read(activeTourIdOverrideProvider.notifier).state = tour.id;
              ActiveTourCacheService.setActiveTourId(tour.id);
              context.go('/home');
            },
            onMembersTap: () {},
            onSettingsTap: isAdmin
                ? () => context.pushReplacement(
                    '/tour/settings?tourId=${tour.id}')
                : null,
          ),
        ),
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
      TourMemberModel member) async {
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
            '${member.displayName} has recorded contributions, expenses, or settlements in this tour.\n\nTo preserve mathematical integrity of tour balances, members with recorded spending or splits cannot be completely removed. If they are leaving the tour, their history remains intact.',
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
          'Remove mistakenly added member "${member.displayName}" from this tour?\n\nSince this member has no contributions or expenses, they will be completely removed from tour calculations, member lists, and the tour card.',
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
                await ref
                    .read(tourRepositoryProvider)
                    .removeMistakenMember(tourId: tourId, userId: member.userId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${member.displayName} removed from tour'),
                      backgroundColor: AppColors.positive,
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

  Future<void> _showLeaveTourDialog(
    BuildContext context,
    WidgetRef ref,
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
          context.go('/home');
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

  Future<void> _showReplaceOfflineMemberDialog(
    BuildContext context,
    WidgetRef ref,
    String tourId,
    TourMemberModel member,
    List<TourMemberModel> allMembers,
  ) async {
    final success = await ReplaceOfflineMemberDialog.show(
      context,
      tourId: tourId,
      offlineMember: member,
      allMembers: allMembers,
    );

    if (success == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.displayName} was successfully replaced and linked to their online account!',
          ),
          backgroundColor: AppColors.positive,
        ),
      );
    }
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
          ...requests.map((r) {
            final reqProfile = ref.watch(userProfileProvider(r.userId)).value;
            final reqCached = ref.watch(userBoxProvider(r.userId));
            final reqUsername = (reqProfile?.username.isNotEmpty == true)
                ? reqProfile!.username
                : (reqCached?.username.isNotEmpty == true
                    ? reqCached!.username
                    : '');
            final reqHandle = reqUsername.isNotEmpty
                ? '@$reqUsername'
                : (r.email.contains('@')
                    ? '@${r.email.split('@').first}'
                    : (r.email.isNotEmpty ? '@${r.email}' : ''));
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    MemberAvatar(
                      initials:
                          r.displayName.isNotEmpty ? r.displayName[0] : '?',
                      photoUrl: reqProfile?.photoUrl ?? r.photoUrl,
                      userId: r.userId,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reqProfile?.displayName.isNotEmpty == true
                                ? reqProfile!.displayName
                                : r.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            reqHandle,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
              );
            }),
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

class _MemberCard extends ConsumerWidget {
  final TourMemberModel member;
  final bool isCreator;
  final bool isMemberAdmin;
  final bool isAdmin;
  final String currentUserId;
  final String currencySymbol;
  final VoidCallback? onToggleAdmin;
  final VoidCallback? onReplaceWithOnline;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;
  final VoidCallback? onLeave;

  const _MemberCard({
    required this.member,
    required this.isCreator,
    required this.isMemberAdmin,
    required this.isAdmin,
    required this.currentUserId,
    required this.currencySymbol,
    this.onToggleAdmin,
    this.onReplaceWithOnline,
    this.onRename,
    this.onRemove,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCurrentUser = member.userId == currentUserId;

    // Resolve live profile info
    final liveProfile = !member.isOffline
        ? ref.watch(userProfileProvider(member.userId)).value
        : null;
    final cachedUser =
        !member.isOffline ? ref.watch(userBoxProvider(member.userId)) : null;

    final resolvedUsername = (liveProfile?.username.isNotEmpty == true)
        ? liveProfile!.username
        : (member.username.isNotEmpty
            ? member.username
            : (cachedUser?.username.isNotEmpty == true
                ? cachedUser!.username
                : ''));

    final resolvedDisplayName = (liveProfile?.displayName.isNotEmpty == true)
        ? liveProfile!.displayName
        : (member.displayName.isNotEmpty
            ? member.displayName
            : (cachedUser?.displayName.isNotEmpty == true
                ? cachedUser!.displayName
                : 'Member'));

    final resolvedPhotoUrl =
        liveProfile?.photoUrl ?? member.photoUrl ?? cachedUser?.photoUrl;

    final displayHandle = member.isOffline
        ? 'Offline Friend · Visible to all members'
        : (resolvedUsername.isNotEmpty
            ? '@$resolvedUsername'
            : (member.email.contains('@')
                ? '@${member.email.split('@').first}'
                : (member.email.isNotEmpty ? '@${member.email}' : '')));

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
              photoUrl: resolvedPhotoUrl,
              radius: 22,
              userId: member.userId,
              tourMember: member.copyWith(
                displayName: resolvedDisplayName,
                username: resolvedUsername,
              ),
              backgroundColor: member.isOffline
                  ? Colors.blueGrey.withValues(alpha: 0.2)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: member.userId == currentUserId
                    ? () {
                        HapticFeedback.lightImpact();
                        context.push('/profile');
                      }
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name on its own line — prevents badge chips from squeezing
                    // the Flexible Text to zero width.
                    Text(
                      resolvedDisplayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    // Badges wrap to new lines if needed — never crowd the name.
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (member.isOffline)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      Colors.blueGrey.withValues(alpha: 0.35)),
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
                        if (isAdmin &&
                            onReplaceWithOnline != null &&
                            member.isOffline)
                          InkWell(
                            onTap: onReplaceWithOnline,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.primaryTeal
                                        .withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_rounded,
                                      size: 11, color: AppColors.primaryTeal),
                                  SizedBox(width: 3),
                                  Text(
                                    'Link Online Friend',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primaryTeal,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (isCurrentUser)
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
                        if (isCreator)
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
                          )
                        else if (isMemberAdmin)
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
                        if (member.isLeft)
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
                    ),
                  const SizedBox(height: 2),
                  Text(
                    displayHandle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          member.isOffline ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
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
            if (isCurrentUser && !isCreator && !member.isLeft && onLeave != null) ...[
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.danger),
                tooltip: 'Leave Tour',
                onPressed: onLeave,
              ),
            ],
            if (isAdmin && !isCreator && !isCurrentUser) ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (val) {
                  if (val == 'role') {
                    onToggleAdmin?.call();
                  } else if (val == 'link_online') {
                    onReplaceWithOnline?.call();
                  } else if (val == 'rename') {
                    onRename?.call();
                  } else if (val == 'remove') {
                    onRemove?.call();
                  }
                },
                itemBuilder: (ctx) => [
                  if (!member.isOffline && !member.isLeft)
                    PopupMenuItem(
                      value: 'role',
                      child: Text(isMemberAdmin ? 'Revoke Admin' : 'Make Admin'),
                    ),
                  if (member.isOffline && !member.isLeft) ...[
                    const PopupMenuItem(
                      value: 'link_online',
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 18, color: AppColors.primaryTeal),
                          SizedBox(width: 8),
                          Text(
                            'Replace with Online Friend',
                            style: TextStyle(
                              color: AppColors.primaryTeal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Rename Offline Friend'),
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
                          member.isLeft
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
          ],
        ),
      ),
    );
  }
}
