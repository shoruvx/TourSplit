import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';

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
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
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
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primaryBlue, size: 22),
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
                            ScaffoldMessenger.of(context).showSnackBar(
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
                  const SizedBox(height: 32),
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
