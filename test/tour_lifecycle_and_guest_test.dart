import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/services/tour_lifecycle_service.dart';
import 'package:toursplit/presentation/widgets/login_required_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tour Inactivity Lifecycle Model Tests', () {
    test('recent tour has low inactiveDays and is neither pending nor expired', () {
      final now = DateTime.now();
      final tour = TourModel(
        id: 'tour_recent',
        name: 'Recent Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 10)),
        createdAt: now.subtract(const Duration(days: 10)),
        lastActivityAt: now.subtract(const Duration(days: 4)),
      );

      expect(tour.inactiveDays, 4);
      expect(tour.isPendingAutoDeletion, isFalse);
      expect(tour.isExpiredByInactivity, isFalse);
      expect(tour.isLockedForDeletion, isFalse);
    });

    test('tour with 25 days inactivity is pending auto-deletion with 5 days remaining', () {
      final now = DateTime.now();
      final tour = TourModel(
        id: 'tour_warn',
        name: 'Warning Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 40)),
        createdAt: now.subtract(const Duration(days: 40)),
        lastActivityAt: now.subtract(const Duration(days: 25)),
      );

      expect(tour.inactiveDays, 25);
      expect(tour.isPendingAutoDeletion, isTrue);
      expect(tour.daysUntilAutoDeletion, 5);
      expect(tour.isExpiredByInactivity, isFalse);
      expect(tour.isLockedForDeletion, isTrue);
    });

    test('tour with >= 30 days inactivity is expired for auto-deletion', () {
      final now = DateTime.now();
      final tour = TourModel(
        id: 'tour_expired',
        name: 'Expired Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 60)),
        createdAt: now.subtract(const Duration(days: 60)),
        lastActivityAt: now.subtract(const Duration(days: 31)),
      );

      expect(tour.inactiveDays, 31);
      expect(tour.isPendingAutoDeletion, isFalse);
      expect(tour.isExpiredByInactivity, isTrue);
      expect(tour.isLockedForDeletion, isTrue);
    });

    test('tour without lastActivityAt falls back to createdAt', () {
      final now = DateTime.now();
      final tour = TourModel(
        id: 'tour_no_activity',
        name: 'No Activity Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 24)),
        createdAt: now.subtract(const Duration(days: 24)),
        lastActivityAt: null,
      );

      expect(tour.effectiveLastActivity, tour.createdAt);
      expect(tour.inactiveDays, 24);
      expect(tour.isPendingAutoDeletion, isTrue);
      expect(tour.daysUntilAutoDeletion, 6);
    });
  });

  group('TourLifecycleService Tests', () {
    test('checkTourLifecycle deletes expired tours and issues warning for 23-29 days', () async {
      final now = DateTime.now();
      final activeTour = TourModel(
        id: 'active_1',
        name: 'Active Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 5)),
        lastActivityAt: now.subtract(const Duration(days: 2)),
      );

      final warningTour = TourModel(
        id: 'warn_1',
        name: 'Warning Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 35)),
        createdAt: now.subtract(const Duration(days: 35)),
        lastActivityAt: now.subtract(const Duration(days: 24)),
      );

      final expiredTour = TourModel(
        id: 'expired_1',
        name: 'Expired Tour',
        currency: 'USD',
        currencySymbol: '\$',
        inviteCode: 'INV123',
        status: TourStatus.active,
        adminId: 'user_1',
        memberIds: ['user_1'],
        startDate: now.subtract(const Duration(days: 50)),
        createdAt: now.subtract(const Duration(days: 50)),
        lastActivityAt: now.subtract(const Duration(days: 32)),
      );

      final deletedTourIds = <String>[];
      final warnedTourIds = <String>[];

      await TourLifecycleService.instance.processTours(
        tours: [activeTour, warningTour, expiredTour],
        onDeleteTour: (tourId) async {
          deletedTourIds.add(tourId);
        },
        onWarnTour: (tour, daysRemaining) async {
          warnedTourIds.add(tour.id);
        },
      );

      expect(deletedTourIds, contains('expired_1'));
      expect(deletedTourIds, isNot(contains('active_1')));
      expect(deletedTourIds, isNot(contains('warn_1')));

      expect(warnedTourIds, contains('warn_1'));
      expect(warnedTourIds, isNot(contains('active_1')));
      expect(warnedTourIds, isNot(contains('expired_1')));
    });
  });

  group('Login Required Dialog Tests', () {
    testWidgets('showLoginRequiredDialog displays action text and buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showLoginRequiredDialog(
                  context,
                  action: 'create a tour',
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Sign In Required'), findsOneWidget);
      expect(find.textContaining('create a tour'), findsOneWidget);
      expect(find.text('Sign In or Register'), findsOneWidget);
      expect(find.text('Continue Exploring'), findsOneWidget);

      await tester.tap(find.text('Continue Exploring'));
      await tester.pumpAndSettle();

      expect(find.text('Sign In Required'), findsNothing);
    });
  });
}
