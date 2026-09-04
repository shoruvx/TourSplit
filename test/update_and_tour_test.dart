import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/services/app_update_service.dart';

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
}
