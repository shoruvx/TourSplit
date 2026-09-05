import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
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
          return UserModel.fromFirestore(doc);
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
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '57491876636-hssqr3kr22ul02175nrufl5953h88po6.apps.googleusercontent.com',
  );

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

      return userModel;
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
    required String firstName,
    required String lastName,
    String? activeTourId,
  }) async {
    final cleanFirst = firstName.trim();
    final cleanLast = lastName.trim();
    final fullName =
        cleanLast.isNotEmpty ? '$cleanFirst $cleanLast' : cleanFirst;

    // 1. Update Firebase Auth displayName
    final user = _auth.currentUser;
    if (user != null) {
      await user.updateDisplayName(fullName);
    }

    // 2. Update Firestore users collection
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'firstName': cleanFirst,
      'lastName': cleanLast,
    });

    // 3. Update member document in active tour if present
    if (activeTourId != null && activeTourId.isNotEmpty) {
      try {
        await _firestore
            .collection(AppConstants.toursCollection)
            .doc(activeTourId)
            .collection(AppConstants.membersSubcollection)
            .doc(uid)
            .update({
          'displayName': fullName,
        });
      } catch (_) {}
    }
  }

  Future<void> updateFcmToken(String uid, String token) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update({'fcmToken': token});
  }

  Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();
      return query.docs.isEmpty;
    } catch (_) {
      return true;
    }
  }

  User? get currentUser => _auth.currentUser;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
