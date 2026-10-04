import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/app_update_service.dart';

class WhatsNewDialog extends ConsumerWidget {
  final String? version;

  const WhatsNewDialog({
    super.key,
    this.version,
  });

  static bool _hasCheckedThisSession = false;

  static Future<void> checkAndShow(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;
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

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (ctx, anim, secAnim) => WhatsNewDialog(version: resolvedVersion),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  static List<({IconData icon, String title, String description})>
      get features => _features;

  static const List<({IconData icon, String title, String description})>
      _features = [
    (
      icon: Icons.calculate_rounded,
      title: 'In-App Expense Math Calculator',
      description:
          'Evaluate mathematical expressions with live results and instant calculation directly inside the expense amount field.',
    ),
    (
      icon: Icons.rounded_corner_rounded,
      title: 'Symmetric & Unified UI Buttons',
      description:
          'Standardized corner radius, elevation, and border stroke width across all screen actions and dialogs.',
    ),
    (
      icon: Icons.forum_rounded,
      title: 'Peer-to-Peer Chat & Reactions',
      description:
          'Coordinate with companions and react to messages in real time or offline nearby.',
    ),
    (
      icon: Icons.cloud_off_rounded,
      title: 'Pure Offline Host Mode',
      description:
          'Create tours and record expenses completely offline with automatic local caching.',
    ),
    (
      icon: Icons.verified_user_rounded,
      title: 'Settlement Deduplication',
      description:
          'Prevents duplicate settlements with automated guards and queue protection.',
    ),
    (
      icon: Icons.navigation_rounded,
      title: 'Unified Navigation Bar',
      description:
          'Seamless bottom navigation bar across all tour views, eliminating header clutter and duplicate back buttons.',
    ),
    (
      icon: Icons.dark_mode_rounded,
      title: 'Pure OLED Pitch Black Theme',
      description:
          'High-contrast true black mode optimized for battery savings and readability.',
    ),
  ];

  static IconData _iconForEmoji(String emoji) {
    if (emoji.contains('🧭') || emoji.contains('🗺️') || emoji.contains('📍')) {
      return Icons.navigation_rounded;
    }
    if (emoji.contains('📡') || emoji.contains('📶') || emoji.contains('🔵')) {
      return Icons.bluetooth_searching_rounded;
    }
    if (emoji.contains('💬') || emoji.contains('✨') || emoji.contains('❤️')) {
      return Icons.add_reaction_rounded;
    }
    if (emoji.contains('⚡') || emoji.contains('🛡️') || emoji.contains('✅')) {
      return Icons.verified_user_rounded;
    }
    if (emoji.contains('🎨') || emoji.contains('🖤') || emoji.contains('🌙')) {
      return Icons.dark_mode_rounded;
    }
    if (emoji.contains('🧾') || emoji.contains('💳')) {
      return Icons.receipt_long_rounded;
    }
    return Icons.auto_awesome_rounded;
  }

  static List<({IconData icon, String title, String description})>
      _parseReleaseNotes(String notes) {
    final lines = notes.split('\n');
    final items = <({IconData icon, String title, String description})>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!line.startsWith('-') && !line.startsWith('*')) continue;

      final match = RegExp(
              r'^[-*]\s*(?:([^\w\s]+)\s*)?\*\*(.*?)\*\*:\s*(.*)$')
          .firstMatch(line);
      if (match != null) {
        final emoji = match.group(1) ?? '✨';
        final title = match.group(2)!.trim();
        final desc = match.group(3)!.trim();
        items.add((
          icon: _iconForEmoji(emoji),
          title: title,
          description: desc,
        ));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final updateInfo = ref.watch(effectiveUpdateInfoProvider);
    final installedVersion =
        ref.watch(currentAppVersionProvider).value?.version;
    final targetVersion = (version != null && version!.isNotEmpty)
        ? version!
        : (installedVersion ?? '');

    List<({IconData icon, String title, String description})> activeFeatures =
        _features;

    // Only override with remote release notes if explicitly previewing a newer release
    if (updateInfo != null &&
        updateInfo.releaseNotes.isNotEmpty &&
        targetVersion.isNotEmpty &&
        AppUpdateService.isVersionNewer(
            updateInfo.latestVersion, targetVersion)) {
      final parsed = _parseReleaseNotes(updateInfo.releaseNotes);
      if (parsed.isNotEmpty) {
        activeFeatures = parsed;
      }
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    // Centered top title (identical to screenshot style)
                    Text(
                      'What\'s New',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.lightText,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final v = (version != null && version!.isNotEmpty)
                            ? version!
                            : (snapshot.data?.version ?? '');
                        if (v.isEmpty) return const SizedBox.shrink();
                        return Text(
                          'Version $v',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryTeal,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 48),

                    // Minimalist features list (bold title + 1-2 sentence description)
                    ...activeFeatures.asMap().entries.map((entry) {
                      final index = entry.key;
                      final feature = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                feature.icon,
                                size: 22,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feature.title,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : AppColors.lightText,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    feature.description,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 14,
                                      height: 1.42,
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
                      )
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: 60 * index),
                            duration: 350.ms,
                          )
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          );
                    }),
                  ],
                ),
              ),
            ),

            // Modern Pill Bottom Action Button (matching screenshot)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
