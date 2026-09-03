import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String username;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String? fcmToken;
  final DateTime createdAt;
  final String? activeTourId;

  const UserModel({
    required this.uid,
    required this.email,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    this.fcmToken,
    required this.createdAt,
    this.activeTourId,
  });

  String get displayName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      username: data['username'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      photoUrl: data['photoUrl'],
      fcmToken: data['fcmToken'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      activeTourId: data['activeTourId'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'username': username,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': photoUrl,
        'fcmToken': fcmToken,
        'createdAt': Timestamp.fromDate(createdAt),
        'activeTourId': activeTourId,
      };

  UserModel copyWith({
    String? email,
    String? username,
    String? firstName,
    String? lastName,
    String? photoUrl,
    String? fcmToken,
    String? activeTourId,
    bool clearActiveTour = false,
  }) {
    return UserModel(
      uid: uid,
      email: email ?? this.email,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      photoUrl: photoUrl ?? this.photoUrl,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt,
      activeTourId:
          clearActiveTour ? null : (activeTourId ?? this.activeTourId),
    );
  }
}
