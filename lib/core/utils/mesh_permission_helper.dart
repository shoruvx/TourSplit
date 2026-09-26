import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'bluetooth_helper.dart';

class MeshPermissionHelper {
  /// Request all required permissions for P2P Mesh Networking.
  /// Fully backwards compatible with older devices like Android 7 (API 24/25)
  /// as well as modern Android 12, 13, 14, 15+ (API 31+).
  static Future<bool> requestMeshPermissions(BuildContext context) async {
    if (kIsWeb) return false;

    final sdkInt = await BluetoothHelper.getSdkInt();

    // On older Android (Android 7-11, API < 31):
    // Only location is a runtime permission required by Nearby/BLE scanning.
    // Bluetooth and BluetoothAdmin are granted in the manifest at install time.
    if (sdkInt < 31) {
      await Permission.notification.request();
      final locStatus = await Permission.locationWhenInUse.request();
      final ok = locStatus.isGranted || (await Permission.location.isGranted);
      if (!ok && locStatus.isPermanentlyDenied && context.mounted) {
        _showSettingsDialog(context);
        return false;
      }
      return ok;
    }

    // On modern Android (Android 12+, API 31+):
    // Runtime permissions for Bluetooth Scan/Connect/Advertise, Location, and Notifications are needed.
    final permissions = <Permission>[
      Permission.notification,
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];

    final statuses = await permissions.request();

    final locationOk = statuses[Permission.locationWhenInUse]?.isGranted ??
        statuses[Permission.location]?.isGranted ??
        false;

    final btScanOk = statuses[Permission.bluetoothScan]?.isGranted ?? true;
    final btAdvOk = statuses[Permission.bluetoothAdvertise]?.isGranted ?? true;
    final btConnOk = statuses[Permission.bluetoothConnect]?.isGranted ?? true;

    final isAllGood = locationOk && btScanOk && btAdvOk && btConnOk;

    final anyPermanentlyDenied =
        statuses.values.any((status) => status.isPermanentlyDenied);

    if (!isAllGood && anyPermanentlyDenied && context.mounted) {
      _showSettingsDialog(context);
      return false;
    }

    return isAllGood;
  }

  static void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'Offline P2P Mesh chat requires Bluetooth, Nearby Devices, Location, and Notification permissions to discover peers and deliver messages instantly.\n\nPlease enable them in App Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
