import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class MemberAvatar extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final double radius;
  final Color? backgroundColor;

  const MemberAvatar({
    super.key,
    required this.initials,
    this.photoUrl,
    this.radius = 20,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(photoUrl!),
        backgroundColor: backgroundColor ?? AppColors.primaryBlue.withOpacity(0.2),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppColors.primaryBlue.withOpacity(0.15),
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
}

/// A row of overlapping member avatars
class MemberAvatarStack extends StatelessWidget {
  final List<String> initials;
  final List<String?> photoUrls;
  final double radius;
  final int maxVisible;

  const MemberAvatarStack({
    super.key,
    required this.initials,
    required this.photoUrls,
    this.radius = 16,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    final visible = initials.take(maxVisible).toList();
    final overflow = initials.length - maxVisible;

    return SizedBox(
      height: radius * 2,
      width: visible.length * (radius * 1.4) + (overflow > 0 ? radius * 1.6 : 0),
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
