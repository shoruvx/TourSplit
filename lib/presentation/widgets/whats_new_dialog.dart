import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/app_update_service.dart';

class WhatsNewDialog extends ConsumerWidget {
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

  static List<({IconData icon, String title, String description})>
      get features => _features;

  static const List<({IconData icon, String title, String description})>
      _features = [
    (
      icon: Icons.forum_rounded,
      title: 'Hybrid Offline & Cloud Tour Chat',
      description:
          'Coordinate with companions in real-time over cloud sync, or chat completely offline via automatic peer-to-peer Bluetooth and Wi-Fi mesh.',
    ),
    (
      icon: Icons.reply_rounded,
      title: 'Quote Replies & Member Mentions',
      description:
          'Long-press or swipe any message to reply with quote snippets, and tag tour companions with instant @mention autocomplete chips.',
    ),
    (
      icon: Icons.bluetooth_audio_rounded,
      title: 'Seamless Android 7+ Compatibility',
      description:
          'Zero-setup silent Bluetooth activation on older Android 7.0+ devices with intelligent permission adapters and zero radio lockups.',
    ),
    (
      icon: Icons.auto_delete_rounded,
      title: '7-Day Inactivity Auto-Pruning',
      description:
          'Old tour chats are automatically purged after 7 days of inactivity to keep your device storage light and protect free-tier cloud limits.',
    ),
    (
      icon: Icons.delete_sweep_rounded,
      title: 'Telegram-Style Complete Message Erasing',
      description:
          'Delete messages cleanly for yourself or everyone without leaving ugly placeholder boxes or residual clutter in the conversation.',
    ),
    (
      icon: Icons.mark_chat_unread_rounded,
      title: 'Teal & White Floating Chat Head',
      description:
          'Ergonomic Messenger-style floating button with vibrant teal styling, dynamic live unread message counts, and bottom navigation placement.',
    ),
  ];

  static IconData _iconForEmoji(String emoji) {
    if (emoji.contains('📷') || emoji.contains('📸') || emoji.contains('🔍')) {
      return Icons.qr_code_scanner_rounded;
    }
    if (emoji.contains('👤') || emoji.contains('👥')) {
      return Icons.account_circle_rounded;
    }
    if (emoji.contains('📅') || emoji.contains('🗓️')) {
      return Icons.calendar_month_rounded;
    }
    if (emoji.contains('🔗') || emoji.contains('📱') || emoji.contains('✈️')) {
      return Icons.share_rounded;
    }
    if (emoji.contains('⚡') || emoji.contains('🚀')) {
      return Icons.flash_on_rounded;
    }
    if (emoji.contains('🎨')) return Icons.palette_rounded;
    if (emoji.contains('📊') || emoji.contains('📈')) {
      return Icons.pie_chart_outline_rounded;
    }
    if (emoji.contains('💬') || emoji.contains('✨')) {
      return Icons.translate_rounded;
    }
    if (emoji.contains('🧾') || emoji.contains('💳')) {
      return Icons.receipt_long_rounded;
    }
    if (emoji.contains('🖼️')) return Icons.image_rounded;
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
    List<({IconData icon, String title, String description})> activeFeatures =
        _features;
    if (updateInfo != null && updateInfo.releaseNotes.isNotEmpty) {
      final parsed = _parseReleaseNotes(updateInfo.releaseNotes);
      if (parsed.isNotEmpty) {
        activeFeatures = parsed;
      }
    }

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
                    children: activeFeatures.map((feature) {
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
