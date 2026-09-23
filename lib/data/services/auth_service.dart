import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userProfileProvider =
    FutureProvider.family<UserModel?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  try {
    final doc = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  } catch (_) {
    return null;
  }
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .snapshots()
          .asyncMap((doc) async {
        if (doc.exists) {
          final model = UserModel.fromFirestore(doc);
          if (user.email != null && user.email!.isNotEmpty) {
            AuthService.recordUserEmail(
              email: user.email!,
              uid: user.uid,
              username: model.username,
              displayName: model.displayName,
              photoUrl: model.photoUrl,
            );
          }
          return model;
        } else {
          final nameParts = (user.displayName ?? '').split(' ');
          final emailPrefix = (user.email ?? 'user').split('@').first;
          final userModel = UserModel(
            uid: user.uid,
            email: user.email ?? '',
            username: emailPrefix.toLowerCase(),
            firstName: nameParts.isNotEmpty && nameParts.first.isNotEmpty
                ? nameParts.first
                : emailPrefix,
            lastName: nameParts.length > 1 ? nameParts.last : '',
            photoUrl: user.photoURL,
            createdAt: DateTime.now(),
          );
          try {
            await FirebaseFirestore.instance
                .collection(AppConstants.usersCollection)
                .doc(user.uid)
                .set(userModel.toFirestore());
            return userModel;
          } catch (e) {
            return null;
          }
        }
      });
    },
    loading: () => const Stream.empty(),
    error: (_, __) => Stream.value(null),
  );
});

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '57491876636-hssqr3kr22ul02175nrufl5953h88po6.apps.googleusercontent.com',
  );

  static Future<void> recordUserEmail({
    required String email,
    required String uid,
    String? username,
    String? displayName,
    String? photoUrl,
    String? provider,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.registeredEmailsCollection)
          .doc(cleanEmail)
          .set({
        'email': cleanEmail,
        'uid': uid,
        if (username != null && username.isNotEmpty)
          'username': username.toLowerCase().trim(),
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName.trim(),
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (provider != null) 'provider': provider,
        'registeredAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AUTH] Failed to record user email: $e');
    }
  }

  Future<UserModel> registerWithEmail({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;

    await user.updateDisplayName('$firstName $lastName');

    final userModel = UserModel(
      uid: user.uid,
      email: email,
      username: username.toLowerCase().trim(),
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .set(userModel.toFirestore());

    await recordUserEmail(
      email: email,
      uid: user.uid,
      username: username,
      displayName: '$firstName $lastName',
      provider: 'email',
    );

    return userModel;
  }

  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;

    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      final nameParts = (user.displayName ?? '').split(' ');
      final userModel = UserModel(
        uid: user.uid,
        email: email,
        username: email.split('@').first.toLowerCase(),
        firstName:
            nameParts.isNotEmpty ? nameParts.first : email.split('@').first,
        lastName: nameParts.length > 1 ? nameParts.last : '',
        createdAt: DateTime.now(),
      );
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(userModel.toFirestore());
    }

    await recordUserEmail(
      email: email,
      uid: user.uid,
      displayName: user.displayName,
      provider: 'email',
    );

    return user;
  }

  Future<UserModel?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user!;

    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      final nameParts = (user.displayName ?? '').split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1 ? nameParts.last : '';

      final userModel = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        username: (user.email ?? '').split('@').first.toLowerCase(),
        firstName: firstName,
        lastName: lastName,
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(userModel.toFirestore());

      if (user.email != null) {
        await recordUserEmail(
          email: user.email!,
          uid: user.uid,
          username: userModel.username,
          displayName: user.displayName,
          photoUrl: user.photoURL,
          provider: 'google',
        );
      }

      return userModel;
    }

    if (user.email != null) {
      await recordUserEmail(
        email: user.email!,
        uid: user.uid,
        displayName: user.displayName,
        photoUrl: user.photoURL,
        provider: 'google',
      );
    }

    return UserModel.fromFirestore(doc);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> updateProfile({
    required String uid,
    String? name,
    String? username,
    String? firstName,
    String? lastName,
    String? activeTourId,
  }) async {
    final cleanName = (name ?? '').trim().isNotEmpty
        ? name!.trim()
        : '${firstName ?? ''} ${lastName ?? ''}'.trim();
    String cleanUsername = (username ?? '').trim().toLowerCase();
    if (cleanUsername.startsWith('@')) {
      cleanUsername = cleanUsername.substring(1).trim();
    }

    if (cleanUsername.isNotEmpty) {
      final available =
          await isUsernameAvailable(cleanUsername, excludeUid: uid);
      if (!available) {
        throw Exception(
            'Username "@$cleanUsername" is already taken. Please choose another.');
      }
    }

    // 1. Update Firebase Auth displayName
    final user = _auth.currentUser;
    if (user != null && cleanName.isNotEmpty) {
      await user.updateDisplayName(cleanName);
    }

    // 2. Update Firestore users collection
    final updateData = <String, dynamic>{
      'firstName': cleanName,
      'lastName': '',
    };
    if (cleanUsername.isNotEmpty) {
      updateData['username'] = cleanUsername;
    }

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update(updateData);

    // 3. Update member document in active tour if present
    if (activeTourId != null && activeTourId.isNotEmpty) {
      try {
        final memberUpdate = <String, dynamic>{'displayName': cleanName};
        if (cleanUsername.isNotEmpty) {
          memberUpdate['username'] = cleanUsername;
        }
        await _firestore
            .collection(AppConstants.toursCollection)
            .doc(activeTourId)
            .collection(AppConstants.membersSubcollection)
            .doc(uid)
            .update(memberUpdate);
      } catch (_) {}
    }

    final authUser = _auth.currentUser;
    if (authUser?.email != null) {
      recordUserEmail(
        email: authUser!.email!,
        uid: uid,
        username: cleanUsername.isNotEmpty ? cleanUsername : null,
        displayName: cleanName,
      );
    }
  }

  Future<void> updatePaymentAccounts(
      String uid, List<PaymentAccount> accounts) async {
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'paymentAccounts': accounts.map((a) => a.toMap()).toList(),
    });
  }

  Future<String> uploadProfileImage(
      String uid, Uint8List imageBytes, String extension) async {
    // Phase 1: Pipe image bytes through flutter_image_compress (target size < 150KB, format JPEG)
    Uint8List processedBytes = imageBytes;
    try {
      int quality = 85;
      var compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      // Iteratively reduce quality/dimensions if still >= 150KB (153600 bytes)
      while (compressed.lengthInBytes > 150 * 1024 && quality > 25) {
        quality -= 15;
        compressed = await FlutterImageCompress.compressWithList(
          compressed,
          minWidth: 600,
          minHeight: 600,
          quality: quality,
          format: CompressFormat.jpeg,
        );
      }
      if (compressed.isNotEmpty) {
        processedBytes = compressed;
      }
    } catch (e) {
      debugPrint('[STORAGE_COMPRESS] Compression failed, proceeding with original: $e');
    }

    const mime = 'image/jpeg';
    const safeExt = 'jpg';

    // 1. Try default storage bucket with 4s timeout
    try {
      final ref = _storage.ref().child(
          'users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
      final snapshot = await ref
          .putData(
            processedBytes,
            SettableMetadata(contentType: mime),
          )
          .timeout(const Duration(seconds: 4));
      return await snapshot.ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[STORAGE_PRIMARY_FAILED_OR_TIMEOUT] $e');
    }

    // 2. Try alternate bucket with 2.5s timeout
    try {
      final altStorage = FirebaseStorage.instanceFor(
        bucket: 'tourexpensetracker-3da34.appspot.com',
      );
      final ref = altStorage.ref().child(
          'users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
      final snapshot = await ref
          .putData(
            processedBytes,
            SettableMetadata(contentType: mime),
          )
          .timeout(const Duration(milliseconds: 2500));
      return await snapshot.ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[STORAGE_ALTSPOT_FAILED_OR_TIMEOUT] $e');
    }

    // 3. Fallback: Store as a data URI so profile picture update NEVER fails and finishes instantly
    final base64String = base64Encode(processedBytes);
    return 'data:$mime;base64,$base64String';
  }

  Future<void> updateProfilePhoto(String uid, String? photoUrl,
      {String? activeTourId}) async {
    final user = _auth.currentUser;
    if (user != null) {
      if (photoUrl == null) {
        try {
          await user.updatePhotoURL(null);
        } catch (_) {}
      } else if (!photoUrl.startsWith('data:') &&
          photoUrl.length <= 2000 &&
          (photoUrl.startsWith('http://') || photoUrl.startsWith('https://'))) {
        try {
          await user.updatePhotoURL(photoUrl);
        } catch (e) {
          debugPrint('[AUTH] updatePhotoURL ignored: $e');
        }
      }
    }

    // 1. Immediately update user document in Firestore (instant UI update via currentUserProvider)
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'photoUrl': photoUrl,
    });

    // 2. Immediately update active tour member document if present
    if (activeTourId != null && activeTourId.isNotEmpty) {
      try {
        await _firestore
            .collection(AppConstants.toursCollection)
            .doc(activeTourId)
            .collection(AppConstants.membersSubcollection)
            .doc(uid)
            .set({'photoUrl': photoUrl}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[AUTH] Active tour member sync error: $e');
      }
    }

    // 3. Background sync across all other tours without blocking the screen
    unawaited(_syncAllToursMemberPhoto(uid, photoUrl, activeTourId));
  }

  Future<void> _syncAllToursMemberPhoto(
      String uid, String? photoUrl, String? activeTourId) async {
    try {
      final Set<String> tourDocIds = {};

      final toursSnapshot = await _firestore
          .collection(AppConstants.toursCollection)
          .where('members', arrayContains: uid)
          .get();
      for (final doc in toursSnapshot.docs) {
        if (doc.id != activeTourId) {
          tourDocIds.add(doc.id);
        }
      }

      final adminToursSnapshot = await _firestore
          .collection(AppConstants.toursCollection)
          .where('adminId', isEqualTo: uid)
          .get();
      for (final doc in adminToursSnapshot.docs) {
        if (doc.id != activeTourId) {
          tourDocIds.add(doc.id);
        }
      }

      if (tourDocIds.isNotEmpty) {
        final batch = _firestore.batch();
        for (final tourId in tourDocIds) {
          final memberRef = _firestore
              .collection(AppConstants.toursCollection)
              .doc(tourId)
              .collection(AppConstants.membersSubcollection)
              .doc(uid);
          batch.set(memberRef, {'photoUrl': photoUrl}, SetOptions(merge: true));
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[AUTH] Background tour member photo sync error: $e');
    }
  }

  /// Retrieves the profile photo URL from the user's Google account.
  /// Checks Firebase Auth providerData, then active GoogleSignIn user,
  /// and finally triggers silent/interactive Google Sign-In if necessary.
  Future<String?> getGoogleProfilePhotoUrl() async {
    // 1. Check providerData on the currently signed-in Firebase user
    final user = _auth.currentUser;
    if (user != null) {
      for (final profile in user.providerData) {
        if (profile.providerId == 'google.com' &&
            profile.photoURL != null &&
            profile.photoURL!.isNotEmpty) {
          return _enhanceGooglePhotoUrl(profile.photoURL!);
        }
      }
    }

    // 2. Check if GoogleSignIn has an active user
    try {
      var googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();
      if (googleUser?.photoUrl != null && googleUser!.photoUrl!.isNotEmpty) {
        return _enhanceGooglePhotoUrl(googleUser.photoUrl!);
      }

      // 3. Fallback to interactive Google Sign-In prompt
      googleUser = await _googleSignIn.signIn();
      if (googleUser?.photoUrl != null && googleUser!.photoUrl!.isNotEmpty) {
        return _enhanceGooglePhotoUrl(googleUser.photoUrl!);
      }
      return null;
    } catch (e) {
      debugPrint('[AUTH] Failed to get Google profile photo: $e');
      return null;
    }
  }

  String _enhanceGooglePhotoUrl(String url) {
    if (url.contains('googleusercontent.com') && url.contains('=s')) {
      return url.replaceAll(RegExp(r'=s\d+(-c)?'), '=s400-c');
    }
    return url;
  }

  Future<void> updateFcmToken(String uid, String token) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update({'fcmToken': token});
  }

  Future<bool> isUsernameAvailable(String username, {String? excludeUid}) async {
    try {
      final clean = username.toLowerCase().trim().replaceAll('@', '');
      if (clean.isEmpty) return false;
      final query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: clean)
          .limit(2)
          .get();
      if (query.docs.isEmpty) return true;
      if (excludeUid != null &&
          query.docs.length == 1 &&
          query.docs.first.id == excludeUid) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  User? get currentUser => _auth.currentUser;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
