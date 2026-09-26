import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'active_tour_cache_service.dart';
import 'offline_tour_queue_service.dart';

class StorageOptimizationService {
  static const MethodChannel _installerChannel =
      MethodChannel('com.shoruv.toursplit/installer');

  /// Clear all accumulated APK files left over in filesDir/ota_update/
  static Future<int> clearDownloadedApks() async {
    try {
      final res = await _installerChannel
          .invokeMethod<Map<dynamic, dynamic>>('clearDownloadedApks');
      final freedBytes = (res?['freedBytes'] as num?)?.toInt() ?? 0;
      final deletedCount = (res?['deletedCount'] as num?)?.toInt() ?? 0;
      if (deletedCount > 0) {
        debugPrint(
            '[STORAGE] Successfully deleted $deletedCount old APK(s), freed ${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB');
      }
      return freedBytes;
    } catch (e) {
      debugPrint('[STORAGE] clearDownloadedApks error: $e');
      return 0;
    }
  }

  /// Clean up Flutter image cache and stale temporary files
  static Future<void> cleanupImageCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      debugPrint('[STORAGE] Image cache purged successfully');
    } catch (e) {
      debugPrint('[STORAGE] cleanupImageCache error: $e');
    }
  }

  /// Run comprehensive storage optimization on app launch
  static Future<void> runStartupStorageOptimization() async {
    try {
      // 1. Purge old OTA APK downloads
      await clearDownloadedApks();

      // 2. Prune any stale tour data so only the latest active tour is kept
      await ActiveTourCacheService.pruneStaleToursCache();

      // 3. Prune orphaned local member records
      await OfflineTourQueueService.pruneOrphanedLocalData();

      // 2. Clean temporary directory if accessible
      final tempDir = Directory.systemTemp;
      if (tempDir.existsSync()) {
        final now = DateTime.now();
        await for (final file in tempDir.list(followLinks: false)) {
          try {
            if (file is File) {
              final stat = await file.stat();
              // Remove temporary files older than 24 hours
              if (now.difference(stat.modified).inHours > 24) {
                await file.delete();
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[STORAGE] runStartupStorageOptimization error: $e');
    }
  }
}
