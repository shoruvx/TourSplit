import 'package:cloud_firestore/cloud_firestore.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String minSupportedVersion;
  final String releaseNotes;
  final String apkUrl;
  final bool forceUpdate;
  final bool autoDownload;
  final DateTime? releasedAt;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    this.minSupportedVersion = '1.0.0',
    required this.releaseNotes,
    required this.apkUrl,
    required this.forceUpdate,
    this.autoDownload = true,
    this.releasedAt,
  });

  factory AppUpdateInfo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppUpdateInfo(
      latestVersion: data['latestVersion'] ?? '1.0.0',
      buildNumber: (data['buildNumber'] as num?)?.toInt() ?? 1,
      minSupportedVersion: data['minSupportedVersion'] ?? '1.0.0',
      releaseNotes:
          data['releaseNotes'] ?? 'Bug fixes and performance improvements.',
      apkUrl: data['apkUrl'] ?? '',
      forceUpdate: data['forceUpdate'] ?? false,
      autoDownload: data['autoDownload'] ?? true,
      releasedAt: (data['releasedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'latestVersion': latestVersion,
        'buildNumber': buildNumber,
        'minSupportedVersion': minSupportedVersion,
        'releaseNotes': releaseNotes,
        'apkUrl': apkUrl,
        'forceUpdate': forceUpdate,
        'autoDownload': autoDownload,
        'releasedAt': releasedAt != null
            ? Timestamp.fromDate(releasedAt!)
            : FieldValue.serverTimestamp(),
      };
}
