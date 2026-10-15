import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';

class GuideFeatureItem {
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final Color accentColor;

  const GuideFeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.accentColor,
  });
}

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

  static const List<GuideFeatureItem> features = [
    GuideFeatureItem(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Create & Join Tours with QR',
      description:
          'Create private or group tours in seconds. Join companions instantly by scanning a Tour QR code or entering a tour code.',
      badge: 'QR & Code',
      accentColor: AppColors.primaryTeal,
    ),
    GuideFeatureItem(
      icon: Icons.person_add_alt_1_rounded,
      title: 'Add Members with Code or QR',
      description:
          'Invite travel companions via a 6-digit invite code or scannable QR card so everyone stays connected on the go.',
      badge: 'Easy Invites',
      accentColor: Color(0xFF0284C7),
    ),
    GuideFeatureItem(
      icon: Icons.receipt_long_rounded,
      title: 'Add Expenses & Split Custom / Equally',
      description:
          'Log spending with multiple payers and built-in math calculation. Split evenly among everyone or customize individual shares.',
      badge: 'Flexible Split',
      accentColor: Color(0xFFF59E0B),
    ),
    GuideFeatureItem(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Live Transparent Balance Sheet',
      description:
          'See real-time balance sheets and daily expense summaries. Track who paid what, who owes whom, and total tour costs.',
      badge: 'Balance Sheet',
      accentColor: Color(0xFF10B981),
    ),
    GuideFeatureItem(
      icon: Icons.forum_rounded,
      title: 'Chat in Both Online & Offline',
      description:
          'Coordinate seamlessly with companions. Send messages and reactions online via cloud, or offline nearby via Bluetooth mesh.',
      badge: 'Online & Mesh',
      accentColor: Color(0xFF14B8A6),
    ),
    GuideFeatureItem(
      icon: Icons.handshake_rounded,
      title: 'Export Chat & Settle Effortlessly',
      description:
          'Export complete chat history and expense receipts, then clear debts with minimum transactions and 1-tap payout accounts.',
      badge: '1-Tap Settle',
      accentColor: Color(0xFF8B5CF6),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar with Close Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.travel_explore_rounded,
                          color: AppColors.primaryTeal,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TourSplit',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.3,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                      size: 22,
                    ),
                    tooltip: 'Close Guide',
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),

                    // Guide Pill & Header
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primaryTeal.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 14,
                              color: AppColors.primaryTeal,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'WELCOME GUIDE',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Center(
                      child: Text(
                        'Split Costs, Keep Memories',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: isDark ? Colors.white : AppColors.lightText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Everything you need for transparent shared travel: instant tour setup, flexible expense splits, offline mesh chat, and effortless settlements.',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 13.5,
                            height: 1.45,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Feature Cards
                    ...features.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: item.accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: item.accentColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.lightText,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: item.accentColor
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            item.badge,
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: item.accentColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.description,
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 13,
                                        height: 1.4,
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
                        ),
                      )
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: 50 * index),
                            duration: 300.ms,
                          )
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          );
                    }),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // Bottom Sticky Action Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.lightBg,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
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
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Got It & Explore',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can revisit this guide anytime under Profile → Welcome Guide',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11.5,
                      color: isDark
                          ? AppColors.darkTextSecondary.withValues(alpha: 0.8)
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef WelcomeGuideScreen = FirstTimeGuideDialog;
