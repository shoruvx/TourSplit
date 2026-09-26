import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/tour_model.dart';
import 'member_avatar.dart';

/// Context-aware bottom navigation bar for the Home landing and All Tours screens
class HomeBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final int activeToursCount;
  final dynamic currentUser;
  final VoidCallback? onHomeTap;
  final VoidCallback? onToursTap;
  final VoidCallback? onProfileTap;

  const HomeBottomNavigationBar({
    super.key,
    required this.currentIndex,
    this.activeToursCount = 0,
    this.currentUser,
    this.onHomeTap,
    this.onToursTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.6)
                : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // 1. Home
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: currentIndex == 0,
                  onTap: onHomeTap ?? () {},
                ),
              ),

              // 2. My Tours
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.luggage_rounded,
                  label: 'My Tours',
                  isSelected: currentIndex == 1,
                  badgeText: activeToursCount > 0 ? '$activeToursCount' : null,
                  onTap: onToursTap ?? () {},
                ),
              ),

              // 3. Profile
              Expanded(
                child: _BottomProfileNavItem(
                  currentUser: currentUser,
                  isSelected: currentIndex == 2,
                  onTap: onProfileTap ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Context-aware bottom navigation bar for the active tour screen
class TourBottomNavigationBar extends StatelessWidget {
  final TourModel tour;
  final bool isAdmin;
  final dynamic currentUser;
  final int membersCount;
  final int currentIndex;
  final VoidCallback? onToursTap;
  final VoidCallback? onHomeTap;
  final VoidCallback? onDashboardTap;
  final VoidCallback? onMembersTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onProfileTap;

  const TourBottomNavigationBar({
    super.key,
    required this.tour,
    required this.isAdmin,
    required this.currentUser,
    required this.membersCount,
    this.currentIndex = 1,
    this.onToursTap,
    this.onHomeTap,
    this.onDashboardTap,
    this.onMembersTap,
    this.onSettingsTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.6)
                : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // 1. All Tours
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.luggage_rounded,
                  label: 'All Tours',
                  isSelected: currentIndex == 0,
                  onTap: onToursTap ?? onHomeTap ?? () {},
                ),
              ),

              // 2. Dashboard / Tour Home
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: currentIndex == 1,
                  onTap: onDashboardTap ?? () {},
                ),
              ),

              // 3. Members
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.people_alt_rounded,
                  label: 'Members',
                  isSelected: currentIndex == 2,
                  badgeText: membersCount > 0 ? '$membersCount' : null,
                  onTap: onMembersTap ?? () {},
                ),
              ),

              // 4. Settings (if admin)
              if (isAdmin)
                Expanded(
                  child: _BottomNavItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    isSelected: currentIndex == 3,
                    onTap: onSettingsTap ?? () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String? badgeText;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primaryTeal;
    final inactiveColor = isDark ? Colors.white60 : Colors.black54;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badgeText != null,
              label: badgeText != null
                  ? Text(
                      badgeText!,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
              backgroundColor: AppColors.primaryTeal,
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomProfileNavItem extends StatelessWidget {
  final dynamic currentUser;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomProfileNavItem({
    required this.currentUser,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primaryTeal;
    final inactiveColor = isDark ? Colors.white60 : Colors.black54;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? activeColor
                      : AppColors.primaryTeal.withValues(alpha: 0.6),
                  width: isSelected ? 2.0 : 1.5,
                ),
              ),
              child: MemberAvatar(
                initials: currentUser?.initials?.isNotEmpty == true
                    ? currentUser!.initials!
                    : 'U',
                photoUrl: currentUser?.photoUrl,
                userId: currentUser?.uid,
                radius: 11,
                enableTap: false,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Profile',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
