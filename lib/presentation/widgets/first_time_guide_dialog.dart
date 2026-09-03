import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';

class FirstTimeGuideDialog extends StatefulWidget {
  const FirstTimeGuideDialog({super.key});

  /// Check if the guide should be shown. If so, display it and mark as seen forever.
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final box = await Hive.openBox('app_preferences');
      final hasSeen = box.get('has_seen_first_time_guide', defaultValue: false) as bool;
      if (!hasSeen && context.mounted) {
        // Mark as seen immediately so it NEVER appears again
        await box.put('has_seen_first_time_guide', true);
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const FirstTimeGuideDialog(),
          );
        }
      }
    } catch (e) {
      debugPrint('[GUIDE] Error checking first-time guide: $e');
    }
  }

  @override
  State<FirstTimeGuideDialog> createState() => _FirstTimeGuideDialogState();
}

class _FirstTimeGuideDialogState extends State<FirstTimeGuideDialog> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  final List<({IconData icon, String title, String description})> _steps = const [
    (
      icon: Icons.travel_explore_rounded,
      title: 'Create or Join Tours',
      description: 'Start a tour with friends or join instantly using a 6-digit invite code or QR scan.',
    ),
    (
      icon: Icons.receipt_long_rounded,
      title: 'Track & Split Expenses',
      description: 'Log daily spending with categories, multiple payers, and equal or custom splits.',
    ),
    (
      icon: Icons.handshake_rounded,
      title: 'Smart Settlement',
      description: 'Real-time balances with minimum transactions to settle all debts effortlessly.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar: Dismiss/Skip button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Quick Guide (${_currentPage + 1}/${_steps.length})',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryTeal,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _finish,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Page View Carousel
            SizedBox(
              height: 230,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) {
                  final step = _steps[i];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryTeal.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(step.icon, size: 38, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          step.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 13,
                            height: 1.45,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                final isSelected = _currentPage == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryTeal
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Next / Got It Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_currentPage < _steps.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    _finish();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  _currentPage == _steps.length - 1 ? 'Got it!' : 'Next',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.92, 0.92));
  }
}
