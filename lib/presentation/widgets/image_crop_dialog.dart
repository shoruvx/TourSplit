import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'gradient_button.dart';

class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageCropDialog({
    super.key,
    required this.imageBytes,
  });

  static Future<Uint8List?> show(BuildContext context, Uint8List imageBytes) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => ImageCropDialog(imageBytes: imageBytes),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  final TransformationController _transformCtrl = TransformationController();
  int _quarterTurns = 0;
  double _zoomLevel = 1.0;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _transformCtrl.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    if ((scale - _zoomLevel).abs() > 0.05) {
      setState(() {
        _zoomLevel = scale.clamp(1.0, 4.0);
      });
    }
  }

  void _onSliderZoom(double value) {
    setState(() => _zoomLevel = value);
    final matrix = Matrix4.diagonal3Values(value, value, 1.0);
    _transformCtrl.value = matrix;
  }

  void _rotateClockwise() {
    HapticFeedback.lightImpact();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _transformCtrl.value = Matrix4.identity();
      _zoomLevel = 1.0;
    });
  }

  void _resetTransform() {
    HapticFeedback.lightImpact();
    setState(() {
      _quarterTurns = 0;
      _zoomLevel = 1.0;
      _transformCtrl.value = Matrix4.identity();
    });
  }

  Future<void> _cropAndFinish() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    HapticFeedback.mediumImpact();

    try {
      // Give the widget tree a tiny tick to settle if mid-interaction
      await Future.delayed(const Duration(milliseconds: 50));

      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop(null);
        return;
      }

      // Capture at pixelRatio 1.4 for crisp ~380x380 avatar with instant encoding & upload
      final ui.Image image = await boundary.toImage(pixelRatio: 1.4);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null && mounted) {
        final croppedBytes = byteData.buffer.asUint8List();
        Navigator.of(context).pop(croppedBytes);
      } else {
        if (mounted) Navigator.of(context).pop(null);
      }
    } catch (e) {
      debugPrint('[IMAGE_CROP_ERROR] $e');
      if (mounted) Navigator.of(context).pop(null);
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final maxByWidth = (screenWidth - 72).clamp(200.0, 300.0);
    final maxByHeight = (screenHeight - 340).clamp(200.0, 300.0);
    final cropSize = maxByWidth < maxByHeight ? maxByWidth : maxByHeight;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar: Title & Reset/Rotate actions
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Crop & Position',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70, size: 20),
                    tooltip: 'Reset',
                    onPressed: _resetTransform,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.rotate_right_rounded,
                        color: Colors.white70, size: 20),
                    tooltip: 'Rotate 90°',
                    onPressed: _rotateClockwise,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(null),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Interactive Crop Viewport Frame
              SizedBox(
                width: cropSize,
                height: cropSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Cropped Render Repaint Boundary
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RepaintBoundary(
                        key: _repaintKey,
                        child: Container(
                          width: cropSize,
                          height: cropSize,
                          color: Colors.black,
                          child: InteractiveViewer(
                            transformationController: _transformCtrl,
                            minScale: 0.5,
                            maxScale: 5.0,
                            boundaryMargin: const EdgeInsets.all(400),
                            clipBehavior: Clip.none,
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: _quarterTurns,
                                child: Image.memory(
                                  widget.imageBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Guide Overlay (Ignored by Pointer)
                    IgnorePointer(
                      child: Container(
                        width: cropSize,
                        height: cropSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primaryTeal.withValues(alpha: 0.8),
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Circular Avatar Preview Ring
                            Container(
                              width: cropSize - 8,
                              height: cropSize - 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            // Subtle center crosshair for alignment
                            Icon(
                              Icons.add,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Helper instruction
              const Text(
                'Pinch or use slider to zoom. Drag to position.',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 8),

              // Zoom Slider
              Row(
                children: [
                  const Icon(Icons.zoom_out_rounded,
                      color: Colors.white60, size: 18),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primaryTeal,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: AppColors.primaryTeal,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: _zoomLevel,
                        min: 1.0,
                        max: 4.0,
                        onChanged: _onSliderZoom,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in_rounded,
                      color: Colors.white60, size: 18),
                ],
              ),
              const SizedBox(height: 14),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GradientButton(
                      onPressed: _isCropping ? null : _cropAndFinish,
                      label: _isCropping ? 'Cropping...' : 'Apply & Save',
                      icon: Icons.check_circle_rounded,
                      gradient: AppColors.primaryGradient,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
