import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
    context.go('/home');
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'TourSplit',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.primaryTeal,
                      height: 1.1,
                    ),
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
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
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
                  ),
                  if (_currentPage == 2) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isRequestingPermissions ? null : _completeOnboarding,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Continue without permissions',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12.5,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
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
    return Align(
      alignment: const Alignment(0.0, -0.35),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Welcome to TourSplit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : AppColors.lightText,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildFeatureBadge(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Create & Join with QR',
              description:
                  'Start trips in seconds or join friends with a quick QR scan.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Invite Friends',
              description:
                  'Share a simple 6-digit tour code or show your QR code.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.receipt_long_rounded,
              title: 'Add Expenses',
              description:
                  'Record trip expenses quickly and keep all your spending organized.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.call_split_rounded,
              title: 'Equal & Custom Split',
              description:
                  'Split costs equally or choose custom shares for each person.',
              isDark: isDark,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineMeshSlide(bool isDark) {
    return Align(
      alignment: const Alignment(0.0, -0.35),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Offline Chat & Settlements',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : AppColors.lightText,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildFeatureBadge(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Live Balance Sheet',
              description:
                  'Real-time summaries showing who paid and who owes what.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.forum_rounded,
              title: 'Online & Offline Chat',
              description:
                  'Chat with your travel group online or nearby without internet.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.handshake_rounded,
              title: 'Export & Settle Up',
              description:
                  'Download tour summaries and settle balances with friends easily.',
              isDark: isDark,
            ),
            _buildFeatureBadge(
              icon: Icons.cloud_off_rounded,
              title: 'Offline Trip Mode',
              description:
                  'Record expenses and manage trips even without internet.',
              isDark: isDark,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsAssuranceSlide(bool isDark) {
    return Align(
      alignment: const Alignment(0.0, -0.35),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Permissions & Privacy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : AppColors.lightText,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildPermissionCard(
              icon: Icons.bluetooth_searching_rounded,
              title: 'Bluetooth & Nearby Devices',
              description:
                  'Connect and chat with nearby friends without mobile data.',
              isGranted: _bluetoothGranted,
              isDark: isDark,
            ),
            _buildPermissionCard(
              icon: Icons.location_on_outlined,
              title: 'Nearby Device Search',
              description:
                  'Needed by Android to discover nearby friends; your location is never tracked.',
              isGranted: _locationGranted,
              isDark: isDark,
            ),
            _buildPermissionCard(
              icon: Icons.notifications_active_outlined,
              title: 'Notifications',
              description:
                  'Get updates when expenses are added or when friends send messages.',
              isGranted: _notificationGranted,
              isDark: isDark,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBadge({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
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
            child: Icon(icon, color: AppColors.primaryTeal, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.lightText,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
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
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: (isGranted ? AppColors.positive : AppColors.primaryTeal)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: isGranted ? AppColors.positive : AppColors.primaryTeal,
            ),
          ),
          const SizedBox(width: 16),
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
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.lightText,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (isGranted)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.positive,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
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
