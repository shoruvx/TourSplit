import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BluetoothHelper {
  static const MethodChannel _channel =
      MethodChannel('com.shoruv.toursplit/bluetooth');

  /// Check if Bluetooth is currently turned on
  static Future<bool> isBluetoothEnabled() async {
    if (kIsWeb) return true;
    try {
      final bool? enabled = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return enabled ?? true;
    } catch (e) {
      debugPrint('[BLUETOOTH_HELPER] Error checking bluetooth: $e');
      return true;
    }
  }

  /// Request the system to prompt the user to turn on Bluetooth ("Allow" dialog)
  static Future<bool> requestEnableBluetooth() async {
    if (kIsWeb) return true;
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('requestEnableBluetooth');
      return result ?? false;
    } catch (e) {
      debugPrint('[BLUETOOTH_HELPER] Error requesting bluetooth enable: $e');
      return false;
    }
  }

  /// Waits until Bluetooth is enabled, polling every 350ms up to [timeout] duration
  static Future<bool> waitForBluetoothEnabled({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (kIsWeb) return true;
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (await isBluetoothEnabled()) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 350));
    }
    return isBluetoothEnabled();
  }

  /// Get Android SDK version (e.g., 24 for Android 7.0, 31 for Android 12)
  static Future<int> getSdkInt() async {
    if (kIsWeb) return 33;
    try {
      final int? sdk = await _channel.invokeMethod<int>('getSdkInt');
      return sdk ?? 33;
    } catch (_) {
      return 33;
    }
  }
}
