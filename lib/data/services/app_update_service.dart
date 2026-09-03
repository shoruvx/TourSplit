import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../models/app_update_model.dart';

final appUpdateInfoStreamProvider = StreamProvider<AppUpdateInfo?>((ref) {
  return FirebaseFirestore.instance
      .collection('app_config')
      .doc('version')
      .snapshots()
      .map((doc) {
    if (!doc.exists) return null;
    return AppUpdateInfo.fromFirestore(doc);
  });
});

final currentAppVersionProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

/// Direct GitHub Releases provider (Queries GitHub API directly)
final gitHubUpdateFutureProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  return await AppUpdateService.fetchGitHubRelease();
});

/// Unified update provider: Checks GitHub Releases first, then Firestore fallback
final latestUpdateInfoProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  // 1. Check GitHub Releases first (free, public, no database setup required)
  final ghUpdate = await AppUpdateService.fetchGitHubRelease();
  if (ghUpdate != null) return ghUpdate;

  // 2. Fall back to Firestore remote config
  try {
    final firestoreDoc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('version')
        .get();
    if (firestoreDoc.exists) {
      return AppUpdateInfo.fromFirestore(firestoreDoc);
    }
  } catch (_) {}
  return null;
});

class AppUpdateService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Helper to compare semantic version strings (e.g. "1.1.0" > "1.0.0")
  static bool isVersionNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }

  /// Fetch the latest release directly from GitHub Releases API
  static Future<AppUpdateInfo?> fetchGitHubRelease({String? repo}) async {
    try {
      final repository = repo ?? AppConstants.githubRepo;
      final uri = Uri.parse('https://api.github.com/repos/$repository/releases/latest');
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'TourSplit-App',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawTag = data['tag_name'] as String? ?? '1.0.0';
        final latestVersion = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
        final releaseNotes = data['body'] as String? ?? 'TourSplit release update! 🎉';
        final assets = data['assets'] as List<dynamic>? ?? [];

        // Find the APK download asset
        String apkUrl = '';
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }

        if (apkUrl.isEmpty) {
          apkUrl = data['html_url'] as String? ?? 'https://github.com/$repository/releases';
        }

        return AppUpdateInfo(
          latestVersion: latestVersion,
          buildNumber: 1,
          releaseNotes: releaseNotes,
          apkUrl: apkUrl,
          forceUpdate: releaseNotes.contains('[FORCE_UPDATE]') || releaseNotes.contains('#mandatory'),
          releasedAt: DateTime.tryParse(data['published_at'] as String? ?? '') ?? DateTime.now(),
        );
      }
    } catch (_) {
      // Silently fall back
    }
    return null;
  }

  /// Launch APK download or release URL
  static Future<bool> launchDownload(String url) async {
    if (url.isEmpty) return false;
    final uri = Uri.parse(url);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Interactive check for updates button (Used in Profile)
  static Future<void> checkForUpdatesInteractive(BuildContext context, WidgetRef ref) async {
    final packageInfo = await ref.read(currentAppVersionProvider.future);
    final currentVer = packageInfo.version;

    // Refresh unified provider to fetch fresh release from GitHub / Firestore
    final updateInfo = await ref.refresh(latestUpdateInfoProvider.future);
    if (!context.mounted) return;

    if (updateInfo != null && isVersionNewer(updateInfo.latestVersion, currentVer)) {
      showUpdateDialog(context, info: updateInfo, currentVersion: currentVer);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are on the latest version of TourSplit (v$currentVer) ✨'),
          backgroundColor: AppColors.positive,
        ),
      );
    }
  }

  /// Publish a new update to Firestore (Accessible by App Owner)
  static Future<void> publishUpdate({
    required String latestVersion,
    required int buildNumber,
    required String releaseNotes,
    required String apkUrl,
    bool forceUpdate = false,
  }) async {
    await _firestore.collection('app_config').doc('version').set({
      'latestVersion': latestVersion,
      'buildNumber': buildNumber,
      'releaseNotes': releaseNotes,
      'apkUrl': apkUrl,
      'forceUpdate': forceUpdate,
      'releasedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Displays the interactive update dialog to the user
  static void showUpdateDialog(
    BuildContext context, {
    required AppUpdateInfo info,
    required String currentVersion,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return PopScope(
          canPop: !info.forceUpdate,
          child: Dialog(
            backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Icon with Rocket Badge
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryTeal.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryTeal,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

                  const SizedBox(height: 18),
                  const Text(
                    'TourSplit Update Available! 🚀',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Version v${info.latestVersion} is ready to install',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF5EEAD4) : AppColors.primaryTeal,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Release notes card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primaryTeal),
                            const SizedBox(width: 6),
                            Text(
                              "What's New in v${info.latestVersion}",
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          info.releaseNotes,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12.5,
                            height: 1.4,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      if (!info.forceUpdate) ...[
                        Expanded(
                          flex: 4,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Later',
                              style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 6,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (info.apkUrl.isNotEmpty) {
                              await launchDownload(info.apkUrl);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download URL is being configured by the admin.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                          label: const Text(
                            'Update Now',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryTeal,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
