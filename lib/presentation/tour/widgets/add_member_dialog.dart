import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/tour_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/tour_repository.dart';
import '../../../data/services/offline_tour_queue_service.dart';
import '../../home/home_screen.dart' show localMembersRefreshProvider;
import '../../widgets/member_avatar.dart';

class AddMemberDialog extends ConsumerStatefulWidget {
  final String tourId;
  final String inviterName;
  final List<TourMemberModel> currentMembers;

  const AddMemberDialog({
    super.key,
    required this.tourId,
    required this.inviterName,
    required this.currentMembers,
  });

  static Future<void> show(
    BuildContext context, {
    required String tourId,
    required String inviterName,
    required List<TourMemberModel> currentMembers,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AddMemberDialog(
        tourId: tourId,
        inviterName: inviterName,
        currentMembers: currentMembers,
      ),
    );
  }

  @override
  ConsumerState<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<AddMemberDialog> {
  int _selectedTab = 0; // 0: Online User, 1: Offline Friend

  final _onlineInputCtrl = TextEditingController();
  final _offlineNameCtrl = TextEditingController();
  final _offlineFormKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isSearching = false;
  bool _isOffline = false;
  String? _onlineError;
  UserModel? _foundUser;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = result.every((r) => r == ConnectivityResult.none);
        // Auto-switch to offline tab when offline
        if (_isOffline) _selectedTab = 1;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _onlineInputCtrl.dispose();
    _offlineNameCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String rawQuery) {
    _debounceTimer?.cancel();
    final query = rawQuery.trim().replaceAll(RegExp(r'^@'), '');
    if (query.isEmpty) {
      setState(() {
        _foundUser = null;
        _onlineError = null;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final user = await ref.read(tourRepositoryProvider).findUserByUsernameOrEmail(query);
        if (!mounted) return;
        setState(() {
          _isSearching = false;
          _foundUser = user;
          if (user != null) {
            final isAlreadyMember = widget.currentMembers.any((m) => m.userId == user.uid);
            if (isAlreadyMember) {
              _onlineError = '${user.displayName} is already a member of this tour.';
            } else {
              _onlineError = null;
            }
          }
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _submitOnlineUser() async {
    String query = _onlineInputCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _onlineError = 'Please enter a username or email address.');
      return;
    }

    if (query.startsWith('@')) {
      query = query.substring(1).trim();
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _onlineError = null;
    });

    try {
      final user = await ref
          .read(tourRepositoryProvider)
          .findUserByUsernameOrEmail(query);

      if (!mounted) return;

      if (user != null) {
        final isAlreadyMember =
            widget.currentMembers.any((m) => m.userId == user.uid);
        if (isAlreadyMember) {
          setState(() {
            _isSubmitting = false;
            _foundUser = user;
            _onlineError = '${user.displayName} is already a member of this tour.';
          });
          return;
        }

        // Add user directly to tour
        await ref.read(tourRepositoryProvider).addMemberToTour(
              tourId: widget.tourId,
              user: user,
            );

        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.displayName} added to the tour!'),
            backgroundColor: AppColors.positive,
          ),
        );
      } else {
        // Not found by username or email
        if (query.contains('@')) {
          // Send email invitation
          await ref.read(tourRepositoryProvider).inviteMemberByEmail(
                tourId: widget.tourId,
                email: query,
                inviterName: widget.inviterName,
              );

          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invitation sent to $query!'),
              backgroundColor: AppColors.positive,
            ),
          );
        } else {
          setState(() {
            _isSubmitting = false;
            _foundUser = null;
            _onlineError =
                'No user found with username "@$query". If they haven\'t joined yet, enter their email address to send an invitation.';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _onlineError = 'Failed to add member: $e';
      });
    }
  }

  Future<void> _addOfflineFriend() async {
    if (_offlineFormKey.currentState?.validate() != true) return;
    final name = _offlineNameCtrl.text.trim();

    setState(() => _isSubmitting = true);
    HapticFeedback.lightImpact();

    try {
      if (_isOffline || widget.tourId.startsWith('local_')) {
        // ── Offline path: queue locally ───────────────────────────────
        final queueService = ref.read(offlineTourQueueProvider);
        await queueService.addOfflineMemberLocally(
          tourId: widget.tourId,
          name: name,
        );
        // Trigger a rebuild of providers and UI so the new member shows up immediately
        ref.read(localMembersRefreshProvider.notifier).bump();
        ref.invalidate(tourMembersStreamProvider(widget.tourId));
        ref.invalidate(tourStreamProvider(widget.tourId));
      } else {
        // ── Online path: write to Firestore directly ─────────────────
        await ref.read(tourRepositoryProvider).addOfflineMember(
          tourId: widget.tourId,
          name: name,
        );
        ref.invalidate(tourMembersStreamProvider(widget.tourId));
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isOffline
                ? 'Offline friend "$name" saved — will sync when connected'
                : 'Offline friend "$name" added to the tour!',
          ),
          backgroundColor: _isOffline ? AppColors.warning : AppColors.positive,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add offline friend: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.primaryTeal,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add Member',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Segmented Tab Switcher
              Container(
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: _isOffline ? 'Not available offline' : '',
                        child: InkWell(
                          onTap: _isOffline
                              ? null // Disabled when offline
                              : () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _selectedTab = 0;
                                    _onlineError = null;
                                  });
                                },
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedTab == 0 && !_isOffline
                                  ? AppColors.primaryTeal
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Online Friend',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: _isOffline
                                        ? (isDark
                                            ? AppColors.darkTextSecondary.withValues(alpha: 0.4)
                                            : AppColors.lightTextSecondary.withValues(alpha: 0.4))
                                        : (_selectedTab == 0
                                            ? Colors.white
                                            : (isDark
                                                ? AppColors.darkTextSecondary
                                                : AppColors.lightTextSecondary)),
                                  ),
                                ),
                                if (_isOffline) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    size: 12,
                                    color: isDark
                                        ? AppColors.darkTextSecondary.withValues(alpha: 0.4)
                                        : AppColors.lightTextSecondary.withValues(alpha: 0.4),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedTab = 1;
                            _onlineError = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? AppColors.primaryTeal
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            'Offline Friend',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _selectedTab == 1
                                  ? Colors.white
                                  : (isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Tab Content
              if (_selectedTab == 0)
                _buildOnlineTabContent(isDark)
              else
                _buildOfflineTabContent(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineTabContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter a unique @username or registered email to add an existing user or invite someone new.',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 12.5,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _onlineInputCtrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitOnlineUser(),
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Username or Email',
            hintText: 'e.g. @rahim or rahim@gmail.com',
            hintStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_onlineInputCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _onlineInputCtrl.clear();
                          setState(() {
                            _foundUser = null;
                            _onlineError = null;
                            _isSearching = false;
                          });
                        },
                      )
                    : null),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (_onlineError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _onlineError!,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_foundUser != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primaryTeal.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                MemberAvatar(
                  initials: _foundUser!.initials,
                  photoUrl: _foundUser!.photoUrl,
                  userId: _foundUser!.uid,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _foundUser!.displayName,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.positive.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Found ✓',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.positive,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _foundUser!.username.isNotEmpty
                            ? '@${_foundUser!.username}'
                            : _foundUser!.email,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                      if (_foundUser!.username.isNotEmpty &&
                          _foundUser!.email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _foundUser!.email,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11.5,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submitOnlineUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(
              _isSubmitting ? 'Adding...' : 'Add to Tour',
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineTabContent(bool isDark) {
    return Form(
      key: _offlineFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a companion using only their name. No email, device, or app installation needed. You can track expenses & splits for them.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12.5,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _offlineNameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _addOfflineFriend(),
            decoration: InputDecoration(
              labelText: 'Friend\'s Name',
              hintText: 'e.g. Alex, Rahim, John',
              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _addOfflineFriend,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Adding...' : 'Add Friend to Tour',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
