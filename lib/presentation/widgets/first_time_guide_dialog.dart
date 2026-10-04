import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';

class FirstTimeGuideDialog extends StatelessWidget {
  const FirstTimeGuideDialog({super.key});

  static bool _hasCheckedThisSession = false;

  static Future<void> checkAndShow(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;
    try {
      final box = await Hive.openBox('app_preferences');
      final hasSeen =
          box.get('has_seen_first_time_guide', defaultValue: false) as bool;
      if (!hasSeen && context.mounted) {
        await box.put('has_seen_first_time_guide', true);
        if (context.mounted) {
          show(context);
        }
      }
    } catch (e) {
      debugPrint('[GUIDE] Error checking first-time guide: $e');
    }
  }

  static Future<void> show(BuildContext context) async {
    if (!context.mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (ctx, anim, secAnim) => const FirstTimeGuideDialog(),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  static const List<({IconData icon, String title, String description})> _steps =
      [
    (
      icon: Icons.travel_explore_rounded,
      title: 'Create & Join Tours',
      description:
          'Create a trip or join instantly with a 6-digit code or QR scan.',
    ),
    (
      icon: Icons.receipt_long_rounded,
      title: 'Track Expenses',
      description:
          'Log spending with custom split ratios, multiple payers, and offline support.',
    ),
    (
      icon: Icons.handshake_rounded,
      title: 'Simplified Settlements',
      description:
          'Clear balances with minimized transactions and saved payment accounts.',
    ),
    (
      icon: Icons.forum_rounded,
      title: 'Peer-to-Peer Chat',
      description:
          'Coordinate with companions and react in real-time or offline nearby.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    // Centered top title (matching screenshot layout)
                    Text(
                      'TourSplit',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.lightText,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Split the costs, keep the memories.',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Minimalist feature highlights
                    ..._steps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final step = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                step.icon,
                                size: 22,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : AppColors.lightText,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    step.description,
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 14,
                                      height: 1.42,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: 60 * index),
                            duration: 350.ms,
                          )
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          );
                    }),
                  ],
                ),
              ),
            ),

            // Modern Pill Bottom Action Button
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
