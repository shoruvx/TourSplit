import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:ota_update/ota_update.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../models/app_update_model.dart';
import 'notification_service.dart';

final appUpdateInfoStreamProvider = StreamProvider<AppUpdateInfo?>((ref) {
  try {
    return FirebaseFirestore.instance
        .collection('app_config')
        .doc('version')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return AppUpdateInfo.fromFirestore(doc);
    }).handleError((_) => null);
  } catch (_) {
    return const Stream.empty();
  }
});

final currentAppVersionProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

final gitHubUpdateFutureProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  return await AppUpdateService.fetchGitHubRelease();
});

final latestUpdateInfoProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  final ghUpdate = await AppUpdateService.fetchGitHubRelease();
  if (ghUpdate != null) {
    AppUpdateService.syncReleaseToFirestoreIfNewer(ghUpdate).catchError((_) {});
    return ghUpdate;
  }

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
  static String? _lastNotifiedVersion;

  static const MethodChannel _installerChannel =
      MethodChannel('com.shoruv.toursplit/installer');

  static bool isVersionNewer(String latest, String current) {
    try {
      final cleanLatest =
          latest.split('+').first.replaceAll(RegExp(r'[^0-9.]'), '').trim();
      final cleanCurrent =
          current.split('+').first.replaceAll(RegExp(r'[^0-9.]'), '').trim();

      final latestParts =
          cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts =
          cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (int i = 0; i < maxLen; i++) {
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

  static String cleanVersion(String version) {
    return version
        .split('+')
        .first
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .trim();
  }

  static Future<bool> isApkDownloaded(String version) async {
    if (!Platform.isAndroid) return false;
    try {
      final cleanVer = cleanVersion(version);
      final filename = 'TourSplit-v$cleanVer.apk';
      final result = await _installerChannel
          .invokeMethod<bool>('isApkDownloaded', {'filename': filename});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> installDownloadedApk(String version) async {
    if (!Platform.isAndroid) return false;
    try {
      final cleanVer = cleanVersion(version);
      final filename = 'TourSplit-v$cleanVer.apk';
      final result = await _installerChannel
          .invokeMethod<bool>('installApk', {'filename': filename});
      return result ?? false;
    } catch (e) {
      debugPrint('[INSTALLER] Error installing apk: $e');
      return false;
    }
  }

  static void notifyIfNewUpdate(AppUpdateInfo info, String currentVersion) {
    if (isVersionNewer(info.latestVersion, currentVersion)) {
      if (_lastNotifiedVersion != info.latestVersion) {
        _lastNotifiedVersion = info.latestVersion;
        NotificationService.showUpdateNotification(
          latestVersion: info.latestVersion,
          releaseNotes: info.releaseNotes,
        );
      }
    }
  }

  static String? _lastPromptedDialogVersion;

  static void promptUpdateIfNeeded(
      BuildContext context, AppUpdateInfo info, String currentVersion) {
    if (isVersionNewer(info.latestVersion, currentVersion)) {
      notifyIfNewUpdate(info, currentVersion);
      if (_lastPromptedDialogVersion != info.latestVersion) {
        _lastPromptedDialogVersion = info.latestVersion;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            showUpdateDialog(context, info: info, currentVersion: currentVersion);
          }
        });
      }
    }
  }

  static Future<AppUpdateInfo?> fetchGitHubRelease({String? repo}) async {
    final repository = repo ?? AppConstants.githubRepo;

    // 1. Try official GitHub API
    try {
      final uri =
          Uri.parse('https://api.github.com/repos/$repository/releases/latest');
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'TourSplit-App',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawTag = data['tag_name'] as String? ?? '1.0.0';
        final latestVersion =
            rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
        final releaseNotes =
            data['body'] as String? ?? 'TourSplit release update! 🎉';
        final assets = data['assets'] as List<dynamic>? ?? [];

        String apkUrl = '';
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }

        if (apkUrl.isEmpty) {
          apkUrl = data['html_url'] as String? ??
              'https://github.com/$repository/releases';
        }

        return AppUpdateInfo(
          latestVersion: latestVersion,
          buildNumber: 1,
          releaseNotes: releaseNotes,
          apkUrl: apkUrl,
          forceUpdate: releaseNotes.contains('[FORCE_UPDATE]') ||
              releaseNotes.contains('#mandatory'),
          releasedAt:
              DateTime.tryParse(data['published_at'] as String? ?? '') ??
                  DateTime.now(),
        );
      }
    } catch (_) {}

    // 2. Resilient Fallback: Query GitHub releases via redirect (zero API rate limit issues)
    try {
      final client = http.Client();
      final request = http.Request(
        'GET',
        Uri.parse('https://github.com/$repository/releases/latest'),
      )..followRedirects = false;

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 5));
      final location = streamedResponse.headers['location'] ?? '';

      if (location.isNotEmpty && location.contains('/releases/tag/')) {
        final rawTag = location.split('/').last;
        final latestVersion =
            rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;

        final assetsUri = Uri.parse(
            'https://github.com/$repository/releases/expanded_assets/$rawTag');
        final assetsResp =
            await http.get(assetsUri).timeout(const Duration(seconds: 5));

        String apkUrl = '';
        final match =
            RegExp(r'href="([^"]+\.apk)"').firstMatch(assetsResp.body);
        if (match != null) {
          final matchedHref = match.group(1)!;
          apkUrl = matchedHref.startsWith('http')
              ? matchedHref
              : 'https://github.com$matchedHref';
        }

        if (apkUrl.isEmpty) {
          apkUrl =
              'https://github.com/$repository/releases/download/$rawTag/TourSplit.apk';
        }

        final updateInfo = AppUpdateInfo(
          latestVersion: latestVersion,
          buildNumber: 5,
          minSupportedVersion: '1.0.1',
          releaseNotes:
              'TourSplit v$latestVersion is available on GitHub with the latest updates! 🎉',
          apkUrl: apkUrl,
          forceUpdate: false,
          releasedAt: DateTime.now(),
        );
        syncReleaseToFirestoreIfNewer(updateInfo).catchError((_) {});
        return updateInfo;
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> launchDownload(String url) async {
    if (url.isEmpty) return false;
    final uri = Uri.parse(url);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> checkForUpdatesInteractive(
      BuildContext context, WidgetRef ref) async {
    final packageInfo = await ref.read(currentAppVersionProvider.future);
    final currentVer = packageInfo.version;

    final updateInfo = await ref.refresh(latestUpdateInfoProvider.future);
    if (!context.mounted) return;

    if (updateInfo != null &&
        isVersionNewer(updateInfo.latestVersion, currentVer)) {
      notifyIfNewUpdate(updateInfo, currentVer);
      showUpdateDialog(context, info: updateInfo, currentVersion: currentVer);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'You are on the latest version of TourSplit (v$currentVer) ✨'),
          backgroundColor: AppColors.positive,
        ),
      );
    }
  }

  static Future<void> syncReleaseToFirestoreIfNewer(AppUpdateInfo ghInfo) async {
    try {
      final doc =
          await _firestore.collection('app_config').doc('version').get();
      bool shouldUpdate = false;
      if (!doc.exists) {
        shouldUpdate = true;
      } else {
        final currentLatest =
            (doc.data()?['latestVersion'] as String?) ?? '1.0.0';
        if (isVersionNewer(ghInfo.latestVersion, currentLatest)) {
          shouldUpdate = true;
        }
      }

      if (shouldUpdate) {
        await publishUpdate(
          latestVersion: ghInfo.latestVersion,
          buildNumber: ghInfo.buildNumber > 1 ? ghInfo.buildNumber : 5,
          releaseNotes: ghInfo.releaseNotes,
          apkUrl: ghInfo.apkUrl,
          forceUpdate: ghInfo.forceUpdate,
          minSupportedVersion: '1.0.1',
        );
      }
    } catch (_) {}
  }

  static Future<void> publishUpdate({
    required String latestVersion,
    required int buildNumber,
    required String releaseNotes,
    required String apkUrl,
    bool forceUpdate = false,
    String minSupportedVersion = '1.0.1',
  }) async {
    await _firestore.collection('app_config').doc('version').set({
      'latestVersion': latestVersion,
      'buildNumber': buildNumber,
      'minSupportedVersion': minSupportedVersion,
      'releaseNotes': releaseNotes,
      'apkUrl': apkUrl,
      'forceUpdate': forceUpdate,
      'releasedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static void showUpdateDialog(
    BuildContext context, {
    required AppUpdateInfo info,
    required String currentVersion,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => _UpdateDialogWidget(
        info: info,
        currentVersion: currentVersion,
      ),
    );
  }
}

class _UpdateDialogWidget extends StatefulWidget {
  final AppUpdateInfo info;
  final String currentVersion;

  const _UpdateDialogWidget({
    required this.info,
    required this.currentVersion,
  });

  @override
  State<_UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

enum _UpdateStep { idle, downloading, installing, error }

class _UpdateDialogWidgetState extends State<_UpdateDialogWidget> {
  _UpdateStep _step = _UpdateStep.idle;
  int _progress = 0;
  String _statusText = '';
  String? _errorMessage;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _checkDownloadedApk();
  }

  Future<void> _checkDownloadedApk() async {
    final downloaded =
        await AppUpdateService.isApkDownloaded(widget.info.latestVersion);
    if (mounted && downloaded) {
      setState(() {
        _isDownloaded = true;
      });
    }
  }

  String _cleanNotes(String raw) {
    if (raw.isEmpty) return 'Bug fixes and performance improvements.';
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) =>
            l.isNotEmpty &&
            !l.toLowerCase().startsWith('## what\'s new') &&
            !l.toLowerCase().startsWith('## release'))
        .map((l) {
      var line = l;
      if (line.startsWith('### ')) line = line.substring(4).trim();
      if (line.startsWith('## ')) line = line.substring(3).trim();
      if (line.startsWith('# ')) line = line.substring(2).trim();
      line = line.replaceAll('**', '');
      if (line.startsWith('- ')) line = '• ${line.substring(2)}';
      return line;
    }).toList();
    return lines.take(3).join('\n');
  }

  Future<void> _triggerInstall() async {
    setState(() {
      _step = _UpdateStep.installing;
      _progress = 100;
      _statusText = 'Opening package installer...';
      _errorMessage = null;
    });

    final success =
        await AppUpdateService.installDownloadedApk(widget.info.latestVersion);
    if (!success && mounted) {
      // If launching existing file failed, fallback to downloading
      _startOtaUpdate();
    }
  }

  void _startOtaUpdate() {
    if (!Platform.isAndroid) {
      AppUpdateService.launchDownload(widget.info.apkUrl);
      return;
    }

    if (widget.info.apkUrl.isEmpty) {
      setState(() {
        _step = _UpdateStep.error;
        _errorMessage = 'Download URL is not available.';
      });
      return;
    }

    setState(() {
      _step = _UpdateStep.downloading;
      _progress = 0;
      _statusText = 'Starting download...';
      _errorMessage = null;
    });

    final filename =
        'TourSplit-v${AppUpdateService.cleanVersion(widget.info.latestVersion)}.apk';

    try {
      OtaUpdate()
          .execute(
        widget.info.apkUrl,
        destinationFilename: filename,
        androidProviderAuthority: 'com.shoruv.toursplit.ota_update_provider',
      )
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = int.tryParse(event.value ?? '0') ?? _progress;
              setState(() {
                _step = _UpdateStep.downloading;
                _progress = pct;
                _statusText = 'Downloading... $pct%';
              });
              break;
            case OtaStatus.INSTALLING:
              setState(() {
                _isDownloaded = true;
                _step = _UpdateStep.installing;
                _progress = 100;
                _statusText = 'Package ready to install';
              });
              break;
            case OtaStatus.INSTALLATION_DONE:
              if (mounted) Navigator.of(context).pop();
              break;
            case OtaStatus.ALREADY_RUNNING_ERROR:
              setState(() {
                _step = _UpdateStep.downloading;
                _statusText = 'Update in progress...';
              });
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() {
                _step = _UpdateStep.error;
                _errorMessage =
                    'Install permission not granted. Please allow installing unknown apps or download via browser.';
              });
              break;
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.INSTALLATION_ERROR:
              setState(() {
                _step = _UpdateStep.error;
                _errorMessage =
                    'Download issue (${event.status.name}). Use browser download below.';
              });
              break;
            case OtaStatus.CANCELED:
              setState(() {
                _step = _UpdateStep.idle;
              });
              break;
          }
        },
        onError: (err) {
          if (!mounted) return;
          setState(() {
            _step = _UpdateStep.error;
            _errorMessage = 'Download failed. Use browser download below.';
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _UpdateStep.error;
        _errorMessage = 'Could not start download: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.info.forceUpdate && _step != _UpdateStep.downloading,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryTeal.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset('assets/images/logo.png',
                            fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTeal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.rocket_launch_rounded,
                            color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 12),
                const Text(
                  'Update Available! 🚀',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isDownloaded
                      ? 'Version v${widget.info.latestVersion} is downloaded & ready'
                      : 'Version v${widget.info.latestVersion} is available',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF5EEAD4)
                        : AppColors.primaryTeal,
                  ),
                ),
                const SizedBox(height: 14),

                // Step View
                if (_step == _UpdateStep.idle) ...[
                  if (_isDownloaded) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.positive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.positive.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: AppColors.positive, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'APK is already downloaded! Tap below to install.',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.positive,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 110),
                      child: SingleChildScrollView(
                        child: Text(
                          _cleanNotes(widget.info.releaseNotes),
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            height: 1.45,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!widget.info.forceUpdate) ...[
                        Expanded(
                          flex: 4,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              'Later',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 6,
                        child: ElevatedButton.icon(
                          onPressed: _isDownloaded ? _triggerInstall : _startOtaUpdate,
                          icon: Icon(
                            _isDownloaded
                                ? Icons.system_update_rounded
                                : Icons.bolt_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: Text(
                            _isDownloaded ? 'Install Now' : 'Update Now',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryTeal,
                            padding:
                                const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isDownloaded) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _startOtaUpdate,
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text(
                        'Re-download update package',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.white60 : Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ],
                ] else if (_step == _UpdateStep.downloading) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _statusText,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '$_progress%',
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryTeal,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _progress / 100.0,
                            minHeight: 8,
                            backgroundColor: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primaryTeal),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Downloading from GitHub releases...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_step == _UpdateStep.installing) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primaryTeal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primaryTeal,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Download Complete!',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'If the installer didn\'t appear or was dismissed, tap "Open Installer" below to install without re-downloading.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11.5,
                            height: 1.35,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _triggerInstall,
                            icon: const Icon(Icons.system_update_rounded,
                                color: Colors.white, size: 18),
                            label: const Text(
                              'Open Installer',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryTeal,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _startOtaUpdate,
                              icon: const Icon(Icons.refresh_rounded, size: 13),
                              label: const Text(
                                'Re-download',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    isDark ? Colors.white60 : Colors.black54,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ),
                            ),
                            if (!widget.info.forceUpdate) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      isDark ? Colors.white60 : Colors.black54,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                ),
                                child: const Text(
                                  'Dismiss',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (_step == _UpdateStep.error) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.danger, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage ?? 'Update could not be completed.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_isDownloaded) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _triggerInstall,
                            icon: const Icon(Icons.system_update_rounded,
                                color: Colors.white, size: 15),
                            label: const Text(
                              'Install',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryTeal,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _startOtaUpdate,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Try Again',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => AppUpdateService.launchDownload(
                              widget.info.apkUrl),
                          icon: const Icon(Icons.download_rounded,
                              color: Colors.white, size: 16),
                          label: const Text(
                            'Browser',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryTeal,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
