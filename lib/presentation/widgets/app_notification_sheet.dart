import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Shows a unified modal bottom sheet for alerts, notifications, and status
/// updates inside the app, styled identically to the update check popup.
Future<T?> showAppNotificationSheet<T>(
  BuildContext context, {
  IconData? icon,
  Color? iconColor,
  Color? iconBgColor,
  required String title,
  required String message,
  String primaryButtonText = 'Got It',
  Color? primaryButtonColor,
  Color? primaryButtonTextColor,
  T? primaryResult,
  VoidCallback? onPrimaryPressed,
  String? secondaryButtonText,
  Color? secondaryButtonTextColor,
  T? secondaryResult,
  VoidCallback? onSecondaryPressed,
  Widget? additionalContent,
  bool isDismissible = true,
  Duration? autoDismissDuration,
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
      return _AppNotificationSheetWidget<T>(
        isDark: isDark,
        icon: icon,
        effectiveIconColor: effectiveIconColor,
        effectiveIconBgColor: effectiveIconBgColor,
        title: title,
        message: message,
        primaryButtonText: primaryButtonText,
        primaryButtonColor: primaryButtonColor ?? AppColors.primaryTeal,
        primaryButtonTextColor: primaryButtonTextColor ?? Colors.white,
        primaryResult: primaryResult ?? (T == bool ? true as T : null),
        onPrimaryPressed: onPrimaryPressed,
        secondaryButtonText: secondaryButtonText,
        secondaryButtonTextColor: secondaryButtonTextColor,
        secondaryResult: secondaryResult ?? (T == bool ? false as T : null),
        onSecondaryPressed: onSecondaryPressed,
        additionalContent: additionalContent,
        autoDismissDuration: autoDismissDuration,
      );
    },
  );
}

/// Convenience helper for confirmation dialogs styled as unified bottom sheets.
Future<bool> showAppConfirmationSheet(
  BuildContext context, {
  required IconData icon,
  Color? iconColor,
  Color? iconBgColor,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  Color? confirmColor,
  String cancelText = 'Cancel',
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  Widget? additionalContent,
  bool isDismissible = true,
}) async {
  final result = await showAppNotificationSheet<bool>(
    context,
    icon: icon,
    iconColor: iconColor ?? confirmColor,
    iconBgColor: iconBgColor,
    title: title,
    message: message,
    primaryButtonText: confirmText,
    primaryButtonColor: confirmColor ?? AppColors.primaryTeal,
    primaryResult: true,
    onPrimaryPressed: onConfirm,
    secondaryButtonText: cancelText,
    secondaryResult: false,
    onSecondaryPressed: onCancel,
    additionalContent: additionalContent,
    isDismissible: isDismissible,
  );
  return result ?? false;
}

class _AppNotificationSheetWidget<T> extends StatefulWidget {
  final bool isDark;
  final IconData? icon;
  final Color effectiveIconColor;
  final Color effectiveIconBgColor;
  final String title;
  final String message;
  final String primaryButtonText;
  final Color primaryButtonColor;
  final Color primaryButtonTextColor;
  final T? primaryResult;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryButtonText;
  final Color? secondaryButtonTextColor;
  final T? secondaryResult;
  final VoidCallback? onSecondaryPressed;
  final Widget? additionalContent;
  final Duration? autoDismissDuration;

  const _AppNotificationSheetWidget({
    required this.isDark,
    this.icon,
    required this.effectiveIconColor,
    required this.effectiveIconBgColor,
    required this.title,
    required this.message,
    required this.primaryButtonText,
    required this.primaryButtonColor,
    required this.primaryButtonTextColor,
    required this.primaryResult,
    required this.onPrimaryPressed,
    required this.secondaryButtonText,
    required this.secondaryButtonTextColor,
    required this.secondaryResult,
    required this.onSecondaryPressed,
    required this.additionalContent,
    required this.autoDismissDuration,
  });

  @override
  State<_AppNotificationSheetWidget<T>> createState() =>
      _AppNotificationSheetWidgetState<T>();
}

class _AppNotificationSheetWidgetState<T>
    extends State<_AppNotificationSheetWidget<T>> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoDismissDuration != null) {
      _autoDismissTimer = Timer(widget.autoDismissDuration!, () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.4 : 0.1),
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
                    color: widget.isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Icon badge (optional)
                if (widget.icon != null) ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: widget.effectiveIconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.effectiveIconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Title
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: widget.isDark
                        ? AppColors.darkText
                        : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 8),

                // Message description
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    height: 1.4,
                    color: widget.isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),

                if (widget.additionalContent != null) ...[
                  const SizedBox(height: 16),
                  widget.additionalContent!,
                ],

                const SizedBox(height: 24),

                // Primary Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _autoDismissTimer?.cancel();
                      Navigator.of(context).pop(widget.primaryResult);
                      widget.onPrimaryPressed?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryButtonColor,
                      foregroundColor: widget.primaryButtonTextColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      elevation: 0,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.primaryButtonText,
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
                if (widget.secondaryButtonText != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        _autoDismissTimer?.cancel();
                        Navigator.of(context).pop(widget.secondaryResult);
                        widget.onSecondaryPressed?.call();
                      },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.secondaryButtonText!,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: widget.secondaryButtonTextColor ??
                                (widget.isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary),
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
  }
}
