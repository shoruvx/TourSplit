import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/widgets/messenger_chat_head.dart';

export '../chat/widgets/messenger_chat_head.dart';

/// Floating Messenger chat head for Tour Dashboard.
/// Features draggable placement, higher screen offset, and dynamic message count icon.
class TourDashboardChatFab extends ConsumerWidget {
  final String tourId;
  final String tourName;
  final String userId;

  const TourDashboardChatFab({
    super.key,
    required this.tourId,
    required this.tourName,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MessengerChatHead(
      tourId: tourId,
      tourName: tourName,
      userId: userId,
    );
  }
}

