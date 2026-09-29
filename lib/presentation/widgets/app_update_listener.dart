import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  Future<void> _checkAndPrompt() async {
    if (!mounted) return;

    // Check installation source via package_info_plus
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    if (AppUpdateService.isAppStorePackage(packageInfo.installerStore)) {
      // If installer package points to an app store (Samsung, Huawei, Amazon, Xiaomi, or F-Droid),
      // completely disable the internal OTA update popup to comply with store policies.
      return;
    }

    final updateInfo = ref.read(effectiveUpdateInfoProvider);

    if (updateInfo != null && mounted) {
      final targetContext = rootNavigatorKey.currentContext ?? context;
      if (targetContext.mounted) {
        AppUpdateService.promptUpdateIfNeeded(
          targetContext,
          updateInfo,
          packageInfo.version,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactively listen to live updates pushed via Firestore or GitHub
    ref.listen<AppUpdateInfo?>(effectiveUpdateInfoProvider, (prev, next) async {
      if (next != null) {
        final packageInfo = await PackageInfo.fromPlatform();
        if (!context.mounted) return;
        if (AppUpdateService.isAppStorePackage(packageInfo.installerStore)) {
          // Disable internal OTA popup for store installs
          return;
        }

        final targetContext = rootNavigatorKey.currentContext ?? context;
        AppUpdateService.promptUpdateIfNeeded(
          targetContext,
          next,
          packageInfo.version,
        );
      }
    });

    return widget.child;
  }
}

