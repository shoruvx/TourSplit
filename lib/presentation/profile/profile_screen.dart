import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/app_update_service.dart';
import '../widgets/member_avatar.dart';
import '../widgets/image_crop_dialog.dart';
import '../widgets/app_text_field.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/whats_new_dialog.dart';
import '../../data/services/user_cache_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../widgets/theme_switch_toggle.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/app_notification_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;
  bool _payoutAccountsExpanded = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(UserModel user) async {
    final name = _nameCtrl.text.trim();
    String username = _usernameCtrl.text.trim().toLowerCase();
    if (username.startsWith('@')) {
      username = username.substring(1).trim();
    }

    if (name.isEmpty) {
      showAppNotificationSheet(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'Missing Name',
        message: 'Name cannot be empty. Please enter your name.',
        primaryButtonText: 'Got It',
      );
      return;
    }

    if (username.isEmpty) {
      showAppNotificationSheet(
        context,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'Missing Username',
        message: 'Username cannot be empty. Please enter a valid username.',
        primaryButtonText: 'Got It',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(authServiceProvider).updateProfile(
            uid: user.uid,
            name: name,
            username: username,
            activeTourId: user.activeTourId,
          );

      ref.invalidate(userProfileProvider(user.uid));
      ref.invalidate(currentUserProvider);
      ref.invalidate(userBoxProvider(user.uid));
      if (user.activeTourId != null && user.activeTourId!.isNotEmpty) {
        ref.invalidate(tourMembersStreamProvider(user.activeTourId!));
      }

      if (mounted) {
        await showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Profile Updated!',
          message: 'Your profile changes have been saved successfully.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Update Failed',
          message: 'Failed to update profile: $e',
          primaryButtonText: 'Dismiss',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadPhoto(
      ImageSource source, UserModel user) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );
      if (picked == null) return;

      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;

      final croppedBytes = await ImageCropDialog.show(context, rawBytes);
      if (croppedBytes == null) return;

      setState(() => _isLoading = true);

      final downloadUrl = await ref
          .read(authServiceProvider)
          .uploadProfileImage(user.uid, croppedBytes, 'png');

      await ref.read(authServiceProvider).updateProfilePhoto(
            user.uid,
            downloadUrl,
            activeTourId: user.activeTourId,
          );

      if (mounted) {
        setState(() => _isLoading = false);
        await showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: 'Picture Updated',
          message: 'Your profile picture has been updated successfully.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Upload Failed',
          message: 'Failed to update picture: $e',
          primaryButtonText: 'Dismiss',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditProfileBottomSheet(BuildContext context, UserModel user) {
    final nameCtrl = TextEditingController(text: user.displayName);
    final usernameCtrl = TextEditingController(
      text: user.username.isNotEmpty ? user.username : user.email.split('@').first,
    );
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Profile Details',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: nameCtrl,
                      label: 'Full Name',
                      prefixIcon: Icons.person_outline,
                      textCapitalization: TextCapitalization.words,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Name cannot be empty';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: usernameCtrl,
                      label: 'Username',
                      prefixIcon: Icons.alternate_email_rounded,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Username cannot be empty';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          Navigator.pop(ctx);
                          _nameCtrl.text = nameCtrl.text;
                          _usernameCtrl.text = usernameCtrl.text;
                          await _saveProfile(user);
                        },
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
            title: const Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.primaryTeal, size: 22),
                SizedBox(width: 8),
                Text(
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: numberCtrl,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Account / Phone Number',
                      hintText: '01XXXXXXXXX or A/C No.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Note (Optional)',
                      hintText: 'e.g. Personal, Agent, Branch',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  final type = typeCtrl.text.trim();
                  final num = numberCtrl.text.trim();
                  final note = noteCtrl.text.trim();

                  if (type.isEmpty || num.isEmpty) {
                    showAppNotificationSheet(
                      ctx,
                      icon: Icons.info_outline_rounded,
                      iconColor: AppColors.warning,
                      title: 'Missing Information',
                      message: 'Please provide both payout type and account number.',
                      primaryButtonText: 'Got It',
                    );
                    return;
                  }

                  Navigator.pop(ctx);

                  final newAccount = PaymentAccount(
                    id: const Uuid().v4(),
                    type: type,
                    accountNumber: num,
                    note: note.isNotEmpty ? note : null,
                  );

                  final updated = [...user.paymentAccounts, newAccount];
                  try {
                    await ref
                        .read(authServiceProvider)
                        .updatePaymentAccounts(user.uid, updated);
                    if (mounted) {
                      await showAppNotificationSheet(
                        context,
                        icon: Icons.check_circle_outline_rounded,
                        iconColor: AppColors.positive,
                        title: 'Payout Account Added',
                        message: '$type account ($num) has been added to your profile.',
                        primaryButtonText: 'Done',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showAppNotificationSheet(
                        context,
                        icon: Icons.error_outline_rounded,
                        iconColor: AppColors.danger,
                        title: 'Failed to Save Account',
                        message: 'Could not save payout account: $e',
                        primaryButtonText: 'Dismiss',
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
    final confirmed = await showAppConfirmationSheet(
      context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.danger,
      title: 'Remove Account?',
      message: 'Are you sure you want to remove this payout method?',
      confirmText: 'Remove',
      confirmColor: AppColors.danger,
    );
    if (!confirmed) return;

    final updated =
        user.paymentAccounts.where((a) => a.id != accountId).toList();
    try {
      await ref
          .read(authServiceProvider)
          .updatePaymentAccounts(user.uid, updated);
      if (mounted) {
        await showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.warning,
          title: 'Account Removed',
          message: 'The payout method has been removed from your profile.',
          primaryButtonText: 'Done',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Delete Failed',
          message: 'Failed to delete account: $e',
          primaryButtonText: 'Dismiss',
        );
      }
    }
  }

  void _showAccountActionSheet(
      BuildContext context, UserModel user, PaymentAccount acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color badgeColor(String type) {
      final lower = type.toLowerCase();
      if (lower.contains('bkash')) return const Color(0xFFE2136E);
      if (lower.contains('nagad')) return const Color(0xFFF7941D);
      if (lower.contains('rocket')) return const Color(0xFF8C3494);
      if (lower.contains('bank')) return AppColors.primaryBlue;
      return AppColors.primaryTeal;
    }

    final color = badgeColor(acc.type);

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
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      acc.type.isNotEmpty ? acc.type[0].toUpperCase() : 'P',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.type,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          acc.accountNumber,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        if (acc.note != null && acc.note!.isNotEmpty)
                          Text(
                            acc.note!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.copy_rounded,
                      color: AppColors.primaryTeal, size: 20),
                ),
                title: const Text('Copy Account Number',
                    style: TextStyle(
                        fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: acc.accountNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${acc.type} number copied to clipboard!'),
                      backgroundColor: AppColors.positive,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 20),
                ),
                title: const Text('Remove Account',
                    style: TextStyle(
                        fontFamily: 'Outfit',
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePaymentAccount(user, acc.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePhotoBottomSheet(BuildContext context, UserModel user) {
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_circle_rounded,
                      color: Colors.redAccent, size: 22),
                ),
                title: const Text('Use Google Account Photo',
                    style: TextStyle(
                        fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                subtitle: const Text('Fetch directly from your Google profile',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  try {
                    final photoUrl = await ref
                        .read(authServiceProvider)
                        .getGoogleProfilePhotoUrl();
                    if (photoUrl != null && photoUrl.isNotEmpty) {
                      await ref.read(authServiceProvider).updateProfilePhoto(
                            user.uid,
                            photoUrl,
                            activeTourId: user.activeTourId,
                          );
                      if (mounted) {
                        setState(() => _isLoading = false);
                        await showAppNotificationSheet(
                          context,
                          icon: Icons.check_circle_outline_rounded,
                          iconColor: AppColors.positive,
                          title: 'Photo Updated',
                          message: 'Profile photo updated from Google successfully!',
                          primaryButtonText: 'Done',
                        );
                      }
                    } else {
                      if (mounted) {
                        showAppNotificationSheet(
                          context,
                          icon: Icons.info_outline_rounded,
                          iconColor: AppColors.warning,
                          title: 'No Photo Found',
                          message: 'No Google profile photo was found for your account.',
                          primaryButtonText: 'Got It',
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      showAppNotificationSheet(
                        context,
                        icon: Icons.error_outline_rounded,
                        iconColor: AppColors.danger,
                        title: 'Photo Fetch Failed',
                        message: 'Failed to retrieve Google photo: $e',
                        primaryButtonText: 'Dismiss',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
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

  void _showShareAppBottomSheet(BuildContext context) {
    const downloadUrl =
        'https://github.com/${AppConstants.githubRepo}/releases/latest';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAppNotificationSheet(
      context,
      title: 'Share TourSplit',
      message:
          'Scan or download TourSplit to track and split expenses together.',
      additionalContent: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: QrImageView(
              data: downloadUrl,
              version: QrVersions.auto,
              size: 155,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0F172A),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_rounded,
                    size: 16, color: AppColors.primaryTeal),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'github.com/${AppConstants.githubRepo}/releases/latest',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      primaryButtonText: 'Share App',
      onPrimaryPressed: () {
        Share.share(
          'Track and split tour expenses effortlessly with TourSplit!\n'
          'Download the latest release here: $downloadUrl',
        );
      },
      secondaryButtonText: 'Copy Link',
      onSecondaryPressed: () {
        Clipboard.setData(const ClipboardData(text: downloadUrl));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download link copied to clipboard!'),
            backgroundColor: AppColors.accent,
            duration: Duration(seconds: 2),
          ),
        );
      },
    );
  }

  Widget _buildHeroProfile(BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryTeal,
                  width: 3.0,
                ),
              ),
              child: MemberAvatar(
                initials: user.initials,
                photoUrl: user.photoUrl,
                userId: user.uid,
                radius: 46,
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: InkWell(
                onTap: () => _showChangePhotoBottomSheet(context, user),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ).animate().fadeIn().scale(),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => _showEditProfileBottomSheet(context, user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              user.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ).animate().fadeIn(delay: 100.ms),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showEditProfileBottomSheet(context, user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '@${user.username.isNotEmpty ? user.username : user.email.split('@').first}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryTeal,
              ),
            ),
          ).animate().fadeIn(delay: 150.ms),
        ),
      ],
    );
  }

  Widget _buildPayoutAccountsCard(BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accounts = user.paymentAccounts;

    Color badgeColor(String type) {
      final lower = type.toLowerCase();
      if (lower.contains('bkash')) return const Color(0xFFE2136E);
      if (lower.contains('nagad')) return const Color(0xFFF7941D);
      if (lower.contains('rocket')) return const Color(0xFF8C3494);
      if (lower.contains('bank')) return AppColors.primaryBlue;
      return AppColors.primaryTeal;
    }

    String getInitial(String type) {
      final lower = type.toLowerCase();
      if (lower.contains('bkash')) return 'b';
      if (lower.contains('nagad')) return 'N';
      if (lower.contains('rocket')) return 'R';
      if (lower.contains('bank')) return 'B';
      return type.isNotEmpty ? type[0].toUpperCase() : 'P';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.primaryTeal.withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _payoutAccountsExpanded = !_payoutAccountsExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: AppColors.primaryTeal,
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Payout Accounts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${accounts.length}',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryTeal,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                InkWell(
                  onTap: () => _showAddPaymentAccountDialog(context, user),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primaryTeal.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 15, color: AppColors.primaryTeal),
                        SizedBox(width: 3),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _payoutAccountsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: accounts.isEmpty
                  ? InkWell(
                      onTap: () => _showAddPaymentAccountDialog(context, user),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.primaryTeal.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppColors.primaryTeal.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline_rounded,
                                size: 18, color: AppColors.primaryTeal),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Add Payout Account (bKash, Nagad, etc.)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryTeal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...accounts.map((acc) {
                              final color = badgeColor(acc.type);
                              final initial = getInitial(acc.type);
                              return InkWell(
                                onTap: () => _showAccountActionSheet(
                                    context, user, acc),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurface
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder,
                                    ),
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth > 0
                                          ? constraints.maxWidth
                                          : double.infinity,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            '${acc.type}: ${acc.accountNumber}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
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
                        );
                      },
                    ),
            ),
            crossFadeState: _payoutAccountsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 180.ms);
  }

  Widget _buildSettingsCard(BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer(
      builder: (context, ref, _) {
        final packageInfoAsync = ref.watch(currentAppVersionProvider);
        final updateInfo = ref.watch(effectiveUpdateInfoProvider);
        final currentVer = packageInfoAsync.value?.version ?? '1.0.0';
        final hasUpdate = updateInfo != null &&
            AppUpdateService.isVersionNewer(
                updateInfo.latestVersion, currentVer);

        Widget buildRowTile({
          required Widget icon,
          required String title,
          String? subtitle,
          Widget? trailing,
          VoidCallback? onTap,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: isDark ? 0.14 : 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: icon,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        Widget buildDivider() {
          return Divider(
            height: 1,
            thickness: 0.8,
            indent: 70,
            endIndent: 18,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder
                  : AppColors.primaryTeal.withValues(alpha: 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // 1. Theme Switch
              buildRowTile(
                icon: const Icon(Icons.dark_mode_outlined,
                    size: 20, color: AppColors.primaryTeal),
                title: 'Theme',
                subtitle: 'Dark / Light mode',
                trailing: const ThemeSwitchToggle(height: 30, width: 54),
              ),
              buildDivider(),

              // 2. What's New
              buildRowTile(
                icon: const Icon(Icons.auto_awesome_rounded,
                    size: 20, color: AppColors.primaryTeal),
                title: 'What\'s New',
                subtitle: 'Latest features and changelog',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTeal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
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
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey, size: 20),
                  ],
                ),
                onTap: () => WhatsNewDialog.show(context, version: currentVer),
              ),
              buildDivider(),

              // 3. Share TourSplit
              buildRowTile(
                icon: const Icon(Icons.share_rounded,
                    size: 20, color: AppColors.primaryTeal),
                title: 'Share TourSplit',
                subtitle: 'Invite friends or download link',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Colors.grey, size: 20),
                onTap: () => _showShareAppBottomSheet(context),
              ),
              buildDivider(),

              // 4. Contact Support
              buildRowTile(
                icon: const Icon(Icons.mark_chat_unread_outlined,
                    size: 20, color: AppColors.primaryTeal),
                title: 'Contact Support',
                subtitle: 'Feedback & developer chat',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Colors.grey, size: 20),
                onTap: () => context.push('/profile/contact-us'),
              ),
              buildDivider(),

              // 5. App Updates
              buildRowTile(
                icon: Icon(
                  hasUpdate
                      ? Icons.system_update_alt_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 20,
                  color: hasUpdate ? AppColors.accent : AppColors.primaryTeal,
                ),
                title: 'App Updates',
                subtitle: hasUpdate
                    ? 'Version ${updateInfo.latestVersion} available!'
                    : 'TourSplit is up to date',
                trailing: hasUpdate
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'Update Available',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Up to date',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.grey, size: 20),
                        ],
                      ),
                onTap: () =>
                    AppUpdateService.checkForUpdatesInteractive(context, ref),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 240.ms);
      },
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          final confirm = await showAppConfirmationSheet(
            context,
            icon: Icons.logout_rounded,
            iconColor: AppColors.danger,
            title: 'Sign Out?',
            message: 'You will be returned to the login screen.',
            confirmText: 'Sign Out',
            confirmColor: AppColors.danger,
          );
          if (confirm == true) {
            await ref.read(authServiceProvider).signOut();
            if (context.mounted) context.go('/login');
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: BorderSide(
            color: AppColors.danger.withValues(alpha: 0.6),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (user) {
        if (user == null) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final toursStream = ref.watch(userToursStreamProvider(user.uid));
        final activeCount =
            toursStream.value?.where((t) => t.isActive).length ?? 0;

        if (!_initialized) {
          _nameCtrl.text = user.displayName;
          _usernameCtrl.text = user.username.isNotEmpty
              ? user.username
              : user.email.split('@').first;
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
                automaticallyImplyLeading: false,
                toolbarHeight: 64,
                titleSpacing: 20,
                title: const Text(
                  'Profile',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: AppColors.primaryTeal,
                    height: 1.1,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.mode_edit_outline_rounded, size: 22),
                    tooltip: 'Edit Profile',
                    onPressed: () => _showEditProfileBottomSheet(context, user),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                child: Column(
                  children: [
                    _buildHeroProfile(context, user),
                    const SizedBox(height: 24),
                    _buildPayoutAccountsCard(context, user),
                    const SizedBox(height: 20),
                    _buildSettingsCard(context, user),
                    const SizedBox(height: 28),
                    _buildSignOutButton(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              bottomNavigationBar: HomeBottomNavigationBar(
                currentIndex: 2,
                activeToursCount: activeCount,
                currentUser: user,
                onHomeTap: () async {
                  ref.read(activeTourIdOverrideProvider.notifier).state =
                      kNoActiveTourId;
                  await ActiveTourCacheService.clearActiveTourId();
                  if (context.mounted) {
                    context.go('/home');
                  }
                },
                onToursTap: () => context.push('/tours'),
                onProfileTap: () {},
              ),
            ),
          ),
        );
      },
    );
  }
}
