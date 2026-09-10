import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentAccount {
  final String id;
  final String type; // e.g. "bKash", "Nagad", "Rocket", "Bank", or custom
  final String accountNumber;
  final String? note;

  const PaymentAccount({
    required this.id,
    required this.type,
    required this.accountNumber,
    this.note,
  });

  factory PaymentAccount.fromMap(Map<String, dynamic> map) {
    return PaymentAccount(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? 'bKash',
      accountNumber: map['accountNumber'] as String? ?? '',
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'accountNumber': accountNumber,
        'note': note,
      };
}

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
  final List<PaymentAccount> paymentAccounts;

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
    this.paymentAccounts = const [],
  });

  String get displayName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    DateTime parsedCreatedAt;
    try {
      final rawCreatedAt = data['createdAt'];
      if (rawCreatedAt is Timestamp) {
        parsedCreatedAt = rawCreatedAt.toDate();
      } else if (rawCreatedAt is String) {
        parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
      } else {
        parsedCreatedAt = DateTime.now();
      }
    } catch (_) {
      parsedCreatedAt = DateTime.now();
    }

    final rawAccounts = data['paymentAccounts'] as List<dynamic>?;
    final parsedAccounts = rawAccounts != null
        ? rawAccounts
            .whereType<Map>()
            .map((m) =>
                PaymentAccount.fromMap(Map<String, dynamic>.from(m)))
            .toList()
        : <PaymentAccount>[];

    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      fcmToken: data['fcmToken'] as String?,
      createdAt: parsedCreatedAt,
      activeTourId: data['activeTourId'] as String?,
      paymentAccounts: parsedAccounts,
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
        'paymentAccounts': paymentAccounts.map((a) => a.toMap()).toList(),
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
    List<PaymentAccount>? paymentAccounts,
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
      paymentAccounts: paymentAccounts ?? this.paymentAccounts,
    );
  }
}
