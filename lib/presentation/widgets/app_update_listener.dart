import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_router.dart';
import '../../data/models/app_update_model.dart';
import '../../data/services/app_update_service.dart';

class AppUpdateListener extends ConsumerStatefulWidget {
  final Widget child;
  const AppUpdateListener({super.key, required this.child});

  @override
  ConsumerState<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends ConsumerState<AppUpdateListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPrompt();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-query GitHub and Firestore when user returns to the app
      ref.invalidate(gitHubUpdateFutureProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndPrompt();
      });
    }
  }

  void _checkAndPrompt() {
    if (!mounted) return;
    final updateInfo = ref.read(effectiveUpdateInfoProvider);
    final packageInfo = ref.read(currentAppVersionProvider).value;

    if (updateInfo != null && packageInfo != null) {
      final targetContext = rootNavigatorKey.currentContext ?? context;
      AppUpdateService.promptUpdateIfNeeded(
        targetContext,
        updateInfo,
        packageInfo.version,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactively listen to live updates pushed via Firestore or GitHub
    ref.listen<AppUpdateInfo?>(effectiveUpdateInfoProvider, (prev, next) {
      if (next != null) {
        final packageInfo = ref.read(currentAppVersionProvider).value;
        if (packageInfo != null) {
          final targetContext = rootNavigatorKey.currentContext ?? context;
          AppUpdateService.promptUpdateIfNeeded(
            targetContext,
            next,
            packageInfo.version,
          );
        }
      }
    });

    return widget.child;
  }
}
