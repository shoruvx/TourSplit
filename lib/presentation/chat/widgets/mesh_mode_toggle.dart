import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

/// An intuitive dual-state toggle slider for switching between
/// Online Internet/Cloud sync and Offline P2P Mesh mode.
///
/// Features:
/// - One end with Internet icon, the other end with Offline icon
/// - Active sliding button with upper icon and text inside the slider
/// - Smooth animated transitions and haptic feedback
class MeshModeToggle extends StatelessWidget {
  final bool isMeshActive;
  final ValueChanged<bool> onToggle;
  final int peerCount;
  final double height;
  final double width;

  const MeshModeToggle({
    super.key,
    required this.isMeshActive,
    required this.onToggle,
    this.peerCount = 0,
    this.height = 40.0,
    this.width = 118.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbWidth = (width / 2) - 2.0;
    final thumbHeight = height - 6.0;

    final tooltipText = isMeshActive
        ? (peerCount > 0
            ? 'Offline Mode Active ($peerCount peer(s) connected)\nTap to switch to Internet'
            : 'Offline Mode Active (Searching for nearby peers)\nTap to switch to Internet')
        : 'Internet & Cloud Mode Active\nTap to switch to Offline';

    return Tooltip(
      message: tooltipText,
      preferBelow: true,
      child: Semantics(
        label: isMeshActive
            ? 'Offline mode active, switch to Internet mode'
            : 'Internet mode active, switch to Offline mode',
        button: true,
        child: GestureDetector(
          onTapUp: (details) {
            HapticFeedback.lightImpact();
            final isRightSide = details.localPosition.dx > (width / 2);
            if (isRightSide != isMeshActive) {
              onToggle(isRightSide);
            } else {
              onToggle(!isMeshActive);
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.all(3.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: isDark
                    ? (isMeshActive
                        ? AppColors.primaryTeal.withValues(alpha: 0.6)
                        : AppColors.darkBorder)
                    : (isMeshActive
                        ? AppColors.primaryTeal
                        : AppColors.primaryTeal.withValues(alpha: 0.35)),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Static background icons on each end
                Row(
                  children: [
                    // Left end: Internet mode
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.wifi_rounded,
                          size: 15,
                          color: isMeshActive
                              ? (isDark ? Colors.white30 : Colors.black26)
                              : Colors.transparent, // Covered by active thumb
                        ),
                      ),
                    ),
                    // Right end: Offline mode
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.wifi_off_rounded,
                          size: 15,
                          color: !isMeshActive
                              ? (isDark ? Colors.white30 : Colors.black26)
                              : Colors.transparent, // Covered by active thumb
                        ),
                      ),
                    ),
                  ],
                ),

                // Sliding thumb indicating active mode with upper icon & text inside
                AnimatedAlign(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  alignment:
                      isMeshActive ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: thumbWidth,
                    height: thumbHeight,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryTeal,
                          Color(0xFF0F766E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular((height - 6.0) / 2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryTeal
                              .withValues(alpha: isDark ? 0.5 : 0.3),
                          blurRadius: 5,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            key: ValueKey<bool>(isMeshActive),
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isMeshActive
                                    ? Icons.wifi_off_rounded
                                    : Icons.wifi_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isMeshActive ? 'Offline' : 'Internet',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
