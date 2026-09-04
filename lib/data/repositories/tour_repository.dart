import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tour_model.dart';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

class TourRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _tours =>
      _db.collection(AppConstants.toursCollection);

  CollectionReference get _users =>
      _db.collection(AppConstants.usersCollection);

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

    await _db
        .collection(AppConstants.usersCollection)
        .doc(adminId)
        .update({'activeTourId': docRef.id});

    return tour;
  }

  Future<TourModel?> getTourByInviteCode(String code) async {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');
    if (clean.isEmpty) return null;

    final candidates = <String>[clean];

    if (clean.contains('0')) candidates.add(clean.replaceAll('0', 'O'));
    if (clean.contains('O')) candidates.add(clean.replaceAll('O', '0'));

    if (clean.contains('1')) candidates.add(clean.replaceAll('1', 'I'));
    if (clean.contains('I')) candidates.add(clean.replaceAll('I', '1'));

    print(
        '[INVITE_DEBUG] Searching for clean: "$clean", candidates: $candidates');
    for (final candidate in candidates) {
      try {
        final query = await _tours
            .where('inviteCode', isEqualTo: candidate)
            .limit(1)
            .get();

        print(
            '[INVITE_DEBUG] Candidate "$candidate" found ${query.docs.length} docs');
        if (query.docs.isNotEmpty) {
          final tour = TourModel.fromFirestore(query.docs.first);
          print(
              '[INVITE_DEBUG] Tour: "${tour.name}", code: "${tour.inviteCode}", status: "${tour.status}"');
          return tour;
        }
      } catch (e, st) {
        print('[INVITE_DEBUG] ERROR querying candidate "$candidate": $e\n$st');
      }
    }

    return null;
  }

  Future<void> joinTour({
    required String tourId,
    required UserModel user,
  }) async {
    final batch = _db.batch();

    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([user.uid]),
    });

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

    final userRef = _db.collection(AppConstants.usersCollection).doc(user.uid);
    batch.update(userRef, {'activeTourId': tourId});

    await batch.commit();
  }

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

  Future<void> inviteMemberByEmail({
    required String tourId,
    required String email,
    required String inviterName,
  }) async {
    await _db.collection('invites').add({
      'tourId': tourId,
      'email': email.toLowerCase(),
      'inviterName': inviterName,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Stream<TourModel?> watchTour(String tourId) {
    return _tours.doc(tourId).snapshots().map(
          (doc) => doc.exists ? TourModel.fromFirestore(doc) : null,
        );
  }

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

  Future<void> updateTour(String tourId, Map<String, dynamic> data) async {
    await _tours.doc(tourId).update(data);
  }

  Future<void> completeTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'completed',
      'endDate': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reopenTour(String tourId) async {
    await _tours.doc(tourId).update({
      'status': 'active',
      'endDate': null,
    });
  }

  Future<void> deleteTour(String tourId, {String? currentUserId}) async {
    // 1. Remove current user from members array and clear activeTourId immediately
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        await _tours.doc(tourId).update({
          'members': FieldValue.arrayRemove([currentUserId]),
        });
      } catch (_) {}
      try {
        await _users.doc(currentUserId).update({'activeTourId': null});
      } catch (_) {}
    }

    // 2. Soft-mark as deleted and clear remaining members list so all listeners drop it instantly
    try {
      await _tours.doc(tourId).update({
        'isDeleted': true,
        'status': 'deleted',
        'members': [],
      });
    } catch (_) {}

    // 3. Collect member IDs from subcollection to clear their activeTourId
    final membersSnap = await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .get();
    final memberIds = membersSnap.docs.map((d) => d.id).toSet();
    if (currentUserId != null) memberIds.add(currentUserId);

    final subcollections = [
      AppConstants.membersSubcollection,
      AppConstants.expensesSubcollection,
      AppConstants.settlementsSubcollection,
      AppConstants.categoriesSubcollection,
      'join_requests',
    ];

    for (final sub in subcollections) {
      try {
        final snap = await _tours.doc(tourId).collection(sub).get();
        const batchLimit = 499;
        for (int i = 0; i < snap.docs.length; i += batchLimit) {
          final batch = _db.batch();
          final chunk = snap.docs.skip(i).take(batchLimit);
          for (final doc in chunk) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (_) {}
    }

    try {
      await _tours.doc(tourId).delete();
    } catch (_) {}

    for (final uid in memberIds) {
      try {
        await _db
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update({'activeTourId': null});
      } catch (_) {}
    }
  }

  Future<TourMemberModel> addOfflineMember({
    required String tourId,
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Name cannot be empty');

    final memberId = 'offline_${const Uuid().v4()}';
    final batch = _db.batch();

    batch.update(_tours.doc(tourId), {
      'members': FieldValue.arrayUnion([memberId]),
    });

    final memberRef = _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(memberId);

    batch.set(memberRef, {
      'userId': memberId,
      'displayName': cleanName,
      'email': '',
      'photoUrl': null,
      'role': 'member',
      'isOffline': true,
      'joinedAt': FieldValue.serverTimestamp(),
      'balance': 0.0,
    });

    await batch.commit();

    return TourMemberModel(
      userId: memberId,
      displayName: cleanName,
      email: '',
      photoUrl: null,
      role: 'member',
      isOffline: true,
      joinedAt: DateTime.now(),
      balance: 0.0,
    );
  }

  Future<void> updateOfflineMemberName({
    required String tourId,
    required String memberId,
    required String newName,
  }) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;

    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(memberId)
        .update({
      'displayName': cleanName,
    });
  }

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

    if (!userId.startsWith('offline_')) {
      try {
        await _db.collection(AppConstants.usersCollection).doc(userId).update({
          'activeTourId': null,
        });
      } catch (_) {}
    }
  }

  Future<void> clearUserActiveTour(String userId) async {
    try {
      await _db.collection(AppConstants.usersCollection).doc(userId).update({
        'activeTourId': null,
      });
    } catch (_) {}
  }

  Future<void> switchActiveTour(String userId, String tourId) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'activeTourId': tourId,
    });
  }

  Future<void> requestToJoinTour({
    required String tourId,
    required String tourName,
    required UserModel user,
  }) async {
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
        requestedAt:
            (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    });
  }

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
                requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              );
            }).toList());
  }

  Future<void> approveJoinRequest({
    required String tourId,
    required JoinRequestModel request,
  }) async {
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

    await _tours.doc(tourId).update({
      'members': FieldValue.arrayUnion([request.userId]),
    });

    try {
      await _users.doc(request.userId).set({
        'activeTourId': tourId,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

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
      await _tours
          .doc(tourId)
          .collection('join_requests')
          .doc(userId)
          .update({'status': 'rejected'});
    } catch (_) {}
  }

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

  Stream<List<TourModel>> watchUserTours(String userId) {
    return _tours
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .where((d) => d.exists)
          .map((d) => TourModel.fromFirestore(d))
          .where((t) => !t.isDeleted && t.status != TourStatus.deleted)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateMemberBalance(
      String tourId, String userId, double balance) async {
    await _tours
        .doc(tourId)
        .collection(AppConstants.membersSubcollection)
        .doc(userId)
        .update({'balance': balance});
  }

  Future<TourModel?> getTour(String tourId) async {
    final doc = await _tours.doc(tourId).get();
    return doc.exists ? TourModel.fromFirestore(doc) : null;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      AppConstants.inviteCodeLength,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }
}

final tourRepositoryProvider =
    Provider<TourRepository>((_) => TourRepository());

final tourStreamProvider =
    StreamProvider.family<TourModel?, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTour(tourId);
});

final tourMembersStreamProvider =
    StreamProvider.family<List<TourMemberModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchMembers(tourId);
});

final tourPendingJoinRequestsProvider =
    StreamProvider.family<List<JoinRequestModel>, String>((ref, tourId) {
  return ref.watch(tourRepositoryProvider).watchTourJoinRequests(tourId);
});

final userToursStreamProvider =
    StreamProvider.family<List<TourModel>, String>((ref, userId) {
  return ref.watch(tourRepositoryProvider).watchUserTours(userId);
});
