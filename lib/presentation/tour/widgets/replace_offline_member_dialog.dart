import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/tour_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/tour_repository.dart';
import '../../widgets/member_avatar.dart';

class ReplaceOfflineMemberDialog extends ConsumerStatefulWidget {
  final String tourId;
  final TourMemberModel offlineMember;
  final List<TourMemberModel> allMembers;

  const ReplaceOfflineMemberDialog({
    super.key,
    required this.tourId,
    required this.offlineMember,
    required this.allMembers,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String tourId,
    required TourMemberModel offlineMember,
    required List<TourMemberModel> allMembers,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReplaceOfflineMemberDialog(
        tourId: tourId,
        offlineMember: offlineMember,
        allMembers: allMembers,
      ),
    );
  }

  @override
  ConsumerState<ReplaceOfflineMemberDialog> createState() =>
      _ReplaceOfflineMemberDialogState();
}

class _ReplaceOfflineMemberDialogState
    extends ConsumerState<ReplaceOfflineMemberDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isSearching = false;
  String? _searchError;
  UserModel? _foundUser;

  // Selected online user to replace the offline member with
  String? _selectedOnlineUserId;
  String? _selectedOnlineUserName;
  String? _selectedOnlineUserPhotoUrl;
  String? _selectedOnlineUserEmail;

  bool _isProcessing = false;
  String? _processError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _searchError = null;
      _foundUser = null;
    });

    try {
      final user = await ref
          .read(tourRepositoryProvider)
          .findUserByUsernameOrEmail(query);

      if (!mounted) return;
      if (user == null) {
        setState(() {
          _isSearching = false;
          _searchError = 'No user found with username or email "$query"';
        });
      } else {
        setState(() {
          _isSearching = false;
          _foundUser = user;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed: $e';
      });
    }
  }

  void _selectUser({
    required String uid,
    required String displayName,
    String? photoUrl,
    String? email,
  }) {
    setState(() {
      _selectedOnlineUserId = uid;
      _selectedOnlineUserName = displayName;
      _selectedOnlineUserPhotoUrl = photoUrl;
      _selectedOnlineUserEmail = email;
      _processError = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedOnlineUserId = null;
      _selectedOnlineUserName = null;
      _selectedOnlineUserPhotoUrl = null;
      _selectedOnlineUserEmail = null;
      _processError = null;
    });
  }

  Future<void> _executeReplacement() async {
    if (_selectedOnlineUserId == null || _selectedOnlineUserName == null) return;

    setState(() {
      _isProcessing = true;
      _processError = null;
    });

    try {
      await ref.read(tourRepositoryProvider).replaceOfflineMemberWithOnlineUser(
            tourId: widget.tourId,
            offlineMemberId: widget.offlineMember.userId,
            onlineUserId: _selectedOnlineUserId!,
            onlineUserName: _selectedOnlineUserName!,
            onlineUserPhotoUrl: _selectedOnlineUserPhotoUrl,
            onlineUserEmail: _selectedOnlineUserEmail,
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _processError = 'Migration failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final onlineTourMembers = widget.allMembers
        .where((m) => !m.isOffline && m.userId != widget.offlineMember.userId)
        .toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: AppColors.primaryTeal,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Link Online Account',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Replace "${widget.offlineMember.displayName}"',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _selectedOnlineUserId != null
            ? _buildConfirmationView(isDark)
            : _buildSelectionView(onlineTourMembers, isDark),
      ),
      actions: _selectedOnlineUserId != null
          ? [
              TextButton(
                onPressed: _isProcessing ? null : _clearSelection,
                child: const Text('Back'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isProcessing ? null : _executeReplacement,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _isProcessing ? 'Linking...' : 'Confirm & Replace',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
    );
  }

  Widget _buildConfirmationView(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryTeal.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          MemberAvatar(
                            initials: widget.offlineMember.initials,
                            radius: 20,
                            backgroundColor:
                                Colors.blueGrey.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.offlineMember.displayName,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Offline Friend',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blueGrey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.primaryTeal,
                        size: 26,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          MemberAvatar(
                            initials: _selectedOnlineUserName!.isNotEmpty
                                ? _selectedOnlineUserName![0].toUpperCase()
                                : '?',
                            photoUrl: _selectedOnlineUserPhotoUrl,
                            radius: 20,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedOnlineUserName!,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Online Account',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primaryTeal,
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
          ),
          const SizedBox(height: 16),
          const Text(
            'What happens after linking:',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          _bulletPoint(
            icon: Icons.receipt_long_rounded,
            title: 'Expense Ledger Transferred',
            desc:
                'All expenses paid by "${widget.offlineMember.displayName}" are reassigned to "$_selectedOnlineUserName".',
          ),
          const SizedBox(height: 8),
          _bulletPoint(
            icon: Icons.pie_chart_rounded,
            title: 'Splits & Settlements Synced',
            desc:
                'Every split share and pending settlement balance will now belong to "$_selectedOnlineUserName".',
          ),
          const SizedBox(height: 8),
          _bulletPoint(
            icon: Icons.delete_sweep_rounded,
            title: 'Offline Profile Removed',
            desc:
                'The offline duplicate placeholder will be cleanly removed from the tour members list.',
          ),
          if (_processError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text(
                _processError!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bulletPoint({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primaryTeal),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionView(
      List<TourMemberModel> onlineTourMembers, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Connect this offline friend to their real TourSplit account so they can track everything on their own phone.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.primaryTeal,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            labelStyle: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            tabs: [
              Tab(text: 'Tour Members (${onlineTourMembers.length})'),
              const Tab(text: 'Search Online User'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTourMembersTab(onlineTourMembers, isDark),
              _buildSearchTab(isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTourMembersTab(
      List<TourMemberModel> onlineTourMembers, bool isDark) {
    if (onlineTourMembers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline_rounded,
                  size: 36,
                  color: isDark ? Colors.white38 : Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text(
                'No other online members in this tour.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Switch to "Search Online User" to find their account by username or email.',
                textAlign: TextAlign.center,
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
      );
    }

    return ListView.separated(
      itemCount: onlineTourMembers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final m = onlineTourMembers[i];
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: MemberAvatar(
            initials: m.initials,
            photoUrl: m.photoUrl,
            radius: 18,
          ),
          title: Text(
            m.displayName,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            m.email,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryTeal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(48, 30),
            ),
            onPressed: () => _selectUser(
              uid: m.userId,
              displayName: m.displayName,
              photoUrl: m.photoUrl,
              email: m.email,
            ),
            child: const Text(
              'Select',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchTab(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter username or email',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (_) => _handleSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(60, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSearching ? null : _handleSearch,
                child: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Find',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 12),
            Text(
              _searchError!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontFamily: 'Outfit',
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_foundUser != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primaryTeal.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  MemberAvatar(
                    initials: _foundUser!.initials,
                    photoUrl: _foundUser!.photoUrl,
                    radius: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _foundUser!.displayName,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _foundUser!.email,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: const Size(60, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _selectUser(
                      uid: _foundUser!.uid,
                      displayName: _foundUser!.displayName,
                      photoUrl: _foundUser!.photoUrl,
                      email: _foundUser!.email,
                    ),
                    child: const Text(
                      'Select',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
