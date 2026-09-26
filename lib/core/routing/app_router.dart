import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/auth_service.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/register_screen.dart';
import '../../presentation/auth/forgot_password_screen.dart';
import '../../presentation/home/home_screen.dart';
import '../../presentation/tour/create_tour_screen.dart';
import '../../presentation/tour/join_tour_screen.dart';
import '../../presentation/tour/all_tours_screen.dart';
import '../../presentation/tour/tour_settings_screen.dart';
import '../../presentation/tour/member_management_screen.dart';
import '../../presentation/expense/add_expense_screen.dart';
import '../../presentation/expense/expense_detail_screen.dart';
import '../../data/models/expense_model.dart';
import '../../presentation/balance/balance_screen.dart';
import '../../presentation/settlement/settlement_screen.dart';
import '../../presentation/reports/report_screen.dart';
import '../../presentation/profile/profile_screen.dart';
import '../../presentation/profile/contact_us_screen.dart';
import '../../presentation/profile/member_profile_screen.dart';
import '../../presentation/chat/tour_chat_screen.dart';
import '../../data/models/tour_model.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _ref.listen<AsyncValue>(authStateProvider, (_, next) {
      debugPrint(
          '[ROUTER] authState changed: ${next.value?.email ?? "null (signed out)"}');
      notifyListeners();
    });
  }

  final Ref _ref;
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  final initialUser = FirebaseAuth.instance.currentUser;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialUser != null ? '/home' : '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final currentUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = currentUser != null || authState.value != null;
      debugPrint(
          '[ROUTER] redirect check for ${state.matchedLocation} (currentUser: ${currentUser?.email}, loggedIn: $isLoggedIn, auth loading: ${authState.isLoading})');

      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register') ||
          state.matchedLocation.startsWith('/forgot-password');

      if (isLoggedIn && isAuthRoute) return '/home';

      if (!isLoggedIn && !authState.isLoading && !isAuthRoute) return '/login';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/tours',
        name: 'all-tours',
        builder: (context, state) => const AllToursScreen(),
      ),
      GoRoute(
        path: '/tour/create',
        name: 'create-tour',
        builder: (context, state) => const CreateTourScreen(),
      ),
      GoRoute(
        path: '/tour/join',
        name: 'join-tour',
        builder: (context, state) {
          final code = state.uri.queryParameters['code'] ??
              state.uri.queryParameters['join'];
          return JoinTourScreen(initialCode: code);
        },
      ),
      GoRoute(
        path: '/shoruvx/TourSplit/releases/latest',
        redirect: (context, state) {
          final code = state.uri.queryParameters['code'] ??
              state.uri.queryParameters['join'];
          if (code != null && code.isNotEmpty) {
            return '/tour/join?code=$code';
          }
          return '/home';
        },
      ),
      GoRoute(
        path: '/join',
        redirect: (context, state) {
          final code = state.uri.queryParameters['code'] ??
              state.uri.queryParameters['join'];
          if (code != null && code.isNotEmpty) {
            return '/tour/join?code=$code';
          }
          return '/tour/join';
        },
      ),
      GoRoute(
        path: '/tour/settings',
        name: 'tour-settings',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return TourSettingsScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/tour/members',
        name: 'tour-members',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return MemberManagementScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/tour/chat/:tourId',
        name: 'tour-chat',
        builder: (context, state) {
          final tourId = state.pathParameters['tourId']!;
          final tourName = state.uri.queryParameters['name'] ?? 'Tour';
          return TourChatScreen(tourId: tourId, tourName: tourName);
        },
      ),
      GoRoute(
        path: '/expense/add',
        name: 'add-expense',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return AddExpenseScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/expense/edit',
        name: 'edit-expense',
        builder: (context, state) {
          final expense = state.extra as ExpenseModel?;
          final tourId = state.uri.queryParameters['tourId'] ?? expense?.tourId;
          return AddExpenseScreen(tourId: tourId, existingExpense: expense);
        },
      ),
      GoRoute(
        path: '/expense/:expenseId',
        name: 'expense-detail',
        builder: (context, state) => ExpenseDetailScreen(
          expenseId: state.pathParameters['expenseId']!,
        ),
      ),
      GoRoute(
        path: '/balance',
        name: 'balance',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return BalanceScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/settlement',
        name: 'settlement',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return SettlementScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/reports',
        name: 'reports',
        builder: (context, state) {
          final tourId = state.uri.queryParameters['tourId'] ??
              (state.extra as String?);
          return ReportScreen(tourId: tourId);
        },
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/contact-us',
        name: 'contact-us',
        builder: (context, state) => const ContactUsScreen(),
      ),
      GoRoute(
        path: '/member/:userId',
        name: 'member-profile',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final member = state.extra as TourMemberModel?;
          return MemberProfileScreen(userId: userId, member: member);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );

  ref.onDispose(() {
    notifier.dispose();
    router.dispose();
  });

  return router;
});
