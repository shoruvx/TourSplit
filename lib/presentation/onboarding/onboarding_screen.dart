import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/bluetooth_helper.dart';
import '../../core/utils/mesh_permission_helper.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  bool _isRequestingPermissions = false;
  bool _bluetoothGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissionStatuses();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPermissionStatuses() async {
    try {
      final loc = await Permission.locationWhenInUse.isGranted ||
          await Permission.location.isGranted;
      final notif = await Permission.notification.isGranted;
      final bt = await BluetoothHelper.isBluetoothEnabled();

      if (mounted) {
        setState(() {
          _locationGranted = loc;
          _notificationGranted = notif;
          _bluetoothGranted = bt;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestPermissionsAndContinue() async {
    setState(() => _isRequestingPermissions = true);
    HapticFeedback.mediumImpact();

    try {
      // 1. Ensure Bluetooth radio is enabled
      bool isBtOn = await BluetoothHelper.isBluetoothEnabled();
      if (!isBtOn) {
        await BluetoothHelper.requestEnableBluetooth();
        isBtOn = await BluetoothHelper.waitForBluetoothEnabled(
          timeout: const Duration(seconds: 8),
        );
      }

      // 2. Request OS Permissions (Nearby/Bluetooth, Location, Notification)
      if (mounted) {
        await MeshPermissionHelper.requestMeshPermissions(context);
      }

      await _checkCurrentPermissionStatuses();

      // Small delay for smooth visual confirmation
      await Future.delayed(const Duration(milliseconds: 350));

      await _completeOnboarding();
    } catch (e) {
      debugPrint('[ONBOARDING] Error in permission request: $e');
      await _completeOnboarding();
    } finally {
      if (mounted) setState(() => _isRequestingPermissions = false);
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final box = Hive.isBoxOpen('app_preferences')
          ? Hive.box('app_preferences')
          : await Hive.openBox('app_preferences');
      await box.put('has_completed_onboarding_guide', true);
      await box.put('has_seen_first_time_guide', true);
    } catch (e) {
      debugPrint('[ONBOARDING] Error saving preference: $e');
    }

    if (!mounted) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _requestPermissionsAndContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal.withValues(alpha: 0.15),
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
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _completeOnboarding();
                      },
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Page View
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  if (index == 2) {
                    _checkCurrentPermissionStatuses();
                  }
                },
                children: [
                  _buildSplitCostsSlide(isDark),
                  _buildOfflineMeshSlide(isDark),
                  _buildPermissionsAssuranceSlide(isDark),
                ],
              ),
            ),

            // Bottom Navigation & Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final isSelected = _currentPage == index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6,
                        width: isSelected ? 24 : 6,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryTeal
                              : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isRequestingPermissions
                          ? null
                          : (_currentPage == 2
                              ? _requestPermissionsAndContinue
                              : _nextPage),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      child: _isRequestingPermissions
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _currentPage == 2
                                  ? 'Grant Permissions & Start'
                                  : 'Continue',
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  if (_currentPage == 2) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isRequestingPermissions ? null : _completeOnboarding,
                      child: Text(
                        'Continue without permissions',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitCostsSlide(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryTeal.withValues(alpha: 0.2),
                  AppColors.primaryBlue.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.pie_chart_rounded,
                size: 56,
                color: AppColors.primaryTeal,
              ),
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 32),
          Text(
            'Split Costs, Keep Memories',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : AppColors.lightText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Keep shared trip expenses completely transparent. Record who paid, customize split shares, and simplify settlements with minimum transactions.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 15,
              height: 1.45,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildFeatureBadge(
            icon: Icons.check_circle_outline_rounded,
            title: 'Multi-Currency & Live Reports',
            description: 'Automatic conversions and exportable PDF summaries.',
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          _buildFeatureBadge(
            icon: Icons.group_outlined,
            title: 'Effortless Group Invitations',
            description: 'Join in seconds via 6-digit code or QR scanning.',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineMeshSlide(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.positive.withValues(alpha: 0.2),
                  AppColors.primaryTeal.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: AppColors.primaryTeal,
              ),
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 32),
          Text(
            'Offline Freedom & P2P Chat',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : AppColors.lightText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Create tours and record expenses completely offline. Chat and react with nearby companions over peer-to-peer Bluetooth without internet.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 15,
              height: 1.45,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildFeatureBadge(
            icon: Icons.cloud_off_rounded,
            title: 'Pure Offline Host Mode',
            description:
                'Host tours and record expenses with instant local caching.',
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          _buildFeatureBadge(
            icon: Icons.forum_rounded,
            title: 'Peer-to-Peer Nearby Chat',
            description:
                'Coordinate and react with nearby companions off the grid.',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsAssuranceSlide(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.positive.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.positive.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 16, color: AppColors.positive),
                  SizedBox(width: 6),
                  Text(
                    '100% Privacy Respected',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.positive,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Permissions & Privacy Assurance',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TourSplit needs the following system permissions to discover peers and keep your tour in sync offline:',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13.5,
              height: 1.4,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Permission Cards
          _buildPermissionCard(
            icon: Icons.bluetooth_searching_rounded,
            title: 'Bluetooth & Nearby Devices',
            description:
                'Discovers and pairs with companions nearby. Operates directly device-to-device without internet.',
            isGranted: _bluetoothGranted,
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          _buildPermissionCard(
            icon: Icons.location_on_outlined,
            title: 'Location Access (Beaconing)',
            description:
                'Required by Android OS for Bluetooth beacon discovery. TourSplit NEVER tracks, stores, or uploads your GPS location.',
            isGranted: _locationGranted,
            isDark: isDark,
            isLocationAssurance: true,
          ),
          const SizedBox(height: 12),

          _buildPermissionCard(
            icon: Icons.notifications_active_outlined,
            title: 'Background Sync Notification',
            description:
                'Keeps your P2P connection alive seamlessly when you leave the app, snap photos, or lock your screen.',
            isGranted: _notificationGranted,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryTeal, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13,
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
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required bool isDark,
    bool isLocationAssurance = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? AppColors.positive.withValues(alpha: 0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isGranted ? AppColors.positive : AppColors.primaryTeal)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isGranted ? AppColors.positive : AppColors.primaryTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.lightText,
                        ),
                      ),
                    ),
                    if (isGranted)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.positive,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12.5,
                    height: 1.35,
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
    );
  }
}
