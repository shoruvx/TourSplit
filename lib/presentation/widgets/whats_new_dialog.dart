import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/app_update_service.dart';

class WhatsNewDialog extends StatelessWidget {
  final String? version;

  const WhatsNewDialog({
    super.key,
    this.version,
  });

  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final box = await Hive.openBox('app_preferences');
      final lastSeenVersion = box.get('last_seen_whats_new_version') as String?;

      if (lastSeenVersion == null) {
        // First install: record current version so we don't display What's New on initial onboarding
        await box.put('last_seen_whats_new_version', currentVersion);
        return;
      }

      if (AppUpdateService.isVersionNewer(currentVersion, lastSeenVersion) &&
          context.mounted) {
        await box.put('last_seen_whats_new_version', currentVersion);
        if (context.mounted) {
          show(context, version: currentVersion);
        }
      }
    } catch (e) {
      debugPrint('[WHATS_NEW] Error checking what\'s new dialog: $e');
    }
  }

  static Future<void> show(BuildContext context, {String? version}) async {
    String? resolvedVersion = version;
    if (resolvedVersion == null || resolvedVersion.isEmpty) {
      try {
        final info = await PackageInfo.fromPlatform();
        resolvedVersion = info.version;
      } catch (_) {}
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => WhatsNewDialog(version: resolvedVersion),
    );
  }

  static const List<({IconData icon, String title, String description})>
      _features = [
    (
      icon: Icons.account_circle_rounded,
      title: 'Member Profile Hub',
      description:
          'Tap any member avatar or name anywhere in the app to view their profile, role, contact info, and tour activity.',
    ),
    (
      icon: Icons.flash_on_rounded,
      title: 'Offline Auto-Settlement',
      description:
          'Settlements with offline companions now resolve automatically without requiring approval from the offline friend.',
    ),
    (
      icon: Icons.layers_rounded,
      title: '3D Teal UI & System Theme',
      description:
          'Smooth 3D elevation cards with sleek teal borders, white-bordered buttons, and adaptive system default theme.',
    ),
    (
      icon: Icons.pie_chart_outline_rounded,
      title: 'Your Spending Breakdown',
      description:
          'Tours and summary cards now display your exact personal spending share rather than a generic per-person average.',
    ),
    (
      icon: Icons.mark_email_unread_rounded,
      title: 'Contact Us & Suggestion Portal',
      description:
          'Send feature ideas, feedback, and bug reports directly to Constant Time Labs from the Profile screen.',
    ),
    (
      icon: Icons.system_update_rounded,
      title: 'Over-The-Air Push Updates',
      description:
          'Stay up-to-date with background push alerts via Firebase Cloud Messaging and 1-tap seamless in-app APK installation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final v = (version != null && version!.isNotEmpty)
                            ? version!
                            : (snapshot.data?.version ?? '');
                        final label = v.isNotEmpty
                            ? 'What\'s New in v$v'
                            : 'What\'s New';
                        return Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryTeal,
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Fresh Features & Refinements',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Here is what has improved in this update of TourSplit.',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              // Feature list
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: _features.map((feature) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTeal
                                    .withValues(alpha: isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                feature.icon,
                                size: 18,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feature.title,
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    feature.description,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryTeal,
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    elevation: 1,
                  ),
                  child: const Text(
                    'Got it, Continue',
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
  }
}
