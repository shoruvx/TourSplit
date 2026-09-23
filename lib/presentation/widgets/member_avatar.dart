import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/auth_service.dart';

ImageProvider? _resolveImageProvider(String? photoUrl) {
  if (photoUrl == null || photoUrl.isEmpty) return null;
  if (photoUrl.startsWith('data:image')) {
    try {
      final base64Part = photoUrl.split(',').last;
      return MemoryImage(base64Decode(base64Part));
    } catch (_) {
      return null;
    }
  }
  return CachedNetworkImageProvider(photoUrl);
}

class MemberAvatar extends ConsumerWidget {
  final String initials;
  final String? photoUrl;
  final double radius;
  final Color? backgroundColor;
  final String? userId;
  final TourMemberModel? tourMember;
  final VoidCallback? onTap;
  final bool enableTap;

  const MemberAvatar({
    super.key,
    required this.initials,
    this.photoUrl,
    this.radius = 20,
    this.backgroundColor,
    this.userId,
    this.tourMember,
    this.onTap,
    this.enableTap = true,
  });

  void _handleDefaultTap(BuildContext context, String targetUid) {
    HapticFeedback.lightImpact();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == currentUid) {
      context.push('/profile');
    } else {
      context.push('/member/$targetUid', extra: tourMember);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetUid = userId ?? tourMember?.userId;
    final currentUser = ref.watch(currentUserProvider).value;

    String? effectivePhotoUrl = photoUrl;

    // 1. If target is the logged-in user, always prioritize the live currentUser photoUrl
    if (targetUid != null && currentUser != null && targetUid == currentUser.uid) {
      if (currentUser.photoUrl != null && currentUser.photoUrl!.isNotEmpty) {
        effectivePhotoUrl = currentUser.photoUrl;
      }
    } else if ((effectivePhotoUrl == null || effectivePhotoUrl.isEmpty) &&
        targetUid != null &&
        targetUid.isNotEmpty &&
        !(tourMember?.isOffline ?? false)) {
      // 2. If target is another online member whose record lacked photoUrl, check their live user profile
      final liveProfile = ref.watch(userProfileProvider(targetUid)).value;
      if (liveProfile?.photoUrl != null && liveProfile!.photoUrl!.isNotEmpty) {
        effectivePhotoUrl = liveProfile.photoUrl;
      }
    }

    final imageProvider = _resolveImageProvider(effectivePhotoUrl);
    final Widget avatarCore;
    if (imageProvider != null) {
      avatarCore = CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor:
            backgroundColor ?? AppColors.primaryBlue.withValues(alpha: 0.2),
      );
    } else {
      avatarCore = CircleAvatar(
        radius: radius,
        backgroundColor:
            backgroundColor ?? AppColors.primaryBlue.withValues(alpha: 0.15),
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: radius * 0.65,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
          ),
        ),
      );
    }

    final isClickable = enableTap && (onTap != null || targetUid != null);

    if (isClickable) {
      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap ?? () => _handleDefaultTap(context, targetUid!),
          child: avatarCore,
        ),
      );
    }

    return avatarCore;
  }
}

class MemberAvatarStack extends StatelessWidget {
  final List<String> initials;
  final List<String?> photoUrls;
  final List<String>? userIds;
  final double radius;
  final int maxVisible;

  const MemberAvatarStack({
    super.key,
    required this.initials,
    required this.photoUrls,
    this.userIds,
    this.radius = 16,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    final visible = initials.take(maxVisible).toList();
    final overflow = initials.length - maxVisible;

    return SizedBox(
      height: radius * 2,
      width:
          visible.length * (radius * 1.4) + (overflow > 0 ? radius * 1.6 : 0),
      child: Stack(
        children: [
          ...List.generate(visible.length, (i) {
            return Positioned(
              left: i * (radius * 1.4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: MemberAvatar(
                  initials: visible[i],
                  photoUrl: i < photoUrls.length ? photoUrls[i] : null,
                  userId: userIds != null && i < userIds!.length ? userIds![i] : null,
                  radius: radius,
                ),
              ),
            );
          }),
          if (overflow > 0)
            Positioned(
              left: visible.length * (radius * 1.4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: radius,
                  backgroundColor: AppColors.darkBorder,
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: radius * 0.6,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
