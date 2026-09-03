import 'package:cloud_firestore/cloud_firestore.dart';

enum TourStatus { active, completed }

class TourModel {
  final String id;
  final String name;
  final String? description;
  final String currency;
  final String currencySymbol;
  final String adminId;
  final String inviteCode;
  final TourStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final double? budget;
  final String? coverImageUrl;
  final List<String> memberIds;
  final List<String> adminIds;

  const TourModel({
    required this.id,
    required this.name,
    this.description,
    required this.currency,
    required this.currencySymbol,
    required this.adminId,
    required this.inviteCode,
    required this.status,
    required this.startDate,
    this.endDate,
    required this.createdAt,
    required this.memberIds,
    this.adminIds = const [],
    this.budget,
    this.coverImageUrl,
  });

  bool get isActive => status == TourStatus.active;
  bool isAdmin(String userId) => adminIds.contains(userId) || adminId == userId;

  factory TourModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final creatorAdminId = data['adminId'] ?? '';
    final rawAdminIds = data['adminIds'] != null
        ? List<String>.from(data['adminIds'])
        : <String>[creatorAdminId];
    if (creatorAdminId.isNotEmpty && !rawAdminIds.contains(creatorAdminId)) {
      rawAdminIds.add(creatorAdminId);
    }

    return TourModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      currency: data['currency'] ?? 'BDT',
      currencySymbol: data['currencySymbol'] ?? '৳',
      adminId: creatorAdminId,
      inviteCode: data['inviteCode'] ?? '',
      status: data['status'] == 'completed'
          ? TourStatus.completed
          : TourStatus.active,
      startDate:
          (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberIds: List<String>.from(data['members'] ?? []),
      adminIds: rawAdminIds,
      budget: (data['budget'] as num?)?.toDouble(),
      coverImageUrl: data['coverImageUrl'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        'currency': currency,
        'currencySymbol': currencySymbol,
        'adminId': adminId,
        'adminIds': adminIds.isNotEmpty ? adminIds : [adminId],
        'inviteCode': inviteCode,
        'status': status.name,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'createdAt': Timestamp.fromDate(createdAt),
        'members': memberIds,
        'budget': budget,
        'coverImageUrl': coverImageUrl,
      };

  TourModel copyWith({
    String? name,
    String? description,
    String? currency,
    String? currencySymbol,
    TourStatus? status,
    DateTime? endDate,
    List<String>? memberIds,
  }) {
    return TourModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      adminId: adminId,
      inviteCode: inviteCode,
      status: status ?? this.status,
      startDate: startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}

class TourMemberModel {
  final String userId;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;
  final double balance; // positive = owed, negative = owes

  const TourMemberModel({
    required this.userId,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.role,
    required this.joinedAt,
    this.balance = 0.0,
  });

  bool get isAdmin => role == 'admin';
  bool get isPositive => balance > 0;
  bool get isNegative => balance < 0;
  bool get isSettled => balance == 0;

  String get initials {
    final clean = displayName.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  factory TourMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TourMemberModel(
      userId: doc.id,
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      role: data['role'] ?? 'member',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'role': role,
        'joinedAt': Timestamp.fromDate(joinedAt),
        'balance': balance,
      };

  TourMemberModel copyWith({double? balance, String? role}) {
    return TourMemberModel(
      userId: userId,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
      role: role ?? this.role,
      joinedAt: joinedAt,
      balance: balance ?? this.balance,
    );
  }
}

class JoinRequestModel {
  final String id;
  final String tourId;
  final String tourName;
  final String userId;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime requestedAt;

  const JoinRequestModel({
    required this.id,
    required this.tourId,
    required this.tourName,
    required this.userId,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.status,
    required this.requestedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  factory JoinRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JoinRequestModel(
      id: doc.id,
      tourId: data['tourId'] ?? '',
      tourName: data['tourName'] ?? '',
      userId: data['userId'] ?? '',
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      status: data['status'] ?? 'pending',
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'tourId': tourId,
        'tourName': tourName,
        'userId': userId,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'status': status,
        'requestedAt': Timestamp.fromDate(requestedAt),
      };
}

