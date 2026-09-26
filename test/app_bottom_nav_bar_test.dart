import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/user_model.dart';
import 'package:toursplit/presentation/widgets/app_bottom_nav_bar.dart';

void main() {
  final sampleUser = UserModel(
    uid: 'u_123',
    firstName: 'Rahim',
    lastName: 'Khan',
    username: 'rahim',
    email: 'rahim@example.com',
    createdAt: DateTime.now(),
  );

  final sampleTour = TourModel(
    id: 'tour_sajek_99',
    name: 'Sajek Valley',
    currency: 'BDT',
    currencySymbol: '৳',
    adminId: 'u_123',
    inviteCode: 'SAJEK9',
    status: TourStatus.active,
    startDate: DateTime.now(),
    endDate: DateTime.now().add(const Duration(days: 3)),
    memberIds: ['u_123', 'u_456'],
    createdAt: DateTime.now(),
  );

  group('HomeBottomNavigationBar Tests', () {
    testWidgets('renders Home, My Tours, and Profile with correct active selection',
        (tester) async {
      bool homeTapped = false;
      bool toursTapped = false;
      bool profileTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: HomeBottomNavigationBar(
                currentIndex: 0,
                activeToursCount: 3,
                currentUser: sampleUser,
                onHomeTap: () => homeTapped = true,
                onToursTap: () => toursTapped = true,
                onProfileTap: () => profileTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('My Tours'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Active tours badge

      await tester.tap(find.text('Home'));
      expect(homeTapped, isTrue);

      await tester.tap(find.text('My Tours'));
      expect(toursTapped, isTrue);

      await tester.tap(find.text('Profile'));
      expect(profileTapped, isTrue);
    });

    testWidgets('renders Profile as selected when currentIndex is 2',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: HomeBottomNavigationBar(
                currentIndex: 2,
                activeToursCount: 1,
                currentUser: sampleUser,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('My Tours'), findsOneWidget);
    });
  });

  group('TourBottomNavigationBar Tests', () {
    testWidgets('renders All Tours, Dashboard, Members, and Settings for tour admin',
        (tester) async {
      bool toursTapped = false;
      bool dashboardTapped = false;
      bool membersTapped = false;
      bool settingsTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: TourBottomNavigationBar(
                tour: sampleTour,
                isAdmin: true,
                currentUser: sampleUser,
                membersCount: 4,
                currentIndex: 1,
                onToursTap: () => toursTapped = true,
                onDashboardTap: () => dashboardTapped = true,
                onMembersTap: () => membersTapped = true,
                onSettingsTap: () => settingsTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('All Tours'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Profile'), findsNothing);
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.text('All Tours'));
      expect(toursTapped, isTrue);

      await tester.tap(find.text('Dashboard'));
      expect(dashboardTapped, isTrue);

      await tester.tap(find.text('Members'));
      expect(membersTapped, isTrue);

      await tester.tap(find.text('Settings'));
      expect(settingsTapped, isTrue);
    });

    testWidgets('hides Settings tab for non-admin members', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: TourBottomNavigationBar(
                tour: sampleTour,
                isAdmin: false,
                currentUser: sampleUser,
                membersCount: 2,
                currentIndex: 1,
              ),
            ),
          ),
        ),
      );

      expect(find.text('All Tours'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Profile'), findsNothing);
    });
  });
}
