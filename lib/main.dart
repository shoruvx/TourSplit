import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/notification_service.dart';
import 'data/services/app_update_service.dart';
import 'data/services/welcome_greeting_service.dart';
import 'presentation/widgets/app_update_listener.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[APP] main() started');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[APP] Firebase initialized');

  await Hive.initFlutter();
  try {
    await Hive.openBox('app_preferences');
    await WelcomeGreetingService.advanceSessionGreeting();
  } catch (e) {
    debugPrint('[APP] Error opening app_preferences: $e');
  }
  debugPrint('[APP] Hive initialized');

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  debugPrint('[APP] calling runApp()');
  runApp(
    const ProviderScope(
      child: TourExpenseTrackerApp(),
    ),
  );

  NotificationService.initialize().catchError((e) {
    debugPrint('[APP] NotificationService init failed: $e');
  });

  // Automatically check for latest GitHub release and sync to Firestore in background
  AppUpdateService.fetchGitHubRelease().catchError((_) => null);
}

class TourExpenseTrackerApp extends ConsumerWidget {
  const TourExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[APP] TourExpenseTrackerApp.build()');
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TourSplit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        ErrorWidget.builder = (details) {
          debugPrint('[APP] Widget error: ${details.exception}');
          return Material(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${details.exception}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          );
        };
        return AppUpdateListener(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
