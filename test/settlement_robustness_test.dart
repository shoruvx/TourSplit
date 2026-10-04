import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/settlement_model.dart';
import 'package:toursplit/data/models/tour_model.dart';

void main() {
  group('Settlement Robustness Tests', () {
    test('SettlementModel correctly parses ISO-8601 string dates from mesh/JSON', () {
      final isoDate = '2026-10-01T15:30:00.000Z';
      final resDate = '2026-10-01T16:00:00.000Z';
      final map = {
        'tourId': 'tour_test_1',
        'fromUserId': 'user_a',
        'fromUserName': 'Alice',
        'toUserId': 'user_b',
        'toUserName': 'Bob',
        'amount': 1500.50,
        'currency': 'BDT',
        'status': 'approved',
        'requestedAt': isoDate,
        'resolvedAt': resDate,
        'resolvedBy': 'user_b',
        'note': 'bKash paid',
      };

      final settlement = SettlementModel.fromMap(map, 'set_iso_1');
      expect(settlement.id, 'set_iso_1');
      expect(settlement.requestedAt.toUtc().toIso8601String(), equals(isoDate));
      expect(settlement.resolvedAt?.toUtc().toIso8601String(), equals(resDate));
      expect(settlement.isApproved, isTrue);
      expect(settlement.amount, equals(1500.50));
    });

    test('SettlementModel handles null or missing dates safely without crashing', () {
      final map = {
        'tourId': 'tour_test_2',
        'fromUserId': 'user_c',
        'fromUserName': 'Charlie',
        'toUserId': 'user_d',
        'toUserName': 'Diana',
        'amount': 250.0,
        'status': 'requested',
      };

      final settlement = SettlementModel.fromMap(map, 'set_safe_2');
      expect(settlement.id, 'set_safe_2');
      expect(settlement.isPending, isTrue);
      expect(settlement.resolvedAt, isNull);
      expect(settlement.requestedAt, isNotNull);
    });

    test('Member deduplication ensures exactly one entry per userId', () {
      final members = [
        TourMemberModel(
          userId: 'user_1',
          displayName: 'Alice',
          username: 'alice',
          email: 'alice@example.com',
          role: 'admin',
          status: 'active',
          joinedAt: DateTime.now(),
        ),
        TourMemberModel(
          userId: 'user_2',
          displayName: 'Bob',
          username: 'bob',
          email: 'bob@example.com',
          role: 'member',
          status: 'active',
          joinedAt: DateTime.now(),
        ),
        TourMemberModel(
          userId: 'user_1', // duplicate
          displayName: 'Alice (Duplicate)',
          username: 'alice',
          email: 'alice@example.com',
          role: 'admin',
          status: 'active',
          joinedAt: DateTime.now(),
        ),
      ];

      final uniqueMembersMap = <String, TourMemberModel>{};
      for (final m in members) {
        uniqueMembersMap[m.userId] = m;
      }
      final uniqueMembers = uniqueMembersMap.values.toList();

      expect(uniqueMembers.length, 2);
      expect(uniqueMembers.map((m) => m.userId).toSet(), containsAll(['user_1', 'user_2']));
    });

    test('Recipient candidates exclude payer and selects valid recipient safely', () {
      final members = [
        TourMemberModel(
          userId: 'u1',
          displayName: 'Alice',
          username: 'alice',
          email: '',
          role: 'admin',
          status: 'active',
          joinedAt: DateTime.now(),
        ),
        TourMemberModel(
          userId: 'u2',
          displayName: 'Bob',
          username: 'bob',
          email: '',
          role: 'member',
          status: 'active',
          joinedAt: DateTime.now(),
        ),
      ];

      String fromUid = 'u1';
      String toUid = 'u2';

      // When fromUid changes to u2
      fromUid = 'u2';
      final validRecipients = members.where((m) => m.userId != fromUid).toList();
      if (!validRecipients.any((m) => m.userId == toUid)) {
        toUid = validRecipients.isNotEmpty ? validRecipients.first.userId : '';
      }

      expect(fromUid, 'u2');
      expect(toUid, 'u1');
      expect(validRecipients.length, 1);
      expect(validRecipients.first.userId, 'u1');
    });
  });
}
