import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

@HiveType(typeId: 10)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String authorId;

  @HiveField(2)
  final String? text;

  @HiveField(3)
  final int createdAt;

  @HiveField(4)
  final bool isDeleted;

  @HiveField(5)
  final bool syncedToServer;

  @HiveField(6)
  final String tourId;

  @HiveField(7)
  final String? replyToId;

  @HiveField(8)
  final String? replyToAuthor;

  @HiveField(9)
  final String? replyToText;

  @HiveField(10)
  final Map<String, String>? reactions;

  ChatMessage({
    required this.id,
    required this.authorId,
    this.text,
    required this.createdAt,
    this.isDeleted = false,
    this.syncedToServer = false,
    required this.tourId,
    this.replyToId,
    this.replyToAuthor,
    this.replyToText,
    this.reactions,
  });

  bool get hasReactions => reactions != null && reactions!.isNotEmpty;

  Map<String, int> get reactionCounts {
    if (!hasReactions) return {};
    final counts = <String, int>{};
    for (final emoji in reactions!.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  String? userReaction(String userId) => reactions?[userId];

  /// Shortened JSON keys to minimize bandwidth and Firestore storage overhead:
  /// 'i' -> id
  /// 'a' -> authorId (relational UID only)
  /// 't' -> text
  /// 'c' -> createdAt (epoch millis)
  /// 'd' -> isDeleted (tombstone flag)
  /// 's' -> syncedToServer
  /// 'tid' -> tourId
  /// 'ri' -> replyToId
  /// 'ra' -> replyToAuthor
  /// 'rt' -> replyToText
  /// 'rx' -> reactions (map of userId -> emoji)
  Map<String, dynamic> toMap() => {
        'i': id,
        'a': authorId,
        't': text,
        'c': createdAt,
        'd': isDeleted,
        's': syncedToServer,
        'tid': tourId,
        if (replyToId != null) 'ri': replyToId,
        if (replyToAuthor != null) 'ra': replyToAuthor,
        if (replyToText != null) 'rt': replyToText,
        if (reactions != null && reactions!.isNotEmpty) 'rx': reactions,
      };

  /// For Firestore document write (excludes local sync flag 's')
  Map<String, dynamic> toFirestoreMap() => {
        'i': id,
        'a': authorId,
        't': text,
        'c': createdAt,
        'd': isDeleted,
        if (replyToId != null) 'ri': replyToId,
        if (replyToAuthor != null) 'ra': replyToAuthor,
        if (replyToText != null) 'rt': replyToText,
        'rx': (reactions != null && reactions!.isNotEmpty)
            ? reactions
            : FieldValue.delete(),
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map, {String? fallbackTourId}) {
    return ChatMessage(
      id: map['i'] as String? ?? '',
      authorId: map['a'] as String? ?? '',
      text: map['t'] as String?,
      createdAt: (map['c'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: map['d'] as bool? ?? false,
      syncedToServer: map['s'] as bool? ?? false,
      tourId: (map['tid'] as String?) ?? fallbackTourId ?? '',
      replyToId: map['ri'] as String?,
      replyToAuthor: map['ra'] as String?,
      replyToText: map['rt'] as String?,
      reactions: (map['rx'] is Map)
          ? (map['rx'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }

  factory ChatMessage.fromFirestore(DocumentSnapshot doc, String tourId) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ChatMessage(
      id: data['i'] as String? ?? doc.id,
      authorId: data['a'] as String? ?? '',
      text: data['t'] as String?,
      createdAt: (data['c'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: data['d'] as bool? ?? false,
      syncedToServer: true,
      tourId: tourId,
      replyToId: data['ri'] as String?,
      replyToAuthor: data['ra'] as String?,
      replyToText: data['rt'] as String?,
      reactions: (data['rx'] is Map)
          ? (data['rx'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? authorId,
    String? text,
    int? createdAt,
    bool? isDeleted,
    bool? syncedToServer,
    String? tourId,
    String? replyToId,
    String? replyToAuthor,
    String? replyToText,
    Map<String, String>? reactions,
    bool clearReactions = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncedToServer: syncedToServer ?? this.syncedToServer,
      tourId: tourId ?? this.tourId,
      replyToId: replyToId ?? this.replyToId,
      replyToAuthor: replyToAuthor ?? this.replyToAuthor,
      replyToText: replyToText ?? this.replyToText,
      reactions: clearReactions ? null : (reactions ?? this.reactions),
    );
  }

  /// Create a tombstone version of this message (nullifies text and replies, sets isDeleted=true)
  ChatMessage toTombstone() {
    return ChatMessage(
      id: id,
      authorId: authorId,
      text: null,
      createdAt: createdAt,
      isDeleted: true,
      syncedToServer: false, // Needs to sync tombstone to server
      tourId: tourId,
      replyToId: null,
      replyToAuthor: null,
      replyToText: null,
      reactions: null,
    );
  }
}

/// Custom binary TypeAdapter for ChatMessage (TypeId: 10)
class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 10;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String? ?? '',
      authorId: fields[1] as String? ?? '',
      text: fields[2] as String?,
      createdAt: (fields[3] as int?) ?? 0,
      isDeleted: fields[4] as bool? ?? false,
      syncedToServer: fields[5] as bool? ?? false,
      tourId: fields[6] as String? ?? '',
      replyToId: fields[7] as String?,
      replyToAuthor: fields[8] as String?,
      replyToText: fields[9] as String?,
      reactions: (fields[10] is Map)
          ? (fields[10] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.authorId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.isDeleted)
      ..writeByte(5)
      ..write(obj.syncedToServer)
      ..writeByte(6)
      ..write(obj.tourId)
      ..writeByte(7)
      ..write(obj.replyToId)
      ..writeByte(8)
      ..write(obj.replyToAuthor)
      ..writeByte(9)
      ..write(obj.replyToText)
      ..writeByte(10)
      ..write(obj.reactions);
  }
}

