import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:toursplit/data/models/chat_message.dart';
import 'package:toursplit/data/repositories/chat_repository.dart';
import 'package:toursplit/data/services/user_cache_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('toursplit_chat_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    if (Hive.isBoxOpen(ChatRepository.boxName)) {
      await Hive.box<ChatMessage>(ChatRepository.boxName).clear();
    } else {
      await Hive.openBox<ChatMessage>(ChatRepository.boxName);
    }

    if (Hive.isBoxOpen(ChatRepository.prefsBoxName)) {
      await Hive.box(ChatRepository.prefsBoxName).clear();
    } else {
      await Hive.openBox(ChatRepository.prefsBoxName);
    }

    if (Hive.isBoxOpen(UserCacheService.boxName)) {
      await Hive.box<Map>(UserCacheService.boxName).clear();
    } else {
      await Hive.openBox<Map>(UserCacheService.boxName);
    }
  });

  group('ChatMessage Model & Byte Optimization Tests', () {
    test('ChatMessage serializes with shortened keys for minimal storage overhead', () {
      final msg = ChatMessage(
        id: 'msg_100',
        authorId: 'user_abc',
        text: 'Let us meet at the hill top!',
        createdAt: 1727092800000,
        isDeleted: false,
        syncedToServer: false,
        tourId: 'tour_xyz',
      );

      final map = msg.toMap();
      expect(map['i'], equals('msg_100'));
      expect(map['a'], equals('user_abc'));
      expect(map['t'], equals('Let us meet at the hill top!'));
      expect(map['c'], equals(1727092800000));
      expect(map['d'], isFalse);
      expect(map['s'], isFalse);
      expect(map['tid'], equals('tour_xyz'));

      // Verify deserialization
      final restored = ChatMessage.fromMap(map);
      expect(restored.id, equals('msg_100'));
      expect(restored.authorId, equals('user_abc'));
      expect(restored.text, equals('Let us meet at the hill top!'));
      expect(restored.createdAt, equals(1727092800000));
      expect(restored.isDeleted, isFalse);
      expect(restored.syncedToServer, isFalse);
      expect(restored.tourId, equals('tour_xyz'));
    });

    test('toFirestoreMap excludes local sync flag to save Firestore bytes', () {
      final msg = ChatMessage(
        id: 'msg_1',
        authorId: 'u1',
        text: 'Hello',
        createdAt: 1000,
        tourId: 't1',
      );

      final fsMap = msg.toFirestoreMap();
      expect(fsMap.containsKey('s'), isFalse);
      expect(fsMap['i'], equals('msg_1'));
      expect(fsMap['a'], equals('u1'));
      expect(fsMap['t'], equals('Hello'));
      expect(fsMap['c'], equals(1000));
      expect(fsMap['d'], isFalse);
    });

    test('toTombstone nullifies text and flags isDeleted as true', () {
      final msg = ChatMessage(
        id: 'msg_to_delete',
        authorId: 'u1',
        text: 'Sensitive temporary info',
        createdAt: 2000,
        tourId: 't1',
      );

      final tombstone = msg.toTombstone();
      expect(tombstone.id, equals('msg_to_delete'));
      expect(tombstone.text, isNull);
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.syncedToServer, isFalse);
    });

    test('ChatMessage serializes and deserializes reply fields correctly', () {
      final msg = ChatMessage(
        id: 'msg_reply_1',
        authorId: 'u2',
        text: 'I agree with this plan!',
        createdAt: 1727092900000,
        tourId: 'tour_abc',
        replyToId: 'msg_orig_1',
        replyToAuthor: 'Alice',
        replyToText: 'Shall we book the tickets now?',
      );

      // Verify toMap
      final map = msg.toMap();
      expect(map['ri'], equals('msg_orig_1'));
      expect(map['ra'], equals('Alice'));
      expect(map['rt'], equals('Shall we book the tickets now?'));

      // Verify fromMap
      final restored = ChatMessage.fromMap(map);
      expect(restored.replyToId, equals('msg_orig_1'));
      expect(restored.replyToAuthor, equals('Alice'));
      expect(restored.replyToText, equals('Shall we book the tickets now?'));

      // Verify toFirestoreMap
      final fsMap = msg.toFirestoreMap();
      expect(fsMap['ri'], equals('msg_orig_1'));
      expect(fsMap['ra'], equals('Alice'));
      expect(fsMap['rt'], equals('Shall we book the tickets now?'));

      // Verify fromFirestore map restored via fromMap
      final fsRestored = ChatMessage.fromMap(fsMap, fallbackTourId: 'tour_abc');
      expect(fsRestored.replyToId, equals('msg_orig_1'));
      expect(fsRestored.replyToAuthor, equals('Alice'));
      expect(fsRestored.replyToText, equals('Shall we book the tickets now?'));
    });

    test('ChatMessageAdapter persists reply fields across Hive write and read', () async {
      final box = Hive.box<ChatMessage>(ChatRepository.boxName);
      final msg = ChatMessage(
        id: 'msg_hive_reply',
        authorId: 'user_bob',
        text: 'Count me in!',
        createdAt: 1727093000000,
        tourId: 'tour_hive',
        replyToId: 'msg_alice_1',
        replyToAuthor: 'Alice',
        replyToText: 'Who wants to join the hike?',
      );

      await box.put('tour_hive_msg_hive_reply', msg);
      final readMsg = box.get('tour_hive_msg_hive_reply');

      expect(readMsg, isNotNull);
      expect(readMsg!.id, equals('msg_hive_reply'));
      expect(readMsg.replyToId, equals('msg_alice_1'));
      expect(readMsg.replyToAuthor, equals('Alice'));
      expect(readMsg.replyToText, equals('Who wants to join the hike?'));
    });
  });

  group('ChatRepository Tombstone & Rolling Window Pruning Tests', () {
    test('saveMessage saves message and retrieves by tourId reverse sorted', () async {
      final repo = ChatRepository();
      final msg1 = ChatMessage(
        id: 'm1',
        authorId: 'u1',
        text: 'First',
        createdAt: 1000,
        tourId: 'tour_1',
      );
      final msg2 = ChatMessage(
        id: 'm2',
        authorId: 'u2',
        text: 'Second',
        createdAt: 2000,
        tourId: 'tour_1',
      );

      await repo.saveMessage(msg1);
      await repo.saveMessage(msg2);

      final messages = repo.getTourMessages('tour_1');
      expect(messages.length, equals(2));
      // Reverse sorted: newest (m2) first
      expect(messages.first.id, equals('m2'));
      expect(messages.last.id, equals('m1'));
    });

    test('Tombstone preservation: Deleted message cannot be resurrected by older payload', () async {
      final repo = ChatRepository();
      final original = ChatMessage(
        id: 'm_del',
        authorId: 'u1',
        text: 'Secret',
        createdAt: 1000,
        tourId: 'tour_1',
      );
      await repo.saveMessage(original);

      // Now tombstone it
      await repo.markAsDeleted('tour_1', 'm_del');
      final deleted = repo.getMessage('tour_1', 'm_del')!;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.text, isNull);

      // Attempt to resurrect by saving older non-deleted version from mesh gossip
      await repo.saveMessage(original);
      final afterAttempt = repo.getMessage('tour_1', 'm_del')!;
      expect(afterAttempt.isDeleted, isTrue);
      expect(afterAttempt.text, isNull);

      // Verify erased from tour messages list like Telegram
      final list = repo.getTourMessages('tour_1');
      expect(list.any((m) => m.id == 'm_del'), isFalse);
    });

    test('deleteForMe marks message deleted locally without queuing upstream sync', () async {
      final repo = ChatRepository();
      final msg = ChatMessage(
        id: 'msg_for_me',
        authorId: 'u1',
        text: 'Private to hide',
        createdAt: 1000,
        tourId: 'tour_me',
      );
      await repo.saveMessage(msg);
      expect(repo.getTourMessages('tour_me').length, equals(1));

      await repo.deleteForMe('tour_me', 'msg_for_me');
      expect(repo.getTourMessages('tour_me'), isEmpty);

      // Verify syncedToServer is true so it never triggers upstream deletion for others
      final stored = repo.getMessage('tour_me', 'msg_for_me')!;
      expect(stored.isDeleted, isTrue);
      expect(stored.syncedToServer, isTrue);
      expect(repo.getUnsyncedMessages(tourId: 'tour_me'), isEmpty);
    });

    test('deleteForEveryone marks message deleted locally and queues upstream deletion', () async {
      final repo = ChatRepository();
      final msg = ChatMessage(
        id: 'msg_everyone',
        authorId: 'u1',
        text: 'Delete for all',
        createdAt: 1000,
        tourId: 'tour_all',
      );
      await repo.saveMessage(msg);
      expect(repo.getTourMessages('tour_all').length, equals(1));

      await repo.deleteForEveryone('tour_all', 'msg_everyone');
      expect(repo.getTourMessages('tour_all'), isEmpty);

      // Verify syncedToServer is false so upstream sync deletes on Firestore
      final stored = repo.getMessage('tour_all', 'msg_everyone')!;
      expect(stored.isDeleted, isTrue);
      expect(stored.syncedToServer, isFalse);
      expect(repo.getUnsyncedMessages(tourId: 'tour_all').length, equals(1));
    });

    test('Local rolling window: Prunes oldest records beyond 200 messages', () async {
      final repo = ChatRepository();
      const tourId = 'tour_prune_test';

      // Save 205 messages sequentially
      for (int i = 1; i <= 205; i++) {
        final msg = ChatMessage(
          id: 'msg_$i',
          authorId: 'user_test',
          text: 'Message #$i',
          createdAt: 1000 + i,
          tourId: tourId,
        );
        await repo.saveMessage(msg);
      }

      final messages = repo.getTourMessages(tourId);
      // Must not exceed 200 messages
      expect(messages.length, equals(200));

      // The 5 oldest messages (msg_1 to msg_5) must have been physically deleted from Hive
      for (int i = 1; i <= 5; i++) {
        expect(repo.hasMessage(tourId, 'msg_$i'), isFalse);
      }

      // msg_6 through msg_205 must be retained
      expect(repo.hasMessage(tourId, 'msg_6'), isTrue);
      expect(repo.hasMessage(tourId, 'msg_205'), isTrue);
    });

    test('7-day inactivity auto-pruning removes messages older than 7 days', () async {
      final repo = ChatRepository();
      const tourId = 'tour_7day_prune';
      final now = DateTime.now().millisecondsSinceEpoch;
      final eightDaysAgo = now - (8 * 24 * 60 * 60 * 1000);
      final twoDaysAgo = now - (2 * 24 * 60 * 60 * 1000);

      // Save an old message (8 days old)
      final oldMsg = ChatMessage(
        id: 'msg_old',
        authorId: 'u1',
        text: 'Old message to be pruned',
        createdAt: eightDaysAgo,
        tourId: tourId,
      );
      await repo.saveMessage(oldMsg);

      // Save a recent message (2 days old) which triggers pruning
      final recentMsg = ChatMessage(
        id: 'msg_recent',
        authorId: 'u2',
        text: 'Recent active message',
        createdAt: twoDaysAgo,
        tourId: tourId,
      );
      await repo.saveMessage(recentMsg);

      // Check that oldMsg was pruned from Hive, but recentMsg remains
      expect(repo.hasMessage(tourId, 'msg_old'), isFalse);
      expect(repo.hasMessage(tourId, 'msg_recent'), isTrue);

      final activeMessages = repo.getTourMessages(tourId);
      expect(activeMessages.length, equals(1));
      expect(activeMessages.first.id, equals('msg_recent'));
    });

    test('Unread count calculation works correctly', () async {
      final repo = ChatRepository();
      const tourId = 'tour_unread_test';
      const myId = 'my_user_id';
      const friendId = 'friend_user_id';

      // Messages sent by friend
      await repo.saveMessage(ChatMessage(
        id: 'u_1',
        authorId: friendId,
        text: 'Hi',
        createdAt: 100,
        tourId: tourId,
      ));
      await repo.saveMessage(ChatMessage(
        id: 'u_2',
        authorId: friendId,
        text: 'Are you ready?',
        createdAt: 200,
        tourId: tourId,
      ));
      // Message sent by myself (does not count as unread)
      await repo.saveMessage(ChatMessage(
        id: 'u_3',
        authorId: myId,
        text: 'Yes I am!',
        createdAt: 300,
        tourId: tourId,
      ));

      expect(repo.getUnreadCount(tourId, myId), equals(2));

      // Mark tour as read
      await repo.markTourAsRead(tourId);
      expect(repo.getUnreadCount(tourId, myId), equals(0));
    });

    test('watchUnreadCount stream emits initial count and updates reactively', () async {
      final repo = ChatRepository();
      const tourId = 'tour_stream_test';
      const myId = 'my_id';
      const friendId = 'friend_id';

      final unreadStream = repo.watchUnreadCount(tourId, myId);
      final emittedValues = <int>[];
      final subscription = unreadStream.listen(emittedValues.add);

      // Allow initial emission
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedValues.last, equals(0));

      // Incoming message from friend
      await repo.saveMessage(ChatMessage(
        id: 'msg_s1',
        authorId: friendId,
        text: 'New incoming message',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        tourId: tourId,
      ));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedValues.last, equals(1));

      // Second message from friend
      await repo.saveMessage(ChatMessage(
        id: 'msg_s2',
        authorId: friendId,
        text: 'Another message',
        createdAt: DateTime.now().millisecondsSinceEpoch + 10,
        tourId: tourId,
      ));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedValues.last, equals(2));

      // Mark as read should immediately emit 0
      await repo.markTourAsRead(tourId);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedValues.last, equals(0));

      await subscription.cancel();
    });
  });

  group('UserCacheService Relational Author Cache Tests', () {
    test('Caches and formats user initials and display name properly', () async {
      await UserCacheService.cacheUser(
        uid: 'user_sami',
        displayName: 'Samiul Shoruv',
        photoUrl: 'https://example.com/avatar.jpg',
      );

      final cached = UserCacheService.getUser('user_sami');
      expect(cached, isNotNull);
      expect(cached!.displayName, equals('Samiul Shoruv'));
      expect(cached.initials, equals('SS'));
      expect(cached.photoUrl, equals('https://example.com/avatar.jpg'));
    });
  });
}
