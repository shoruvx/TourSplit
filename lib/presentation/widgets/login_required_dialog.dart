import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Shows a dialog or modal bottom sheet informing guest users that
/// an action (e.g. creating a tour, joining a tour, or viewing profile)
/// requires authentication.
Future<bool?> showLoginRequiredDialog(
  BuildContext context, {
  required String action,
  String? customMessage,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
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
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.primaryTeal,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    'Sign In Required',
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
                    customMessage ??
                        'You are currently exploring TourSplit as a guest. Please sign in or create an account to $action.',
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
                  const SizedBox(height: 24),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop(true);
                        context.push('/login');
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
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Sign In or Register',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Cancel / Continue Exploring
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Continue Exploring',
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
              ),
            ),
          ),
        ),
      );
    },
  );
}
