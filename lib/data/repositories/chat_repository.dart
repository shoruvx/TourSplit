import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/chat_message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository();
});

/// Riverpod stream of messages for active tour, reverse sorted (newest first for reverse ListView)
final tourMessagesStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, tourId) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchTourMessages(tourId);
});

/// Riverpod stream of unread message count for a tour
final tourUnreadCountProvider =
    StreamProvider.family<int, ({String tourId, String currentUserId})>((ref, arg) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchUnreadCount(arg.tourId, arg.currentUserId);
});

class ChatRepository {
  static const String boxName = 'chat_box';
  static const String prefsBoxName = 'app_preferences';
  static const int maxLocalMessagesPerTour = 200;

  Box<ChatMessage> get _box => Hive.box<ChatMessage>(boxName);

  String _key(String tourId, String messageId) => '${tourId}_$messageId';

  /// Save message with Tombstone protection and 200-message local rolling window pruning
  Future<void> saveMessage(ChatMessage msg) async {
    if (!Hive.isBoxOpen(boxName)) return;

    final key = _key(msg.tourId, msg.id);
    final existing = _box.get(key);

    // CRDT Tombstone rule: if already deleted locally, do not resurrect
    if (existing != null && existing.isDeleted) {
      return;
    }

    // Phase 3.1: If isDeleted is true, nullify text field to store strictly as a Tombstone
    final ChatMessage toSave;
    if (msg.isDeleted) {
      toSave = msg.copyWith(text: null, isDeleted: true, reactions: null);
    } else {
      if (existing != null && !existing.syncedToServer && existing.reactions != null) {
        final mergedReactions = Map<String, String>.from(msg.reactions ?? {});
        mergedReactions.addAll(existing.reactions!);
        toSave = msg.copyWith(reactions: mergedReactions, syncedToServer: false);
      } else {
        toSave = msg;
      }
    }

    await _box.put(key, toSave);

    // Phase 3.2: Local Rolling Window: Count total messages for tour, prune if > 200
    await _pruneLocalTourMessages(msg.tourId);
  }

  /// Toggle a reaction on a message by a user.
  /// If the user already reacted with this emoji, the reaction is removed.
  /// If the user reacted with a different emoji, it is updated.
  /// Sets syncedToServer = false so ChatSyncService can push to Firestore.
  Future<ChatMessage?> toggleReaction({
    required String tourId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    if (!Hive.isBoxOpen(boxName)) return null;
    final key = _key(tourId, messageId);
    final msg = _box.get(key);
    if (msg == null || msg.isDeleted) return null;

    final currentReactions = Map<String, String>.from(msg.reactions ?? {});
    if (currentReactions[userId] == emoji) {
      currentReactions.remove(userId);
    } else {
      currentReactions[userId] = emoji;
    }

    final updated = msg.copyWith(
      reactions: currentReactions.isEmpty ? null : currentReactions,
      clearReactions: currentReactions.isEmpty,
      syncedToServer: false,
    );

    await _box.put(key, updated);
    return updated;
  }

  Future<void> _pruneLocalTourMessages(String tourId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final threeDaysAgo = now - (3 * 24 * 60 * 60 * 1000);

    final tourEntries = _box
        .toMap()
        .entries
        .where((e) => e.value.tourId == tourId)
        .toList();

    // 1. Delete messages older than 3 days of inactivity to save device space
    for (final entry in tourEntries) {
      if (entry.value.createdAt > 1000000000000 &&
          entry.value.createdAt < threeDaysAgo) {
        await _box.delete(entry.key);
      }
    }

    // 2. Local Rolling Window: Count total messages for tour, prune if > 200
    final remaining = _box
        .toMap()
        .entries
        .where((e) => e.value.tourId == tourId)
        .toList();

    if (remaining.length > maxLocalMessagesPerTour) {
      // Sort ascending by createdAt (oldest first)
      remaining.sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      final excessCount = remaining.length - maxLocalMessagesPerTour;
      for (int i = 0; i < excessCount; i++) {
        await _box.delete(remaining[i].key);
      }
      debugPrint('[CHAT_REPO] Pruned $excessCount oldest messages for tour $tourId (max: $maxLocalMessagesPerTour)');
    }
  }

  /// Check if a message exists locally
  bool hasMessage(String tourId, String messageId) {
    if (!Hive.isBoxOpen(boxName)) return false;
    return _box.containsKey(_key(tourId, messageId));
  }

  /// Get single message
  ChatMessage? getMessage(String tourId, String messageId) {
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box.get(_key(tourId, messageId));
  }

  /// Get all messages for a tour, sorted descending (newest first for reverse ListView).
  /// Erases deleted messages from the UI completely like Telegram.
  List<ChatMessage> getTourMessages(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = _box.values
        .where((m) => m.tourId == tourId && !m.isDeleted)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Stream of tour messages for UI (reacts to Hive box changes)
  Stream<List<ChatMessage>> watchTourMessages(String tourId) async* {
    yield getTourMessages(tourId);
    if (Hive.isBoxOpen(boxName)) {
      yield* _box.watch().map((_) => getTourMessages(tourId));
    }
  }

  /// Unsynced messages for upstream server sync
  List<ChatMessage> getUnsyncedMessages({String? tourId}) {
    if (!Hive.isBoxOpen(boxName)) return [];
    return _box.values
        .where((m) => !m.syncedToServer && (tourId == null || m.tourId == tourId))
        .toList();
  }

  /// Mark message as synced to server
  Future<void> markSynced(String tourId, String messageId) async {
    if (!Hive.isBoxOpen(boxName)) return;
    final key = _key(tourId, messageId);
    final msg = _box.get(key);
    if (msg != null && !msg.syncedToServer) {
      await _box.put(key, msg.copyWith(syncedToServer: true));
    }
  }

  /// Get the highest timestamp locally for downstream delta sync
  int getLastTimestamp(String tourId) {
    if (!Hive.isBoxOpen(boxName)) return 0;
    final list = _box.values.where((m) => m.tourId == tourId).toList();
    if (list.isEmpty) return 0;
    return list.map((m) => m.createdAt).reduce((max, c) => c > max ? c : max);
  }

  /// Delete message locally for this user only (does not sync or broadcast)
  Future<void> deleteForMe(String tourId, String messageId) async {
    if (!Hive.isBoxOpen(boxName)) return;
    final key = _key(tourId, messageId);
    final existing = _box.get(key);
    if (existing != null) {
      await _box.put(
        key,
        existing.copyWith(isDeleted: true, syncedToServer: true, text: null),
      );
    }
  }

  /// Delete message for everyone (tombstone locally with syncedToServer=false so upstream sync deletes on Firestore)
  Future<void> deleteForEveryone(String tourId, String messageId) async {
    if (!Hive.isBoxOpen(boxName)) return;
    final key = _key(tourId, messageId);
    final existing = _box.get(key);
    if (existing != null) {
      await _box.put(
        key,
        existing.copyWith(isDeleted: true, syncedToServer: false, text: null),
      );
    }
  }

  /// Soft delete a message (creates a tombstone)
  Future<void> markAsDeleted(String tourId, String messageId) async {
    final msg = getMessage(tourId, messageId);
    if (msg != null) {
      await saveMessage(msg.toTombstone());
    }
  }

  /// Read tracking for unread badge
  int getLastReadTimestamp(String tourId) {
    if (!Hive.isBoxOpen(prefsBoxName)) return 0;
    final prefs = Hive.box(prefsBoxName);
    return prefs.get('last_read_chat_$tourId', defaultValue: 0) as int;
  }

  Future<void> markTourAsRead(String tourId) async {
    if (!Hive.isBoxOpen(prefsBoxName)) return;
    final prefs = Hive.box(prefsBoxName);
    await prefs.put('last_read_chat_$tourId', DateTime.now().millisecondsSinceEpoch);
  }

  int getUnreadCount(String tourId, String currentUserId) {
    if (!Hive.isBoxOpen(boxName)) return 0;
    final lastRead = getLastReadTimestamp(tourId);
    return _box.values.where((m) {
      return m.tourId == tourId &&
          m.authorId != currentUserId &&
          !m.isDeleted &&
          m.createdAt > lastRead;
    }).length;
  }

  Stream<int> watchUnreadCount(String tourId, String currentUserId) {
    late StreamController<int> controller;
    StreamSubscription? boxSub;
    StreamSubscription? prefsSub;

    void emitLatest() {
      if (!controller.isClosed) {
        controller.add(getUnreadCount(tourId, currentUserId));
      }
    }

    controller = StreamController<int>.broadcast(
      onListen: () {
        emitLatest();
        if (Hive.isBoxOpen(boxName)) {
          boxSub = _box.watch().listen((_) => emitLatest());
        }
        if (Hive.isBoxOpen(prefsBoxName)) {
          prefsSub = Hive.box(prefsBoxName).watch().listen((_) => emitLatest());
        }
      },
      onCancel: () {
        boxSub?.cancel();
        prefsSub?.cancel();
      },
    );

    return controller.stream;
  }
}
