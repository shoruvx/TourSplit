import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'chat_active_tracker.dart';
import 'notification_service.dart';
import 'user_cache_service.dart';

final chatSyncServiceProvider = Provider<ChatSyncService>((ref) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final service = ChatSyncService(
    chatRepo: chatRepo,
    firestore: FirebaseFirestore.instance,
    connectivity: Connectivity(),
  );
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

class ChatSyncService {
  final ChatRepository _chatRepo;
  final FirebaseFirestore _firestore;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<QuerySnapshot>? _liveChatsSub;
  bool _isSyncing = false;
  bool _hasPendingSync = false;
  String? _activeTourId;
  String? _activeTourName;

  ChatSyncService({
    required ChatRepository chatRepo,
    required FirebaseFirestore firestore,
    required Connectivity connectivity,
  })  : _chatRepo = chatRepo,
        _firestore = firestore,
        _connectivity = connectivity;

  void initialize() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection && _activeTourId != null) {
        triggerSync(tourId: _activeTourId);
      }
    });
  }

  final Map<String, StreamSubscription<QuerySnapshot>> _liveTourSubs = {};
  final Map<String, String> _tourNames = {};

  void setActiveTour(String? tourId, {String? tourName}) {
    if (tourId == null || tourId.isEmpty) {
      _activeTourId = null;
      return;
    }

    _activeTourId = tourId;
    if (tourName != null) {
      _activeTourName = tourName;
      _tourNames[tourId] = tourName;
    }

    // Only stream the active tour to save memory and storage
    for (final entry in _liveTourSubs.entries) {
      if (entry.key != tourId) {
        entry.value.cancel();
      }
    }
    _liveTourSubs.removeWhere((k, _) => k != tourId);

    listenToTour(tourId, tourName: tourName);
    triggerSync(tourId: tourId);
  }

  void listenToTour(String tourId, {String? tourName}) {
    if (tourId.isEmpty) return;
    if (tourName != null && tourName.isNotEmpty) {
      _tourNames[tourId] = tourName;
    }

    try {
      FirebaseMessaging.instance.subscribeToTopic('tour_$tourId');
    } catch (_) {}

    if (_liveTourSubs.containsKey(tourId)) return;

    final lastTimestamp = _chatRepo.getLastTimestamp(tourId);
    try {
      _liveTourSubs[tourId] = _firestore
          .collection('tours')
          .doc(tourId)
          .collection('chats')
          .where('c', isGreaterThan: lastTimestamp)
          .orderBy('c')
          .snapshots()
          .listen((snapshot) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final incoming = ChatMessage.fromFirestore(change.doc, tourId);
            final isNew = !_chatRepo.hasMessage(tourId, incoming.id);
            _chatRepo.saveMessage(incoming);

            // Display dynamic phone notification for messages from other members
            if (isNew &&
                incoming.authorId != currentUserId &&
                !incoming.isDeleted &&
                ChatActiveTracker.activeTourChatId != tourId) {
              final authorName =
                  UserCacheService.getUser(incoming.authorId)?.displayName ??
                      'Tour Member';
              final resolvedTourName =
                  _tourNames[tourId] ?? _activeTourName ?? 'Tour';
              NotificationService.showChatMessageNotification(
                tourId: tourId,
                tourName: resolvedTourName,
                senderName: authorName,
                messageText: incoming.text ?? '',
                messageId: incoming.id,
              );
            }
          } else if (change.type == DocumentChangeType.removed) {
            // Deleted on server (erased for everyone like Telegram)
            _chatRepo.markAsDeleted(tourId, change.doc.id);
          }
        }
      }, onError: (e) {
        debugPrint('[CHAT_SYNC] Live tour chats listener error for $tourId: $e');
      });
    } catch (e) {
      debugPrint('[CHAT_SYNC] Could not start live listener for $tourId: $e');
    }
  }

  /// Trigger full sync: Upstream, Downstream Delta, and Client-Side Firestore Pruning
  Future<void> triggerSync({String? tourId}) async {
    if (_isSyncing) {
      _hasPendingSync = true;
      return;
    }
    _isSyncing = true;

    try {
      do {
        _hasPendingSync = false;
        final targetTourId = tourId ?? _activeTourId;

        // 1. Upstream Bridge Sync (Upload local unsynced messages to Firestore)
        await syncUpstream(tourId: targetTourId);

        // 2. Downstream Delta Sync (Download new messages since last local timestamp)
        if (targetTourId != null && targetTourId.isNotEmpty) {
          await _syncDownstream(targetTourId);

          // 3. Client-Side Pruning (Batch delete Firestore messages older than 30 days)
          await _pruneOldFirestoreMessages(targetTourId);
        }
      } while (_hasPendingSync);
    } catch (e) {
      debugPrint('[CHAT_SYNC] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Phase 4.2: Bridge Sync (Upstream)
  /// Query Hive for messages where syncedToServer == false, upload to tours/{tourId}/chats
  Future<void> syncUpstream({String? tourId}) async {
    final unsynced = _chatRepo.getUnsyncedMessages(tourId: tourId);
    if (unsynced.isEmpty) return;

    debugPrint('[CHAT_SYNC] Starting upstream sync for ${unsynced.length} messages');
    for (final msg in unsynced) {
      if (msg.tourId.isEmpty) continue;
      try {
        if (msg.isDeleted) {
          // Message deleted for everyone: erase from Firestore like Telegram
          await _firestore
              .collection('tours')
              .doc(msg.tourId)
              .collection('chats')
              .doc(msg.id)
              .delete()
              .timeout(const Duration(seconds: 4));
        } else {
          await _firestore
              .collection('tours')
              .doc(msg.tourId)
              .collection('chats')
              .doc(msg.id)
              .set(msg.toFirestoreMap(), SetOptions(merge: true))
              .timeout(const Duration(seconds: 4));
        }

        // On success, update local Hive state to syncedToServer = true
        await _chatRepo.markSynced(msg.tourId, msg.id);
        debugPrint('[CHAT_SYNC] Message ${msg.id} marked as synced to server');
      } catch (e) {
        debugPrint('[CHAT_SYNC] Failed to sync message ${msg.id}: $e');
      }
    }
  }

  /// Phase 4.3: Delta Sync (Downstream)
  /// Query Firestore: collection('chats').where('c', isGreaterThan: lastLocalTimestamp)
  Future<void> _syncDownstream(String tourId) async {
    final lastLocalTimestamp = _chatRepo.getLastTimestamp(tourId);
    debugPrint('[CHAT_SYNC] Starting delta sync for tour $tourId (lastLocalTimestamp: $lastLocalTimestamp)');

    try {
      final snapshot = await _firestore
          .collection('tours')
          .doc(tourId)
          .collection('chats')
          .where('c', isGreaterThan: lastLocalTimestamp)
          .orderBy('c')
          .limit(100)
          .get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint('[CHAT_SYNC] Received ${snapshot.docs.length} new messages from Firestore');
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
        for (final doc in snapshot.docs) {
          final incoming = ChatMessage.fromFirestore(doc, tourId);
          final isNew = !_chatRepo.hasMessage(tourId, incoming.id);
          await _chatRepo.saveMessage(incoming);

          if (isNew &&
              incoming.authorId != currentUserId &&
              !incoming.isDeleted &&
              ChatActiveTracker.activeTourChatId != tourId) {
            final authorName =
                UserCacheService.getUser(incoming.authorId)?.displayName ??
                    'Tour Member';
            NotificationService.showChatMessageNotification(
              tourId: tourId,
              tourName: _activeTourName ?? 'Tour Chat',
              senderName: authorName,
              messageText: incoming.text ?? '',
              messageId: incoming.id,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[CHAT_SYNC] Downstream delta sync error: $e');
    }
  }

  /// Execute a batch delete in Firestore for messages older than 3 days to save space
  Future<void> _pruneOldFirestoreMessages(String tourId) async {
    final threeDaysAgoMs =
        DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;

    try {
      final oldDocsSnapshot = await _firestore
          .collection('tours')
          .doc(tourId)
          .collection('chats')
          .where('c', isLessThan: threeDaysAgoMs)
          .limit(50)
          .get();

      if (oldDocsSnapshot.docs.isEmpty) return;

      debugPrint('[CHAT_SYNC] Pruning ${oldDocsSnapshot.docs.length} messages older than 3 days from Firestore');
      final batch = _firestore.batch();
      for (final doc in oldDocsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[CHAT_SYNC] Firestore pruning skipped/error: $e');
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _liveChatsSub?.cancel();
    for (final sub in _liveTourSubs.values) {
      sub.cancel();
    }
    _liveTourSubs.clear();
  }
}
