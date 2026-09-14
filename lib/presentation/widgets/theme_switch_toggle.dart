import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';

class ThemeSwitchToggle extends ConsumerWidget {
  final double height;
  final double width;

  const ThemeSwitchToggle({
    super.key,
    this.height = 40.0,
    this.width = 68.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);

    final thumbSize = height - 8.0;

    return Semantics(
      label: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(themeModeProvider.notifier).toggleTheme(isDark);
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
                  ? AppColors.darkBorder
                  : AppColors.primaryTeal.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Static background icons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6.0),
                    child: Icon(
                      Icons.wb_sunny_rounded,
                      size: 15,
                      color: isDark
                          ? AppColors.darkTextSecondary.withValues(alpha: 0.45)
                          : Colors.amber.shade700,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Icon(
                      Icons.dark_mode_rounded,
                      size: 15,
                      color: isDark
                          ? AppColors.primaryTeal
                          : AppColors.lightTextSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              // Sliding thumb
              AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOutCubic,
                alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: isDark
                          ? AppColors.primaryTeal.withValues(alpha: 0.5)
                          : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: child,
                      ),
                      child: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.wb_sunny_rounded,
                        key: ValueKey<bool>(isDark),
                        size: 16,
                        color: isDark
                            ? AppColors.primaryTeal
                            : Colors.amber.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
