import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
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

  void _showPublishUpdateDialog(BuildContext context) {
    final versionCtrl = TextEditingController(text: '1.1.0');
    final buildCtrl = TextEditingController(text: '2');
    final notesCtrl = TextEditingController(
      text:
          'TourSplit update: Split the costs, keep the memories! Brand new emblem logo and performance updates.',
    );
    final urlCtrl = TextEditingController(
      text: 'https://github.com/shoruvx/TourSplit/releases',
    );
    bool forceUpdate = false;

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
                              'All users will be notified to update',
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
                      label: 'APK Download URL / Release Link',
                      hint: 'https://...',
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
                          await AppUpdateService.publishUpdate(
                            latestVersion: versionCtrl.text.trim(),
                            buildNumber:
                                int.tryParse(buildCtrl.text.trim()) ?? 1,
                            releaseNotes: notesCtrl.text.trim(),
                            apkUrl: urlCtrl.text.trim(),
                            forceUpdate: forceUpdate,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Published v${versionCtrl.text.trim()}! Users will receive update prompt 🎉'),
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
                    child: MemberAvatar(
                      initials: user.initials,
                      photoUrl: user.photoUrl,
                      radius: 48,
                    ).animate().fadeIn().scale(),
                  ),
                  const SizedBox(height: 16),
                  Text(user.displayName,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700))
                      .animate()
                      .fadeIn(delay: 100.ms),
                  Text('@${user.username}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.primaryBlue,
                      )).animate().fadeIn(delay: 150.ms),
                  Text(user.email, style: theme.textTheme.bodySmall)
                      .animate()
                      .fadeIn(delay: 180.ms),
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
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Profile updated!'),
                              backgroundColor: AppColors.accent),
                        );
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save Changes'),
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
                          ref.watch(appUpdateInfoStreamProvider).valueOrNull;
                      final currentVer =
                          packageInfoAsync.valueOrNull?.version ?? '1.0.0';
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
