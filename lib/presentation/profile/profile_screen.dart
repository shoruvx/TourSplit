import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/app_update_service.dart';
import '../widgets/member_avatar.dart';
import '../widgets/app_text_field.dart';
import '../widgets/loading_overlay.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;
  bool _isAccountsExpanded = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(UserModel user) async {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();

    if (first.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First name cannot be empty'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(authServiceProvider).updateProfile(
            uid: user.uid,
            firstName: first,
            lastName: last,
            activeTourId: user.activeTourId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully! 🎉'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto(
      ImageSource source, UserModel user) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 75,
      );
      if (picked == null) return;

      setState(() => _isLoading = true);
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final safeExt =
          (ext == 'png' || ext == 'jpg' || ext == 'jpeg') ? ext : 'jpg';

      final downloadUrl = await ref
          .read(authServiceProvider)
          .uploadProfileImage(user.uid, bytes, safeExt);

      await ref.read(authServiceProvider).updateProfilePhoto(
            user.uid,
            downloadUrl,
            activeTourId: user.activeTourId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully! ✨'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update picture: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddPaymentAccountDialog(BuildContext context, UserModel user,
      {String initialType = 'bKash'}) {
    String selectedType = initialType;
    final typeCtrl = TextEditingController(
        text: initialType == 'Other' ? '' : initialType);
    final numberCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final quickTypes = ['bKash', 'Nagad', 'Rocket', 'Bank', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.dialog),
            ),
            title: Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.primaryTeal, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Add Payout Method',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select or write payment method:',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickTypes.map((t) {
                      final isSelected = selectedType == t;
                      return ChoiceChip(
                        label: Text(t,
                            style: const TextStyle(
                                fontFamily: 'Outfit', fontSize: 12)),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              selectedType = t;
                              if (t != 'Other') {
                                typeCtrl.text = t;
                              } else {
                                typeCtrl.clear();
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Account / Provider Type',
                      hintText: 'e.g. bKash, Nagad, City Bank',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Phone or Account Number *',
                      hintText: 'e.g. 017XXXXXXXX or A/C 1234...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Optional Note / Details',
                      hintText: 'e.g. Personal, Agent, or Branch',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      isDense: true,
                    ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                onPressed: () async {
                  final numVal = numberCtrl.text.trim();
                  final typeVal = typeCtrl.text.trim();
                  if (numVal.isEmpty || typeVal.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter account type and number.'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                    return;
                  }

                  final newAcc = PaymentAccount(
                    id: const Uuid().v4(),
                    type: typeVal,
                    accountNumber: numVal,
                    note: noteCtrl.text.trim().isNotEmpty
                        ? noteCtrl.text.trim()
                        : null,
                  );

                  final updated = [...user.paymentAccounts, newAcc];
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);

                  try {
                    await ref
                        .read(authServiceProvider)
                        .updatePaymentAccounts(user.uid, updated);
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Receiving account added! ✨'),
                          backgroundColor: AppColors.positive,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Failed to save account: $e'),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Add Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePaymentAccount(UserModel user, String accountId) async {
    final updated =
        user.paymentAccounts.where((a) => a.id != accountId).toList();
    try {
      await ref
          .read(authServiceProvider)
          .updatePaymentAccounts(user.uid, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account removed.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Widget _buildQuickAddPill({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentAccountsSection(
      BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color badgeColor(String type) {
      final lower = type.toLowerCase();
      if (lower.contains('bkash')) return const Color(0xFFE2136E);
      if (lower.contains('nagad')) return const Color(0xFFF7941D);
      if (lower.contains('rocket')) return const Color(0xFF8C3494);
      if (lower.contains('bank')) return AppColors.primaryBlue;
      return AppColors.primaryTeal;
    }

    final hasAccounts = user.paymentAccounts.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _isAccountsExpanded = !_isAccountsExpanded);
            },
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      size: 18, color: AppColors.primaryTeal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Payout Methods',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasAccounts) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        '${user.paymentAccounts.length}',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded,
                        color: AppColors.primaryTeal, size: 19),
                    tooltip: 'Add Payout Method',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () =>
                        _showAddPaymentAccountDialog(context, user),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isAccountsExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isAccountsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                if (!hasAccounts) ...[
                  Text(
                    'Tap a provider to add your account for 1-tap settlement pay:',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickAddPill(
                        label: '+ bKash',
                        color: const Color(0xFFE2136E),
                        onTap: () => _showAddPaymentAccountDialog(context, user,
                            initialType: 'bKash'),
                      ),
                      _buildQuickAddPill(
                        label: '+ Nagad',
                        color: const Color(0xFFF7941D),
                        onTap: () => _showAddPaymentAccountDialog(context, user,
                            initialType: 'Nagad'),
                      ),
                      _buildQuickAddPill(
                        label: '+ Rocket',
                        color: const Color(0xFF8C3494),
                        onTap: () => _showAddPaymentAccountDialog(context, user,
                            initialType: 'Rocket'),
                      ),
                      _buildQuickAddPill(
                        label: '+ Bank',
                        color: AppColors.primaryBlue,
                        onTap: () => _showAddPaymentAccountDialog(context, user,
                            initialType: 'Bank'),
                      ),
                    ],
                  ),
                ] else ...[
                  ...user.paymentAccounts.map((acc) {
                    final badgeCol = badgeColor(acc.type);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Clipboard.setData(
                              ClipboardData(text: acc.accountNumber));
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: AppColors.primaryTeal, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Copied ${acc.accountNumber}',
                                    style: const TextStyle(fontFamily: 'Outfit'),
                                  ),
                                ],
                              ),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBg.withValues(alpha: 0.5)
                                : const Color(0xFFF8FAFC),
                            borderRadius:
                                BorderRadius.circular(AppRadius.input),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeCol.withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.chip),
                                  border: Border.all(
                                      color: badgeCol.withValues(alpha: 0.4)),
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
                                        letterSpacing: 0.3,
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
                              IconButton(
                                icon: const Icon(Icons.copy_rounded,
                                    size: 16, color: Colors.grey),
                                tooltip: 'Copy',
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  Clipboard.setData(
                                      ClipboardData(text: acc.accountNumber));
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded,
                                              color: AppColors.primaryTeal,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Copied ${acc.accountNumber}',
                                            style: const TextStyle(
                                                fontFamily: 'Outfit'),
                                          ),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.danger),
                                tooltip: 'Remove',
                                onPressed: () =>
                                    _deletePaymentAccount(user, acc.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showAddPaymentAccountDialog(context, user),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Another Account',
                          style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryTeal,
                        side: BorderSide(
                          color: AppColors.primaryTeal.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        minimumSize: const Size(0, 42),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showChangePhotoBottomSheet(BuildContext context, UserModel user) {
    final presetAvatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=200&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&auto=format&fit=crop&q=80',
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profile Photo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Outfit',
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: AppColors.primaryTeal, size: 22),
                ),
                title: const Text('Choose from Gallery',
                    style: TextStyle(
                        fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.gallery, user);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primaryTeal, size: 22),
                ),
                title: const Text('Take a Photo',
                    style: TextStyle(
                        fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.camera, user);
                },
              ),
              const SizedBox(height: 10),
              const Text('Or Pick a Travel Avatar:',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 10),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: presetAvatars.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final avatarUrl = presetAvatars[i];
                    return InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);
                        try {
                          await ref
                              .read(authServiceProvider)
                              .updateProfilePhoto(
                                user.uid,
                                avatarUrl,
                                activeTourId: user.activeTourId,
                              );
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      borderRadius: BorderRadius.circular(27),
                      child: CircleAvatar(
                        radius: 25,
                        backgroundImage: NetworkImage(avatarUrl),
                      ),
                    );
                  },
                ),
              ),
              if (user.photoUrl != null && user.photoUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger, size: 22),
                  ),
                  title: const Text('Remove Photo',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    try {
                      await ref
                          .read(authServiceProvider)
                          .updateProfilePhoto(user.uid, null,
                              activeTourId: user.activeTourId);
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPublishUpdateDialog(BuildContext context) {
    final versionCtrl = TextEditingController(text: '1.2.0');
    final buildCtrl = TextEditingController(text: '11');
    final notesCtrl = TextEditingController(
      text:
          'TourSplit update: Split the costs, keep the memories! Math expression calculations, settlement fixes, offline-online linking, profile avatar updates, and performance polish.',
    );
    final urlCtrl = TextEditingController(
      text:
          'https://github.com/${AppConstants.githubRepo}/releases/download/v1.2.0/TourSplit-v1.2.0.apk',
    );
    bool forceUpdate = false;
    bool autoDownload = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.rocket_launch_rounded,
                              color: AppColors.primaryTeal),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Release App Update 🚀',
                              style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'All users will automatically receive update',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: versionCtrl,
                            label: 'Version (e.g. 1.1.0)',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            controller: buildCtrl,
                            label: 'Build # (e.g. 2)',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: urlCtrl,
                      label: 'Direct APK Download URL',
                      hint: 'https://github.com/.../TourSplit.apk',
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: notesCtrl,
                      label: "What's New (Release Notes)",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Download & Prompt Install',
                          style: TextStyle(fontFamily: 'Outfit', fontSize: 14)),
                      subtitle: const Text(
                          'Background downloads APK & prompts install automatically',
                          style: TextStyle(fontSize: 12)),
                      value: autoDownload,
                      onChanged: (v) => setModalState(() => autoDownload = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mandatory / Force Update',
                          style: TextStyle(fontFamily: 'Outfit', fontSize: 14)),
                      subtitle: const Text(
                          'Users must update before continuing',
                          style: TextStyle(fontSize: 12)),
                      value: forceUpdate,
                      onChanged: (v) => setModalState(() => forceUpdate = v),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(ctx);
                          final ver = versionCtrl.text.trim();
                          String finalUrl = urlCtrl.text.trim();
                          if (finalUrl.isEmpty ||
                              !finalUrl.toLowerCase().endsWith('.apk')) {
                            finalUrl =
                                'https://github.com/${AppConstants.githubRepo}/releases/download/v$ver/TourSplit-v$ver.apk';
                          }

                          await AppUpdateService.publishUpdate(
                            latestVersion: ver,
                            buildNumber:
                                int.tryParse(buildCtrl.text.trim()) ?? 1,
                            releaseNotes: notesCtrl.text.trim(),
                            apkUrl: finalUrl,
                            forceUpdate: forceUpdate,
                            autoDownload: autoDownload,
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Published v$ver! All devices will receive update automatically 🚀'),
                                backgroundColor: AppColors.positive,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                        label: const Text(
                          'Publish Update to All Users',
                          style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (user) {
        if (user == null) return const Scaffold();

        if (!_initialized) {
          _firstNameCtrl.text = user.firstName;
          _lastNameCtrl.text = user.lastName;
          _initialized = true;
        }

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
          child: LoadingOverlay(
            isLoading: _isLoading,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Profile'),
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
              ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  AppColors.primaryTeal.withValues(alpha: 0.4),
                              width: 2.5,
                            ),
                          ),
                          child: MemberAvatar(
                            initials: user.initials,
                            photoUrl: user.photoUrl,
                            radius: 48,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () =>
                                _showChangePhotoBottomSheet(context, user),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn().scale(),
                  ),
                  const SizedBox(height: 16),
                  Text(user.displayName,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700))
                      .animate()
                      .fadeIn(delay: 100.ms),
                  const SizedBox(height: 4),
                  Text(user.email, style: theme.textTheme.bodySmall)
                      .animate()
                      .fadeIn(delay: 150.ms),
                  const SizedBox(height: 12),
                  _buildPaymentAccountsSection(context, user)
                      .animate()
                      .fadeIn(delay: 180.ms),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _firstNameCtrl,
                    label: 'First Name',
                    prefixIcon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _lastNameCtrl,
                    label: 'Last Name',
                    textCapitalization: TextCapitalization.words,
                  ).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isLoading ? null : () => _saveProfile(user),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Consumer(
                    builder: (context, ref, _) {
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final packageInfoAsync =
                          ref.watch(currentAppVersionProvider);
                      final updateInfo =
                          ref.watch(effectiveUpdateInfoProvider);
                      final currentVer =
                          packageInfoAsync.value?.version ?? '1.0.0';
                      final hasUpdate = updateInfo != null &&
                          AppUpdateService.isVersionNewer(
                              updateInfo.latestVersion, currentVer);

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF131D2E)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasUpdate
                                ? AppColors.primaryTeal
                                : (isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0)),
                            width: hasUpdate ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 38,
                                    height: 38,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'TourSplit',
                                            style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryTeal
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'v$currentVer',
                                              style: const TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primaryTeal,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Split the costs, keep the memories.',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => AppUpdateService
                                        .checkForUpdatesInteractive(
                                            context, ref),
                                    icon: Icon(
                                      hasUpdate
                                          ? Icons.system_update_alt_rounded
                                          : Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: hasUpdate
                                          ? AppColors.primaryTeal
                                          : Colors.grey,
                                    ),
                                    label: Text(
                                      hasUpdate
                                          ? 'Update Available!'
                                          : 'Check for Updates',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: hasUpdate
                                            ? AppColors.primaryTeal
                                            : null,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: hasUpdate
                                            ? AppColors.primaryTeal
                                            : Colors.grey.shade400,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () =>
                                      _showPublishUpdateDialog(context),
                                  icon: const Icon(Icons.cloud_upload_outlined,
                                      color: AppColors.primaryTeal),
                                  tooltip: 'Publish New Release',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Sign Out?'),
                            content: const Text(
                                'You will be returned to the login screen.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.danger),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Sign Out')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(authServiceProvider).signOut();
                          if (context.mounted) context.go('/login');
                        }
                      },
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.danger),
                      label: const Text('Sign Out',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ).animate().fadeIn(delay: 350.ms),
                ],
              ),
            ),
          ),
        ),
      );
      },
    );
  }
}
