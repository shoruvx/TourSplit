import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_theme.dart';

class TourQrScannerView extends StatefulWidget {
  final Function(String code) onScanned;
  final VoidCallback onCancel;

  const TourQrScannerView({
    super.key,
    required this.onScanned,
    required this.onCancel,
  });

  @override
  State<TourQrScannerView> createState() => _TourQrScannerViewState();
}

class _TourQrScannerViewState extends State<TourQrScannerView> {
  late MobileScannerController _controller;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        final code = _extractInviteCode(raw);
        if (code.length == 6) {
          _hasScanned = true;
          HapticFeedback.mediumImpact();
          widget.onScanned(code);
          break;
        }
      }
    }
  }

  String _extractInviteCode(String input) {
    final clean = input.trim();

    // 1. Try parsing as a URL for 'code' or 'join' query parameter
    try {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        final codeParam =
            uri.queryParameters['code'] ?? uri.queryParameters['join'];
        if (codeParam != null && codeParam.trim().length == 6) {
          return codeParam.trim().toUpperCase();
        }
      }
    } catch (_) {}

    // 2. Look for code= or join= in raw string
    final queryMatch = RegExp(r'[?&](?:code|join)=([A-Z0-9]{6})\b',
            caseSensitive: false)
        .firstMatch(clean);
    if (queryMatch != null) {
      return queryMatch.group(1)!.toUpperCase();
    }

    // 3. Direct 6-character clean code
    final direct = clean.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    if (direct.length == 6 && RegExp(r'^[A-Z0-9]{6}$').hasMatch(direct)) {
      return direct;
    }

    // 4. Word boundary match, excluding common URL keywords like GITHUB, LATEST
    final matches =
        RegExp(r'\b([A-Z0-9]{6})\b', caseSensitive: false).allMatches(clean);
    for (final m in matches) {
      final val = m.group(1)!.toUpperCase();
      if (val != 'GITHUB' && val != 'LATEST') {
        return val;
      }
    }

    return direct;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
            errorBuilder: (context, error) {
              return Container(
                color: Colors.black,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined,
                          color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Camera permission needed',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please allow camera access to scan QR codes: ${error.errorDetails?.message ?? error.toString()}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) {
                      final isOn = state.torchState == TorchState.on;
                      return IconButton(
                        icon: Icon(
                          isOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: isOn ? Colors.amber : Colors.white,
                        ),
                        onPressed: () => _controller.toggleTorch(),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.cameraswitch_rounded,
                        color: Colors.white),
                    onPressed: () => _controller.switchCamera(),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Align QR code within the box',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
