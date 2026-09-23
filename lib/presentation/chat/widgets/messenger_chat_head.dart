import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/chat_repository.dart';

/// A Messenger-style floating chat button matched to the app theme.
/// - Background matches the UI background (darkish slate #0F172A in dark mode, light in light mode).
/// - Gradient ring and chat icon themed with app's Teal + White.
/// - Anchored in the bottom right corner directly above the bottom bar.
class MessengerChatHead extends ConsumerWidget {
  final String tourId;
  final String tourName;
  final String userId;

  const MessengerChatHead({
    super.key,
    required this.tourId,
    required this.tourName,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final unreadAsync = ref.watch(
      tourUnreadCountProvider((tourId: tourId, currentUserId: userId)),
    );
    final unreadCount =
        unreadAsync.maybeWhen(data: (count) => count, orElse: () => 0);

    const double buttonSize = 58.0;

    return Positioned(
      bottom: 16,
      right: 18,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push(
            '/tour/chat/$tourId?name=${Uri.encodeComponent(tourName)}',
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Outer Teal gradient ring container
            Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF2DD4BF), // Mint teal highlight
                    AppColors.primaryTeal, // App primary teal
                    Color(0xFF0D9488), // Deep teal
                    AppColors.primaryTealDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryTeal.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2.5), // Teal ring thickness
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Matches the exact darkish UI background of the app
                  color: isDark ? AppColors.darkBg : theme.scaffoldBackgroundColor,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: unreadCount > 0
                        ? _DynamicCountIcon(
                            key: ValueKey('count_$unreadCount'),
                            count: unreadCount,
                          )
                        : const _TealWhiteChatIcon(
                            key: ValueKey('default_chat_icon'),
                          ),
                  ),
                ),
              ),
            ),

            // Top-right Red Unread Badge (matching Messenger "Chats 2" badge)
            if (unreadCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30), // Messenger red badge
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? AppColors.darkBg : Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic message count icon displayed at the center of the chat button (Teal + White)
class _DynamicCountIcon extends StatelessWidget {
  final int count;

  const _DynamicCountIcon({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              color: AppColors.primaryTeal,
              size: 32,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  color: Colors.white,
                  fontSize: count > 99 ? 10 : 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Default chat icon combining vibrant Teal with crisp White accents
class _TealWhiteChatIcon extends StatelessWidget {
  const _TealWhiteChatIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_rounded,
            color: AppColors.primaryTeal,
            size: 29,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2.5),
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2.5),
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
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
