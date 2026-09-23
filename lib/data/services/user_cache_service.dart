import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/tour_model.dart';
import 'auth_service.dart';

class CachedUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String username;

  const CachedUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.username = '',
  });

  factory CachedUser.fromMap(Map map) {
    return CachedUser(
      uid: map['uid'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Member',
      photoUrl: map['photoUrl'] as String?,
      username: map['username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'username': username,
      };

  String get initials {
    if (displayName.trim().isEmpty) return '?';
    final parts = displayName.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}

class UserCacheService {
  static const String boxName = 'user_box';

  static Box<Map> get box => Hive.box<Map>(boxName);

  static CachedUser? getUser(String uid) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final map = box.get(uid);
    if (map == null) return null;
    return CachedUser.fromMap(map);
  }

  static Future<void> cacheUser({
    required String uid,
    required String displayName,
    String? photoUrl,
    String username = '',
  }) async {
    if (!Hive.isBoxOpen(boxName)) return;
    await box.put(uid, {
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'username': username,
    });
  }

  static Future<void> cacheUserModel(UserModel user) async {
    await cacheUser(
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      username: user.username,
    );
  }

  static Future<void> cacheTourMember(TourMemberModel member) async {
    await cacheUser(
      uid: member.userId,
      displayName: member.displayName,
      photoUrl: member.photoUrl,
      username: '',
    );
  }
}

/// Listenable Provider for reading a cached user from user_box
final userBoxProvider = Provider.family<CachedUser?, String>((ref, uid) {
  if (uid.isEmpty) return null;

  // Listen to Hive box changes so UI re-renders reactively when user is cached
  if (Hive.isBoxOpen(UserCacheService.boxName)) {
    final box = UserCacheService.box;
    // Watch box for this specific key
    final cached = box.get(uid);
    if (cached != null) {
      return CachedUser.fromMap(cached);
    }
  }

  // If not in cache, fallback to userProfileProvider and populate user_box asynchronously
  final asyncProfile = ref.watch(userProfileProvider(uid)).value;
  if (asyncProfile != null) {
    UserCacheService.cacheUserModel(asyncProfile);
    return CachedUser(
      uid: asyncProfile.uid,
      displayName: asyncProfile.displayName,
      photoUrl: asyncProfile.photoUrl,
      username: asyncProfile.username,
    );
  }

  return null;
});
