import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/user_model.dart';
import 'package:toursplit/core/theme/app_theme.dart';

void main() {
  group('Mistaken Member Removal & Member Lists', () {
    test('Mistakenly added member can be cleanly removed from TourModel', () {
      final initialTour = TourModel(
        id: 'tour_1',
        name: 'Cox\'s Bazar Trip',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_1',
        memberIds: ['admin_1', 'mistaken_member'],
        inviteCode: 'TRP123',
        status: TourStatus.active,
        startDate: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(initialTour.memberIds.length, 2);
      expect(initialTour.isMember('mistaken_member'), isTrue);

      // Clean removal of mistakenly added member
      final updatedMembers = List<String>.from(initialTour.memberIds)
        ..remove('mistaken_member');
      final updatedTour = initialTour.copyWith(memberIds: updatedMembers);

      expect(updatedTour.memberIds.length, 1);
      expect(updatedTour.isMember('mistaken_member'), isFalse);
      expect(updatedTour.memberIds, contains('admin_1'));
    });
  });

  group('UserModel Username & Privacy Display', () {
    test('Username replaces email in privacy-safe handles', () {
      final user = UserModel(
        uid: 'u1',
        email: 'alex.smith@example.com',
        username: 'alexsmith',
        firstName: 'Alex Smith',
        lastName: '',
        createdAt: DateTime.now(),
      );

      expect(user.username, 'alexsmith');
      expect(user.displayName, 'Alex Smith');

      // Handle without exposing domain
      final handle = user.username.isNotEmpty
          ? user.username
          : user.email.split('@').first;
      expect(handle, 'alexsmith');
      expect('@$handle', '@alexsmith');
    });

    test('Fallback to email prefix when username is not set', () {
      final user = UserModel(
        uid: 'u2',
        email: 'traveler99@domain.org',
        username: '',
        firstName: 'Traveler',
        lastName: '',
        createdAt: DateTime.now(),
      );

      final handle = user.username.isNotEmpty
          ? user.username
          : user.email.split('@').first;
      expect(handle, 'traveler99');
      expect('@$handle', '@traveler99');
    });
  });

  group('Typography & Font Fallbacks', () {
    test('AppTheme includes Apple San Francisco in fontFallbacks', () {
      final lightTheme = AppTheme.lightTheme;
      final darkTheme = AppTheme.darkTheme;

      expect(lightTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('.SF Pro Text'));
      expect(lightTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('Outfit'));

      expect(darkTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('.SF Pro Text'));
      expect(darkTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('Outfit'));
    });
  });
}
