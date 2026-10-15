import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/tour_model.dart';
import '../repositories/tour_repository.dart';
import 'active_tour_cache_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';

final tourLifecycleServiceProvider = Provider<TourLifecycleService>((ref) {
  return TourLifecycleService(ref);
});

class TourLifecycleService {
  final Ref? _ref;
  static bool _hasCheckedThisSession = false;
  static TourLifecycleService? _instance;

  TourLifecycleService([this._ref]);

  static TourLifecycleService get instance =>
      _instance ??= TourLifecycleService();

  /// Maximum inactive days allowed before automated deletion to save Firestore storage.
  static const int kInactivityThresholdDays = 30;

  /// Days before auto-deletion when warning notification/banner begins (7 days before 30 = 23 days).
  static const int kWarningThresholdDays = 23;

  /// Pure lifecycle processor for testing and decoupled operations.
  Future<void> processTours({
    required List<TourModel> tours,
    required Future<void> Function(String tourId) onDeleteTour,
    required Future<void> Function(TourModel tour, int daysRemaining) onWarnTour,
  }) async {
    for (final tour in tours) {
      if (tour.isDeleted) continue;
      if (tour.isExpiredByInactivity) {
        await onDeleteTour(tour.id);
      } else if (tour.isPendingAutoDeletion) {
        await onWarnTour(tour, tour.daysUntilAutoDeletion);
      }
    }
  }

  /// Checks user tours for inactivity and executes automated cleanup or export reminders.
  Future<void> checkAndProcessInactiveTours({
    required List<TourModel> tours,
    required String currentUserId,
  }) async {
    if (tours.isEmpty || currentUserId.isEmpty || _ref == null) return;

    for (final tour in tours) {
      if (tour.isDeleted) continue;

      // 1. Auto-delete tours with 30 or more days of inactivity
      if (tour.isExpiredByInactivity) {
        debugPrint(
            '[TOUR_LIFECYCLE] Tour "${tour.name}" (${tour.id}) inactive for ${tour.inactiveDays} days. Auto-deleting to save Firestore storage.');
        try {
          await _ref
              .read(tourRepositoryProvider)
              .deleteTour(tour.id, currentUserId: currentUserId);

          final activeId = _ref.read(activeTourIdProvider);
          if (activeId == tour.id) {
            _ref.read(activeTourIdOverrideProvider.notifier).state =
                kNoActiveTourId;
            await ActiveTourCacheService.clearCachedActiveTour();
          }

          _ref.invalidate(userToursStreamProvider(currentUserId));
          _ref.invalidate(tourStreamProvider(tour.id));
        } catch (e) {
          debugPrint('[TOUR_LIFECYCLE] Error auto-deleting inactive tour: $e');
        }
        continue;
      }

      // 2. 7-Day reminder before auto-deletion (23 to 29 days inactive)
      if (tour.isPendingAutoDeletion) {
        await _dispatchInactivityReminderIfNeeded(tour);
      }
    }
  }

  /// Sends a local notification reminder if one has not already been sent today for this tour.
  Future<void> _dispatchInactivityReminderIfNeeded(TourModel tour) async {
    try {
      final box = Hive.isBoxOpen('app_preferences')
          ? Hive.box('app_preferences')
          : await Hive.openBox('app_preferences');

      final todayKey =
          'inactivity_reminded_${tour.id}_day_${tour.inactiveDays}';
      final alreadyReminded = box.get(todayKey, defaultValue: false) as bool;

      if (!alreadyReminded) {
        await box.put(todayKey, true);
        await NotificationService.showTourInactivityWarningNotification(
          tourId: tour.id,
          tourName: tour.name,
          daysRemaining: tour.daysUntilAutoDeletion,
        );
        debugPrint(
            '[TOUR_LIFECYCLE] Reminder dispatched for "${tour.name}": ${tour.daysUntilAutoDeletion} days remaining.');
      }
    } catch (e) {
      debugPrint('[TOUR_LIFECYCLE] Error checking reminder status: $e');
    }
  }

  /// Checks inactive tours once per app session automatically.
  Future<void> checkOncePerSession(
    List<TourModel> tours, {
    String? currentUserId,
  }) async {
    if (_hasCheckedThisSession || tours.isEmpty) return;
    _hasCheckedThisSession = true;
    try {
      final uid = currentUserId ??
          (_ref?.read(currentUserProvider).value?.uid) ??
          '';
      if (uid.isEmpty) return;
      await checkAndProcessInactiveTours(
        tours: tours,
        currentUserId: uid,
      );
    } catch (e) {
      debugPrint('[TOUR_LIFECYCLE] Session check error: $e');
    }
  }

  @visibleForTesting
  static void resetSessionForTesting() {
    _hasCheckedThisSession = false;
  }
}
