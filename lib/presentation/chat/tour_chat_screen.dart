import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bluetooth_helper.dart';
import '../../core/utils/mesh_permission_helper.dart';
import '../../data/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/chat_active_tracker.dart';
import '../../data/services/chat_sync_service.dart';
import '../../data/services/mesh_network_service.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_field.dart';
import 'widgets/chat_reaction_bar.dart';
import 'widgets/mesh_mode_toggle.dart';

class TourChatScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;

  const TourChatScreen({
    super.key,
    required this.tourId,
    required this.tourName,
  });

  @override
  ConsumerState<TourChatScreen> createState() => _TourChatScreenState();
}

class _TourChatScreenState extends ConsumerState<TourChatScreen> {
  final ScrollController _scrollController = ScrollController();
  ChatMessage? _replyingToMessage;

  @override
  void initState() {
    super.initState();
    ChatActiveTracker.activeTourChatId = widget.tourId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mark tour as read when entering chat screen
      ref.read(chatRepositoryProvider).markTourAsRead(widget.tourId);
      // Inform sync service of the active tour for delta syncing
      ref
          .read(chatSyncServiceProvider)
          .setActiveTour(widget.tourId, tourName: widget.tourName);
      // Restore previously chosen connection mode or detect network
      _restoreSavedOrDetectConnectionMode();
    });
  }

  Future<void> _saveConnectionMode(String mode) async {
    try {
      final box = Hive.isBoxOpen('app_preferences')
          ? Hive.box('app_preferences')
          : await Hive.openBox('app_preferences');
      await box.put('last_chat_connection_mode_${widget.tourId}', mode);
      await box.put('last_chat_connection_mode', mode);
    } catch (e) {
      debugPrint('[TOUR_CHAT] Error saving connection mode: $e');
    }
  }

  Future<void> _restoreSavedOrDetectConnectionMode() async {
    try {
      final box = Hive.isBoxOpen('app_preferences')
          ? Hive.box('app_preferences')
          : await Hive.openBox('app_preferences');

      final savedMode =
          box.get('last_chat_connection_mode_${widget.tourId}') as String? ??
              box.get('last_chat_connection_mode') as String?;

      if (savedMode == 'mesh') {
        if (!ref.read(meshNetworkServiceProvider).isMeshActive) {
          await _toggleMesh(true, isAutoRestore: true);
        }
        return;
      } else if (savedMode == 'cloud') {
        if (ref.read(meshNetworkServiceProvider).isMeshActive) {
          await _toggleMesh(false, isAutoRestore: true);
        }
        return;
      }

      // No saved preference found yet; auto-detect network as default
      await _detectInitialNetworkMode();
    } catch (e) {
      debugPrint('[TOUR_CHAT] Error restoring connection mode: $e');
      await _detectInitialNetworkMode();
    }
  }

  Future<void> _detectInitialNetworkMode() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      bool hasRealInternet = false;
      if (hasInterface) {
        try {
          final lookup = await InternetAddress.lookup('dns.google')
              .timeout(const Duration(milliseconds: 1500));
          hasRealInternet =
              lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
        } catch (_) {
          hasRealInternet = false;
        }
      }
      if (mounted) {
        if (hasRealInternet) {
          if (ref.read(meshNetworkServiceProvider).isMeshActive) {
            _toggleMesh(false, isAutoRestore: true);
          }
        } else {
          // If no internet connection when launching chat, default to offline mesh
          if (!ref.read(meshNetworkServiceProvider).isMeshActive) {
            _toggleMesh(true, isAutoRestore: true);
          }
        }
      }
    } catch (e) {
      debugPrint('[TOUR_CHAT] Error detecting initial network: $e');
    }
  }

  @override
  void dispose() {
    if (ChatActiveTracker.activeTourChatId == widget.tourId) {
      ChatActiveTracker.activeTourChatId = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _showBluetoothRequiredDialog() async {
    if (!mounted) return false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.bluetooth_searching_rounded,
                color: AppColors.primaryTeal, size: 28),
            SizedBox(width: 10),
            Text(
              'Bluetooth Required',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'Offline P2P Mesh chat requires Bluetooth to discover and communicate with nearby tour members.\n\nPlease turn on Bluetooth to connect offline.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Use Internet Mode',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.bluetooth_rounded, size: 18),
            label: const Text('Turn On Bluetooth'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _toggleMesh(bool value, {bool isAutoRestore = false}) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    final meshNotifier = ref.read(meshNetworkServiceProvider.notifier);
    if (value) {
      // 1. Strictly verify Bluetooth is turned on
      bool isBtOn = await BluetoothHelper.isBluetoothEnabled();
      if (!isBtOn) {
        await BluetoothHelper.requestEnableBluetooth();
        isBtOn = await BluetoothHelper.waitForBluetoothEnabled(
          timeout: const Duration(seconds: 8),
        );
        if (!isBtOn) {
          if (!mounted) return;
          final retry = await _showBluetoothRequiredDialog();
          if (retry) {
            await BluetoothHelper.requestEnableBluetooth();
            isBtOn = await BluetoothHelper.waitForBluetoothEnabled(
              timeout: const Duration(seconds: 10),
            );
          }
          if (!isBtOn) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Bluetooth was not enabled. Switched to Internet mode.'),
                  backgroundColor: AppColors.warning,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            await _saveConnectionMode('cloud');
            return;
          }
        }
      }

      // 2. Prompt user for permissions (Bluetooth, Location, Notification)
      if (!mounted) return;
      final hasPermissions =
          await MeshPermissionHelper.requestMeshPermissions(context);
      if (!hasPermissions) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Bluetooth, Nearby Devices, Location, and Notification permissions are required for offline P2P mesh.'),
              backgroundColor: AppColors.danger,
              duration: Duration(seconds: 3),
            ),
          );
        }
        await _saveConnectionMode('cloud');
        return;
      }

      // 3. Small pause for radio stack to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      final success = await meshNotifier.startMesh(
        tourId: widget.tourId,
        userId: user.uid,
        displayName: user.displayName,
      );

      if (mounted) {
        if (success) {
          await _saveConnectionMode('mesh');
          if (!mounted) return;
          if (!isAutoRestore) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Offline mesh active. Searching for nearby tour members...'),
                backgroundColor: AppColors.primaryTeal,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          await _saveConnectionMode('cloud');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not start offline mesh. Please ensure Bluetooth and Location (GPS) are turned on.'),
              backgroundColor: AppColors.danger,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      await meshNotifier.stopMesh();
      await _saveConnectionMode('cloud');
      if (!mounted) return;
      if (!isAutoRestore) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switched to Internet & Cloud Mode'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleToggleReaction(ChatMessage message, String emoji) async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    await ref.read(chatRepositoryProvider).toggleReaction(
          tourId: widget.tourId,
          messageId: message.id,
          userId: currentUser.uid,
          emoji: emoji,
        );

    // Sync upstream immediately
    ref.read(chatSyncServiceProvider).syncUpstream(tourId: widget.tourId);
  }

  void _showMessageActions(ChatMessage message) {
    final currentUser = ref.read(currentUserProvider).value;
    final currentUserId = currentUser?.uid ?? '';
    final isAuthor = currentUser != null && currentUser.uid == message.authorId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Floating Messenger Reaction Bar
              ChatReactionBar(
                currentReaction: message.userReaction(currentUserId),
                onSelectEmoji: (emoji) {
                  Navigator.of(ctx).pop();
                  _handleToggleReaction(message, emoji);
                },
              ),
              const SizedBox(height: 8),
              if (message.text != null && message.text!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: AppColors.primaryTeal),
                  title: const Text(
                    'Copy Text',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: message.text!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: AppColors.primaryTeal),
                title: const Text(
                  'Reply',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Quote this message in your reply',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _replyingToMessage = message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Removes this message from your device only',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(chatRepositoryProvider)
                      .deleteForMe(widget.tourId, message.id);
                },
              ),
              if (isAuthor)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                  title: const Text(
                    'Delete for everyone',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                  subtitle: Text(
                    'Erases this message for all tour members like Telegram',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    // 1. Delete locally with tombstone flag
                    await ref
                        .read(chatRepositoryProvider)
                        .deleteForEveryone(widget.tourId, message.id);

                    // 2. Broadcast tombstone to P2P mesh peers
                    final tombstone = message.toTombstone();
                    await ref
                        .read(meshNetworkServiceProvider.notifier)
                        .broadcastMessage(tombstone);

                    // 3. Trigger upstream sync to erase on Firestore
                    ref
                        .read(chatSyncServiceProvider)
                        .triggerSync(tourId: widget.tourId);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentUser = ref.watch(currentUserProvider).value;
    final currentUserId = currentUser?.uid ?? '';

    final meshState = ref.watch(meshNetworkServiceProvider);
    final messagesAsync = ref.watch(tourMessagesStreamProvider(widget.tourId));

    final tourAsync = ref.watch(tourStreamProvider(widget.tourId));
    final effectiveTourName = tourAsync.value?.name ??
        (widget.tourName.isNotEmpty ? widget.tourName : 'Tour');
    final chatTitle = effectiveTourName.toLowerCase().endsWith('chat')
        ? effectiveTourName
        : '$effectiveTourName Chat';

    return Scaffold(
      appBar: AppBar(
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              chatTitle,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: meshState.isMeshActive ? AppColors.positive : Colors.grey,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  meshState.isMeshActive
                      ? 'Offline Mode: ${meshState.connectedPeersCount} peer(s)'
                      : 'Internet & Cloud Mode',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: MeshModeToggle(
                isMeshActive: meshState.isMeshActive,
                peerCount: meshState.connectedPeersCount,
                onToggle: _toggleMesh,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Mesh Active Status Banner
          if (meshState.isMeshActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.primaryTeal.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth_searching_rounded,
                    size: 16,
                    color: AppColors.primaryTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meshState.statusMessage ?? 'Mesh cluster active',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 12,
                        color: AppColors.primaryTeal,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Phase 6.2 Body: ListView.builder (reverse: true) strictly consuming local Hive stream
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Error loading chat: $err'),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 48,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Send a message to coordinate with tour members. Messages work offline and sync over P2P mesh & cloud!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // reverse: true so newest messages start at bottom
                  itemCount: messages.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isCurrentUser = message.authorId == currentUserId;
                    return ChatBubble(
                      message: message,
                      isCurrentUser: isCurrentUser,
                      currentUserId: currentUserId,
                      onLongPress: () => _showMessageActions(message),
                      onReact: (emoji) => _handleToggleReaction(message, emoji),
                      onDelete: () => _showMessageActions(message),
                      onReply: () =>
                          setState(() => _replyingToMessage = message),
                    );
                  },
                );
              },
            ),
          ),

          // Input field with reply and mention support
          ChatInputField(
            tourId: widget.tourId,
            currentUserId: currentUserId,
            replyingTo: _replyingToMessage,
            onCancelReply: () => setState(() => _replyingToMessage = null),
            onMessageSent: (_) {
              // Trigger background sync when a message is sent
              ref
                  .read(chatSyncServiceProvider)
                  .triggerSync(tourId: widget.tourId);
            },
          ),
        ],
      ),
    );
  }
}
