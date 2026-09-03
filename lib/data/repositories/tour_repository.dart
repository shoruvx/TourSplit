import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tour_model.dart';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

class TourRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _tours =>
      _db.collection(AppConstants.toursCollection);

  /// Create a new tour, set admin as first member
  Future<TourModel> createTour({
    required String name,
    String? description,
    required String currency,
    required String currencySymbol,
    required String adminId,
    required DateTime startDate,
    DateTime? endDate,
    double? budget,
    String? coverImageUrl,
  }) async {
    final inviteCode = _generateInviteCode();

    final tourData = {
      'name': name,
      'description': description,
      'currency': currency,
      'currencySymbol': currencySymbol,
      'adminId': adminId,
      'inviteCode': inviteCode,
      'status': 'active',
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
      'budget': budget,
      'coverImageUrl': coverImageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'members': [adminId],
    };

    final docRef = await _tours.add(tourData);
    final doc = await docRef.get();
    final tour = TourModel.fromFirestore(doc);

    // Update user's activeTourId
    await _db
        .collection(AppConstants.usersCollection)
        .doc(adminId)
        .update({'activeTourId': docRef.id});

    return tour;
  }

  /// Get a tour by invite code (handles 0/O, 1/I ambiguity and cleans spaces/dashes)
  Future<TourModel?> getTourByInviteCode(String code) async {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');
    if (clean.isEmpty) return null;

    // Build candidates list to check
    final candidates = <String>[clean];

    // Swapping 0 and O
    if (clean.contains('0')) candidates.add(clean.replaceAll('0', 'O'));
    if (clean.contains('O')) candidates.add(clean.replaceAll('O', '0'));

    // Swapping 1 and I
    if (clean.contains('1')) candidates.add(clean.replaceAll('1', 'I'));
    if (clean.contains('I')) candidates.add(clean.replaceAll('I', '1'));

    print('[INVITE_DEBUG] Searching for clean: "$clean", candidates: $candidates');
    for (final candidate in candidates) {
      try {
        final query = await _tours
            .where('inviteCode', isEqualTo: candidate)
            .limit(1)
            .get();

        print('[INVITE_DEBUG] Candidate "$candidate" found ${query.docs.length} docs');
        if (query.docs.isNotEmpty) {
          final tour = TourModel.fromFirestore(query.docs.first);
          print('[INVITE_DEBUG] Tour: "${tour.name}", code: "${tour.inviteCode}", status: "${tour.status}"');
          return tour;
        }
      } catch (e, st) {
        print('[INVITE_DEBUG] ERROR querying candidate "$candidate": $e\n$st');
      }
    }

    return null;
  }

  /// Join tour — add user to members array and create member subcollection doc
  Future<void> joinTour({
    required String tourId,
    required UserModel user,
  }) async {
    final batch = _db.batch();

    // Add to members array
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([user.uid]),
    });

    // Add member subcollection doc
    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(user.uid);
    batch.set(memberRef, {
      'userId': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoUrl,
      'role': 'member',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });

    // Update user's activeTourId
    final userRef = _db
        .collection(AppConstants.usersCollection)
        .doc(user.uid);
    batch.update(userRef, {'activeTourId': tourId});

    await batch.commit();
  }

  /// Add admin as member subcollection doc (called after tour creation)
  Future<void> addAdminAsMember({
    required String tourId,
    required UserModel admin,
  }) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(admin.uid)
        .set({
      'userId': admin.uid,
      'displayName': admin.displayName,
      'email': admin.email,
      'photoUrl': admin.photoUrl,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });
  }

  /// Invite member by email — creates a pending invite record
  Future<void> inviteMemberByEmail({
    required String tourId,
    required String email,
    required String inviterName,
  }) async {
    // In a real app you'd send a Cloud Function–triggered email.
    // Here we store a pending invite that the user can pick up on login.
    await _db.collection('invites').add({
      'tourId': tourId,
      'email': email.toLowerCase(),
      'inviterName': inviterName,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  /// Stream of a specific tour
  Stream<TourModel?> watchTour(String tourId) {
    return _tours.doc(tourId).snapshots().map(
          (doc) => doc.exists ? TourModel.fromFirestore(doc) : null,
        );
  }

  /// Stream of all active members of a tour
  Stream<List<TourMemberModel>> watchMembers(String tourId) {
    return _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TourMemberModel.fromFirestore(d))
            .where((m) => m.role != 'pending' && m.role != 'rejected')
            .toList());
  }

  /// Update tour details (admin only)
  Future<void> updateTour(String tourId, Map<String, dynamic> data) async {
    await _tours.doc(tourId).update(data);
  }

  /// Complete/end a tour
  Future<void> completeTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'completed',
      'endDate': FieldValue.serverTimestamp(),
    });
  }

  /// Reopen a completed tour
  Future<void> reopenTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'active',
      'endDate': null,
    });
  }

  /// Remove member from tour (admin only)
  Future<void> removeMember(String tourId, String userId) async {
    final batch = _db.batch();
    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayRemove([userId]),
    });
    batch.delete(_tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId));
    await batch.commit();

    // Best-effort attempt to clear activeTourId on user's doc
    try {
      await _db.collection(AppConstants.usersCollection).doc(userId).update({
        'activeTourId': null,
      });
    } catch (_) {
      // Handled gracefully if rules restrict updating another user's profile
    }
  }

  /// Clear activeTourId for a user (called directly from the user's client when leaving or ejected)
  Future<void> clearUserActiveTour(String userId) async {
    try {
      await _db.collection(AppConstants.usersCollection).doc(userId).update({
        'activeTourId': null,
      });
    } catch (_) {}
  }

  /// Switch active tour for a user
  Future<void> switchActiveTour(String userId, String tourId) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'activeTourId': tourId,
    });
  }

  /// Submit request to join a tour (waiting for admin approval)
  Future<void> requestToJoinTour({
    required String tourId,
    required String tourName,
    required UserModel user,
  }) async {
    // 1. Write to members subcollection with role: 'pending'
    // This is permitted by the existing cloud security rule: match /members/{memberId} { allow create, update: if isLoggedIn(); }
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(user.uid)
        .set({
      'tourId': tourId,
      'tourName': tourName,
      'userId': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoUrl,
      'role': 'pending',
      'status': 'pending',
      'joinedAt': FieldValue.serverTimestamp(),
      'requestedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });

    // 2. Also try writing to join_requests in case rules are updated
    try {
      await _tours.doc(tourId).collection('join_requests').doc(user.uid).set({
        'tourId': tourId,
        'tourName': tourName,
        'userId': user.uid,
        'displayName': user.displayName,
        'email': user.email,
        'photoUrl': user.photoUrl,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Watch an individual user's join request for a tour
  Stream<JoinRequestModel?> watchUserJoinRequest(String tourId, String userId) {
    return _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      final role = data['role'] ?? 'member';
      final status = (role == 'member' || role == 'admin')
          ? 'approved'
          : (role == 'rejected' ? 'rejected' : (data['status'] ?? 'pending'));
      return JoinRequestModel(
        id: doc.id,
        tourId: data['tourId'] ?? tourId,
        tourName: data['tourName'] ?? '',
        userId: data['userId'] ?? userId,
        displayName: data['displayName'] ?? '',
        email: data['email'] ?? '',
        photoUrl: data['photoUrl'],
        status: status,
        requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    });
  }

  /// Watch pending join requests for a tour (admins)
  Stream<List<JoinRequestModel>> watchTourJoinRequests(String tourId) {
    return _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .where('role', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return JoinRequestModel(
                id: d.id,
                tourId: data['tourId'] ?? tourId,
                tourName: data['tourName'] ?? '',
                userId: data['userId'] ?? d.id,
                displayName: data['displayName'] ?? 'Member',
                email: data['email'] ?? '',
                photoUrl: data['photoUrl'],
                status: data['status'] ?? 'pending',
                requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList());
  }

  /// Approve a member's join request
  Future<void> approveJoinRequest({
    required String tourId,
    required JoinRequestModel request,
  }) async {
    // 1. Update member subcollection document to active member
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(request.userId)
        .set({
      'userId': request.userId,
      'displayName': request.displayName,
      'email': request.email,
      'photoUrl': request.photoUrl,
      'role': 'member',
      'status': 'approved',
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    }, SetOptions(merge: true));

    // 2. Add user to tour members array
    await _tours.doc(tourId).update({
      'members': FieldValue.arrayUnion([request.userId]),
    });
  }

  /// Reject a member's join request
  Future<void> rejectJoinRequest({
    required String tourId,
    required String userId,
  }) async {
    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId);
    await memberRef.set({
      'role': 'rejected',
      'status': 'rejected',
    }, SetOptions(merge: true));

    try {
      await _tours.doc(tourId).collection('join_requests').doc(userId).update({'status': 'rejected'});
    } catch (_) {}
  }

  /// Set member role (e.g. promote to 'admin' or demote to 'member')
  Future<void> setMemberRole({
    required String tourId,
    required String userId,
    required String role,
  }) async {
    final batch = _db.batch();

    if (role == 'admin') {
      batch.update(_tours.doc(tourId), {
        'adminIds': FieldValue.arrayUnion([userId]),
      });
    } else {
      batch.update(_tours.doc(tourId), {
        'adminIds': FieldValue.arrayRemove([userId]),
      });
    }

    batch.update(
      _tours
          .doc(tourId)
          .collection(AppConstants.membersSubcollection)
          .doc(userId),
      {'role': role},
    );

    await batch.commit();
  }

  /// Stream all tours that a user belongs to
  Stream<List<TourModel>> watchUserTours(String userId) {
    return _tours
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => TourModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Update a member's balance
  Future<void> updateMemberBalance(
      String tourId, String userId, double balance) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId)
        .update({'balance': balance});
  }

  /// Get a one-time snapshot of a tour
  Future<TourModel?> getTour(String tourId) async {
    final doc = await _tours.doc(tourId).get();
    return doc.exists ? TourModel.fromFirestore(doc) : null;
  }

  /// Generate a random 6-character uppercase invite code (avoiding 0/O and 1/I)
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      AppConstants.inviteCodeLength,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }
}

final tourRepositoryProvider = Provider<TourRepository>((_) => TourRepository());

/// Stream a single tour by ID (family provider so it caches per tourId)
final tourStreamProvider = StreamProvider.family<TourModel?, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTour(tourId);
});

/// Stream members for a tour by ID
final tourMembersStreamProvider =
    StreamProvider.family<List<TourMemberModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchMembers(tourId);
});

/// Stream pending join requests for a tour (admins)
final tourPendingJoinRequestsProvider =
    StreamProvider.family<List<JoinRequestModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTourJoinRequests(tourId);
});

/// Stream all tours a user is a member of
final userToursStreamProvider =
    StreamProvider.family<List<TourModel>, String>((ref, userId) {
  return ref.watch(tourRepositoryProvider).watchUserTours(userId);
});

