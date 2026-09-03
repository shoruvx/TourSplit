import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/notification_service.dart';

/// Background FCM message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[APP] main() started');

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[APP] Firebase initialized');

  // Initialize Hive for local offline cache
  await Hive.initFlutter();
  debugPrint('[APP] Hive initialized');

  // Set up background FCM handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  debugPrint('[APP] calling runApp()');
  // Launch the app immediately — don't block on notification setup
  // (FCM/Play Services may hang on some devices)
  runApp(
    const ProviderScope(
      child: TourExpenseTrackerApp(),
    ),
  );

  // Initialize notifications in the background, non-blocking
  NotificationService.initialize().catchError((e) {
    // Notification setup failed — app still works without it
    debugPrint('[APP] NotificationService init failed: $e');
  });
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
        // Catch widget errors visually
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
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
