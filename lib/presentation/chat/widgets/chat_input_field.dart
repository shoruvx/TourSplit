import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/models/tour_model.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/tour_repository.dart';
import '../../../data/services/mesh_network_service.dart';
import '../../../data/services/user_cache_service.dart';

class ChatInputField extends ConsumerStatefulWidget {
  final String tourId;
  final String currentUserId;
  final ValueChanged<ChatMessage>? onMessageSent;
  final ChatMessage? replyingTo;
  final VoidCallback? onCancelReply;

  const ChatInputField({
    super.key,
    required this.tourId,
    required this.currentUserId,
    this.onMessageSent,
    this.replyingTo,
    this.onCancelReply,
  });

  @override
  ConsumerState<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends ConsumerState<ChatInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _showMentions = false;
  String _mentionQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final text = _controller.text;
      final hasNow = text.trim().isNotEmpty;
      if (hasNow != _hasText) {
        setState(() => _hasText = hasNow);
      }

      // Check if user is typing a mention
      final cursor = _controller.selection.baseOffset;
      if (cursor > 0) {
        final textBeforeCursor = text.substring(0, cursor);
        final lastAt = textBeforeCursor.lastIndexOf('@');
        if (lastAt != -1) {
          final query = textBeforeCursor.substring(lastAt + 1);
          // If query has no spaces, user is currently typing a mention handle
          if (!query.contains(' ') && query.length <= 25) {
            _mentionQuery = query.toLowerCase();
            if (!_showMentions) setState(() => _showMentions = true);
            return;
          }
        }
      }
      if (_showMentions) {
        setState(() {
          _showMentions = false;
          _mentionQuery = '';
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replyingTo != null && widget.replyingTo != oldWidget.replyingTo) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final id = const Uuid().v4();
    final replying = widget.replyingTo;
    final replyingAuthor = replying != null
        ? (UserCacheService.getUser(replying.authorId)?.displayName ??
            'Tour Member')
        : null;

    final message = ChatMessage(
      id: id,
      authorId: widget.currentUserId,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isDeleted: false,
      syncedToServer: false,
      tourId: widget.tourId,
      replyToId: replying?.id,
      replyToAuthor: replyingAuthor,
      replyToText: replying?.text,
    );

    _controller.clear();
    setState(() => _showMentions = false);
    widget.onCancelReply?.call();

    // 1. Save locally to Hive with tombstone check & rolling window
    await ref.read(chatRepositoryProvider).saveMessage(message);

    // 2. Broadcast via P2P Mesh if cluster is active
    final meshState = ref.read(meshNetworkServiceProvider);
    if (meshState.isMeshActive) {
      await ref
          .read(meshNetworkServiceProvider.notifier)
          .broadcastMessage(message);
    }

    widget.onMessageSent?.call(message);
  }

  void _insertMention(String handle) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor > 0) {
      final textBeforeCursor = text.substring(0, cursor);
      final lastAt = textBeforeCursor.lastIndexOf('@');
      if (lastAt != -1) {
        final newText =
            '${text.substring(0, lastAt)}@$handle ${text.substring(cursor)}';
        _controller.value = TextEditingValue(
          text: newText,
          selection:
              TextSelection.collapsed(offset: lastAt + handle.length + 2),
        );
      } else {
        _controller.text = '$text@$handle ';
      }
    } else {
      _controller.text = '$text@$handle ';
    }
    setState(() {
      _showMentions = false;
      _mentionQuery = '';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final replying = widget.replyingTo;
    final replyingAuthor = replying != null
        ? (UserCacheService.getUser(replying.authorId)?.displayName ??
            'Tour Member')
        : null;

    final membersAsync = ref.watch(tourMembersStreamProvider(widget.tourId));
    final members = membersAsync.value ?? [];
    final activeMembers = members
        .where((m) => !m.isLeft && m.userId != widget.currentUserId)
        .toList();

    final matchingMembers = activeMembers.where((m) {
      if (_mentionQuery.isEmpty) return true;
      final q = _mentionQuery.toLowerCase();
      final name = m.displayName.toLowerCase();
      final email = m.email.toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();

    final showEveryone = _mentionQuery.isEmpty ||
        'everyone'.contains(_mentionQuery.toLowerCase());
    final showAll = _mentionQuery.isEmpty ||
        'all'.contains(_mentionQuery.toLowerCase());

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : AppColors.lightBg,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick Mentions Row with Tour Members
            if (_showMentions)
              Container(
                height: 38,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (showEveryone)
                      _buildMentionChip(
                          'everyone', Icons.groups_rounded, isDark),
                    if (showAll)
                      _buildMentionChip(
                          'all', Icons.people_alt_rounded, isDark),
                    ...matchingMembers.map((member) {
                      final handle = member.displayName
                          .trim()
                          .replaceAll(RegExp(r'\s+'), '_');
                      return _buildMemberMentionChip(member, handle, isDark);
                    }),
                  ],
                ),
              ),

            // Reply Quote Preview Banner
            if (replying != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: AppColors.primaryTeal, width: 3.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        color: AppColors.primaryTeal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Replying to $replyingAuthor',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryTeal,
                            ),
                          ),
                          Text(
                            replying.text ?? '',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: isDark ? Colors.white60 : Colors.black54,
                      onPressed: widget.onCancelReply,
                    ),
                  ],
                ),
              ),

            // Single Clean Typing Box & Send Button (One box only)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      color: isDark ? Colors.white : AppColors.lightText,
                    ),
                    decoration: InputDecoration(
                      hintText: replying != null
                          ? 'Reply to $replyingAuthor...'
                          : 'Type a message (or @ to mention)...',
                      hintStyle: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      filled: true,
                      fillColor:
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _hasText
                        ? AppColors.primaryTeal
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05)),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, size: 20),
                    color: _hasText
                        ? Colors.white
                        : (isDark ? Colors.white38 : Colors.black38),
                    onPressed: _hasText ? _handleSend : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionChip(String name, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: AppColors.primaryTeal),
        label: Text(
          '@$name',
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryTeal,
          ),
        ),
        backgroundColor:
            isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        side: BorderSide(
          color: AppColors.primaryTeal.withValues(alpha: 0.4),
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: () => _insertMention(name),
      ),
    );
  }

  Widget _buildMemberMentionChip(
      TourMemberModel member, String handle, bool isDark) {
    final photoUrl = member.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: CircleAvatar(
          radius: 11,
          backgroundColor: AppColors.primaryTeal,
          backgroundImage:
              hasPhoto ? CachedNetworkImageProvider(photoUrl) : null,
          child: !hasPhoto
              ? Text(
                  member.initials,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
        label: Text(
          '@${member.displayName}',
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryTeal,
          ),
        ),
        backgroundColor:
            isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        side: BorderSide(
          color: AppColors.primaryTeal.withValues(alpha: 0.4),
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: () => _insertMention(handle),
      ),
    );
  }
}
