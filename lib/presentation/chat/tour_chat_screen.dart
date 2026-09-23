import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bluetooth_helper.dart';
import '../../core/utils/mesh_permission_helper.dart';
import '../../data/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/chat_active_tracker.dart';
import '../../data/services/chat_sync_service.dart';
import '../../data/services/mesh_network_service.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_field.dart';
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
      ref.read(chatSyncServiceProvider).setActiveTour(widget.tourId);
      // Initial network detection: default to Internet mode when online, Offline otherwise
      _detectInitialNetworkMode();
    });
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
            _toggleMesh(false);
          }
        } else {
          // If no internet connection when launching chat, default to offline mesh
          if (!ref.read(meshNetworkServiceProvider).isMeshActive) {
            _toggleMesh(true);
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

  Future<void> _toggleMesh(bool value) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    final meshNotifier = ref.read(meshNetworkServiceProvider.notifier);
    if (value) {
      // 1. Prompt user to turn on Bluetooth automatically with native system dialog ("Allow")
      final isBtOn = await BluetoothHelper.isBluetoothEnabled();
      if (!isBtOn) {
        await BluetoothHelper.requestEnableBluetooth();
        // Wait until Bluetooth is enabled or user dismisses dialog (up to 12s)
        final turnedOn = await BluetoothHelper.waitForBluetoothEnabled(
          timeout: const Duration(seconds: 12),
        );
        if (!turnedOn) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth is required to use Offline mode.'),
                backgroundColor: AppColors.warning,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      // 2. Prompt user for permissions if needed
      if (!mounted) return;
      final hasPermissions =
          await MeshPermissionHelper.requestMeshPermissions(context);
      if (!hasPermissions) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Bluetooth, Nearby Devices, and Location permissions are required for offline P2P mesh.'),
              backgroundColor: AppColors.danger,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Small pause for radio stack to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      final success = await meshNotifier.startMesh(
        tourId: widget.tourId,
        userId: user.uid,
        displayName: user.displayName,
      );
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not start offline mesh. Please ensure Bluetooth and Location (GPS) are turned on.'),
            backgroundColor: AppColors.danger,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      await meshNotifier.stopMesh();
    }
  }

  void _confirmDeleteMessage(ChatMessage message) {
    final currentUser = ref.read(currentUserProvider).value;
    final isAuthor = currentUser != null && currentUser.uid == message.authorId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

    return Scaffold(
      appBar: AppBar(
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.tourName,
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
                      onDelete: () => _confirmDeleteMessage(message),
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
