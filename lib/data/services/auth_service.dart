import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

/// Reactive stream of the current Firebase auth user
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provider for the current logged-in UserModel from Firestore
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
          // Document missing in Firestore: auto-create profile from auth credentials
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
    loading: () => const Stream.empty(), // Stay in loading until auth emits
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

  /// Register with email + password, save user doc to Firestore
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

    // Update display name
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

  /// Sign in with email + password — creates Firestore doc if missing
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;

    // Ensure Firestore user document exists (may be missing if created before rules were set)
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
        firstName: nameParts.isNotEmpty ? nameParts.first : email.split('@').first,
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

  /// Sign in with Google
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

    // Check if user exists in Firestore
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      // New Google user — create profile
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

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Sign out from Firebase and Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Update FCM token in user doc
  Future<void> updateFcmToken(String uid, String token) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update({'fcmToken': token});
  }

  /// Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();
      return query.docs.isEmpty;
    } catch (_) {
      return true; // Allow registration if rules restrict unauthenticated user queries
    }
  }

  User? get currentUser => _auth.currentUser;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
