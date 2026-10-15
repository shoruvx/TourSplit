import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Shows a unified modal bottom sheet for alerts, notifications, and status
/// updates inside the app, styled identically to the sign-in required sheet.
Future<T?> showAppNotificationSheet<T>(
  BuildContext context, {
  required IconData icon,
  Color? iconColor,
  Color? iconBgColor,
  required String title,
  required String message,
  String primaryButtonText = 'Got It',
  VoidCallback? onPrimaryPressed,
  String? secondaryButtonText,
  VoidCallback? onSecondaryPressed,
  Widget? additionalContent,
  bool isDismissible = true,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final effectiveIconColor = iconColor ?? AppColors.primaryTeal;
  final effectiveIconBgColor =
      iconBgColor ?? effectiveIconColor.withValues(alpha: 0.12);

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (ctx) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pull bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: effectiveIconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: effectiveIconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      height: 1.4,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),

                  if (additionalContent != null) ...[
                    const SizedBox(height: 16),
                    additionalContent,
                  ],

                  const SizedBox(height: 24),

                  // Primary Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onPrimaryPressed?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        elevation: 0,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          primaryButtonText,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Optional Secondary Action
                  if (secondaryButtonText != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onSecondaryPressed?.call();
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            secondaryButtonText,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
