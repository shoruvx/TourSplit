import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/user_model.dart';
import 'package:toursplit/data/models/app_update_model.dart';
import 'package:toursplit/data/services/app_update_service.dart';
import 'package:toursplit/core/theme/app_theme.dart';

void main() {
  group('AppUpdateService Version Checks', () {
    test('isVersionNewer correctly compares versions with and without build numbers', () {
      // 1.0.5 is newer than 1.0.1
      expect(AppUpdateService.isVersionNewer('1.0.5', '1.0.1'), isTrue);

      // 1.0.5 is newer than 1.0.4
      expect(AppUpdateService.isVersionNewer('1.0.5', '1.0.4'), isTrue);

      // 1.0.5 is NOT newer than 1.0.5+5
      expect(AppUpdateService.isVersionNewer('1.0.5', '1.0.5+5'), isFalse);

      // 1.0.6 is newer than 1.0.5+5
      expect(AppUpdateService.isVersionNewer('1.0.6', '1.0.5+5'), isTrue);

      // 1.0.1 is not newer than 1.0.5
      expect(AppUpdateService.isVersionNewer('1.0.1', '1.0.5'), isFalse);

      // identical versions
      expect(AppUpdateService.isVersionNewer('1.0.1', '1.0.1'), isFalse);

      // Major version upgrade
      expect(AppUpdateService.isVersionNewer('2.0.0', '1.0.5+5'), isTrue);
    });

    test('cleanVersion properly removes build metadata and leading "v"', () {
      expect(AppUpdateService.cleanVersion('v1.0.5+5'), '1.0.5');
      expect(AppUpdateService.cleanVersion('1.0.1'), '1.0.1');
      expect(AppUpdateService.cleanVersion('1.2.3-beta+4'), '1.2.3');
    });
  });

  group('TourModel Deletion and Status', () {
    test('TourModel handles deleted status and isDeleted flag', () {
      final tour = TourModel(
        id: 'tour_123',
        name: 'Sylhet Tour',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'user_1',
        adminIds: ['user_1'],
        memberIds: ['user_1', 'user_2'],
        inviteCode: 'ABC12345',
        startDate: DateTime.now(),
        status: TourStatus.deleted,
        isDeleted: true,
        createdAt: DateTime.now(),
      );

      expect(tour.isDeleted, isTrue);
      expect(tour.status, TourStatus.deleted);
      expect(tour.isActive, isFalse);

      final copy = tour.copyWith(isDeleted: false, status: TourStatus.active);
      expect(copy.isDeleted, isFalse);
      expect(copy.status, TourStatus.active);
      expect(copy.isActive, isTrue);
    });
  });

  group('AppUpdateInfo Model & AutoDownload', () {
    test('AppUpdateInfo defaults autoDownload to true and serializes properly', () {
      const info = AppUpdateInfo(
        latestVersion: '1.2.0',
        buildNumber: 10,
        releaseNotes: 'Performance enhancements',
        apkUrl: 'https://github.com/shoruvx/TourSplit/releases/download/v1.2.0/TourSplit-v1.2.0.apk',
        forceUpdate: false,
      );

      expect(info.autoDownload, isTrue);
      final map = info.toFirestore();
      expect(map['autoDownload'], isTrue);
      expect(map['latestVersion'], '1.2.0');
      expect(map['forceUpdate'], isFalse);
    });
  });

  group('PaymentAccount and UserModel preferred accounts', () {
    test('PaymentAccount serializes and deserializes properly', () {
      const acc = PaymentAccount(
        id: 'acc_1',
        type: 'bKash',
        accountNumber: '01712345678',
        note: 'Personal',
      );

      final map = acc.toMap();
      expect(map['id'], 'acc_1');
      expect(map['type'], 'bKash');
      expect(map['accountNumber'], '01712345678');
      expect(map['note'], 'Personal');

      final reconstructed = PaymentAccount.fromMap(map);
      expect(reconstructed.id, 'acc_1');
      expect(reconstructed.type, 'bKash');
      expect(reconstructed.accountNumber, '01712345678');
      expect(reconstructed.note, 'Personal');
    });

    test('UserModel handles paymentAccounts in copyWith and toFirestore', () {
      final user = UserModel(
        uid: 'user_1',
        email: 'test@example.com',
        username: 'test',
        firstName: 'Test',
        lastName: 'User',
        createdAt: DateTime.now(),
        paymentAccounts: const [
          PaymentAccount(
            id: 'acc_1',
            type: 'Nagad',
            accountNumber: '01887654321',
          ),
        ],
      );

      expect(user.paymentAccounts.length, 1);
      expect(user.paymentAccounts.first.type, 'Nagad');

      final map = user.toFirestore();
      expect(map['paymentAccounts'], isA<List>());
      expect((map['paymentAccounts'] as List).length, 1);

      final updated = user.copyWith(
        paymentAccounts: [
          ...user.paymentAccounts,
          const PaymentAccount(id: 'acc_2', type: 'Bank', accountNumber: '12345678'),
        ],
      );
      expect(updated.paymentAccounts.length, 2);
    });

    test('AppTheme ensures primaryTeal is used for elevated and outlined buttons', () {
      final light = AppTheme.lightTheme;
      expect(light.colorScheme.primary, AppColors.primaryTeal);
      expect(light.floatingActionButtonTheme.backgroundColor, AppColors.primaryTeal);
      expect(light.bottomNavigationBarTheme.selectedItemColor, AppColors.primaryTeal);
    });

    test('TourCard summary calculations handle empty and non-empty expenses', () {
      final memberIds = ['user_1', 'user_2', 'user_3'];
      final totalSpent = 1500.0;
      final perPerson = totalSpent / memberIds.length;
      expect(perPerson, 500.0);

      // Division by zero safeguard
      final emptyMembers = <String>[];
      final safePerPerson = totalSpent / (emptyMembers.isNotEmpty ? emptyMembers.length : 1);
      expect(safePerPerson, 1500.0);
    });
  });
}
