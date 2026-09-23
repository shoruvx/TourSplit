/// Global lightweight tracker for whether the user is actively viewing a tour's chat screen.
/// When viewing a tour chat screen, in-app notifications for that specific tour are suppressed
/// to avoid redundant notification banners while typing/reading.
class ChatActiveTracker {
  static String? activeTourChatId;
}
