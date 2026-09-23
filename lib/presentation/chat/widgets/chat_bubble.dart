import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/services/user_cache_service.dart';
import '../../widgets/member_avatar.dart';

class ChatBubble extends ConsumerWidget {
  final ChatMessage message;
  final bool isCurrentUser;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.onDelete,
    this.onReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Erase completely like Telegram: never show "This message was deleted"
    if (message.isDeleted) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Relational lookup strictly from local Hive UserBox (Zero Firestore reads)
    final cachedAuthor = ref.watch(userBoxProvider(message.authorId));
    final authorName = cachedAuthor?.displayName ?? 'Member';

    final timeString = DateFormat('h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(message.createdAt),
    );

    // Primary Colors
    final userBubbleColor = AppColors.primaryTeal;
    final otherBubbleColor =
        isDark ? const Color(0xFF263345) : const Color(0xFFE2E8F0);

    final textColor = isCurrentUser
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF0F172A));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            MemberAvatar(
              initials: cachedAuthor?.initials ?? '?',
              photoUrl: cachedAuthor?.photoUrl,
              radius: 14,
              enableTap: false,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onDelete,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.76,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isCurrentUser ? userBubbleColor : otherBubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isCurrentUser ? 16 : 4),
                    bottomRight: Radius.circular(isCurrentUser ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isCurrentUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Author label for other members in group chat
                    if (!isCurrentUser) ...[
                      Text(
                        authorName,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.primaryTeal
                              : const Color(0xFF00796B),
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],

                    // Quoted replied-to message snippet
                    if (message.replyToText != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCurrentUser
                              ? Colors.black.withValues(alpha: 0.15)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border(
                            left: BorderSide(
                              color: isCurrentUser
                                  ? Colors.white70
                                  : AppColors.primaryTeal,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.replyToAuthor ?? 'Tour Member',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isCurrentUser
                                    ? Colors.white
                                    : AppColors.primaryTeal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              message.replyToText!,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11.5,
                                color: isCurrentUser
                                    ? Colors.white70
                                    : (isDark ? Colors.white60 : Colors.black54),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Message Body with Mentions highlight
                    _buildMessageRichText(
                      message.text ?? '',
                      textColor,
                      isCurrentUser,
                    ),

                    const SizedBox(height: 4),

                    // Footer: Timestamp & Sync Indicator
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeString,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 10,
                            color: isCurrentUser
                                ? Colors.white.withValues(alpha: 0.75)
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.syncedToServer
                                ? Icons.done_all_rounded
                                : Icons.access_time_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Parses text and highlights @mentions like Telegram/Slack
  Widget _buildMessageRichText(
    String text,
    Color defaultColor,
    bool isCurrentUser,
  ) {
    if (!text.contains('@')) {
      return Text(
        text,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 14.5,
          height: 1.25,
          color: defaultColor,
        ),
      );
    }

    final mentionRegex = RegExp(r'(@[\w_\.\-]+)');
    final matches = mentionRegex.allMatches(text);
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 14.5,
            height: 1.25,
            color: defaultColor,
          ),
        ));
      }

      final mentionText = match.group(0)!;
      spans.add(TextSpan(
        text: mentionText,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: isCurrentUser ? Colors.amber.shade200 : AppColors.primaryTeal,
        ),
      ));

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 14.5,
          height: 1.25,
          color: defaultColor,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}
