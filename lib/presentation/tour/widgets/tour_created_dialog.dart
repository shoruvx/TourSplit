import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class TourCreatedDialog extends StatelessWidget {
  final String tourName;
  final String inviteCode;
  final VoidCallback? onDone;

  const TourCreatedDialog({
    super.key,
    required this.tourName,
    required this.inviteCode,
    this.onDone,
  });

  static Future<void> show(
    BuildContext context, {
    required String tourName,
    required String inviteCode,
    VoidCallback? onDone,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TourCreatedDialog(
        tourName: tourName,
        inviteCode: inviteCode,
        onDone: onDone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final joinUrl =
        'https://github.com/${AppConstants.githubRepo}/releases/latest?code=$inviteCode';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onDone != null) {
          onDone!();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Celebration Icon Badge
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.positive.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.positive.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.positive,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Success Title
                Text(
                  'Tour Created Successfully!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // Tour Name Highlight
                Text(
                  tourName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryTeal,
                    fontSize: 22,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Subtitle
                Text(
                  'Share this QR code or 6-character code with your travel companions.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Outfit',
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 12.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),

                // QR Code Container
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: joinUrl,
                    version: QrVersions.auto,
                    size: 180,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0F172A),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Invite Code Box with Actions
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inviteCode,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'Copy Invite Code',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Clipboard.setData(ClipboardData(text: inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invite code copied to clipboard!'),
                              backgroundColor: AppColors.accent,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_rounded, size: 18),
                        tooltip: 'Share Invite Link',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Share.share(
                            'Join my tour "$tourName" on TourSplit!\n'
                            'Invite code: $inviteCode\n\n'
                            'Download & Join TourSplit:\n$joinUrl',
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Bottom Middle: "Done" Button taking inside the tour
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      if (onDone != null) {
                        onDone!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    label: 'Done',
                    icon: Icons.arrow_forward_rounded,
                    gradient: AppColors.primaryGradient,
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
