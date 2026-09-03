import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final LinearGradient? gradient;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.gradient,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final grad = gradient ?? AppColors.primaryGradient;

    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: onPressed == null ? null : grad,
          color: onPressed == null ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
