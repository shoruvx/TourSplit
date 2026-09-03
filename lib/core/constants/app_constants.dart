class AppConstants {
  static const String usersCollection = 'users';
  static const String toursCollection = 'tours';
  static const String membersSubcollection = 'members';
  static const String expensesSubcollection = 'expenses';
  static const String settlementsSubcollection = 'settlements';
  static const String categoriesSubcollection = 'categories';

  static const String tourCacheBox = 'tour_cache';
  static const String expenseCacheBox = 'expense_cache';
  static const String userCacheBox = 'user_cache';

  static const int inviteCodeLength = 6;

  static const List<Map<String, dynamic>> defaultCategories = [
    {'name': 'Food & Drinks', 'icon': '🍽️'},
    {'name': 'Transport', 'icon': '🚗'},
    {'name': 'Accommodation', 'icon': '🏨'},
    {'name': 'Activities', 'icon': '🎭'},
    {'name': 'Shopping', 'icon': '🛍️'},
    {'name': 'Fuel', 'icon': '⛽'},
    {'name': 'Medical', 'icon': '💊'},
    {'name': 'Entry Tickets', 'icon': '🎟️'},
    {'name': 'Miscellaneous', 'icon': '📦'},
  ];

  static const List<Map<String, String>> currencies = [
    {'code': 'BDT', 'name': 'Bangladeshi Taka', 'symbol': '৳'},
    {'code': 'USD', 'name': 'US Dollar', 'symbol': '\$'},
    {'code': 'EUR', 'name': 'Euro', 'symbol': '€'},
    {'code': 'GBP', 'name': 'British Pound', 'symbol': '£'},
    {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹'},
    {'code': 'AED', 'name': 'UAE Dirham', 'symbol': 'د.إ'},
    {'code': 'SAR', 'name': 'Saudi Riyal', 'symbol': '﷼'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit', 'symbol': 'RM'},
    {'code': 'THB', 'name': 'Thai Baht', 'symbol': '฿'},
    {'code': 'SGD', 'name': 'Singapore Dollar', 'symbol': 'S\$'},
  ];

  static const String allUsersTopic = 'all_users';

  static const String githubRepo = 'shoruvx/TourSplit';
}

class AppStrings {
  static const String appName = 'TourSplit';
  static const String appSlogan = 'Split the costs, keep the memories.';
  static const String loginTitle = 'Welcome to TourSplit';
  static const String loginSubtitle = 'Split the costs, keep the memories.';
  static const String registerTitle = 'Join TourSplit';
  static const String registerSubtitle = 'Split the costs, keep the memories.';

  static const String createTour = 'Create Tour';
  static const String joinTour = 'Join Tour';
  static const String noActiveTour = 'No Active Tour';
  static const String noActiveTourSubtitle =
      'Create a new tour or join an existing one with an invite code';

  static const String addExpense = 'Add Expense';
  static const String pendingApproval = 'Pending Approval';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';

  static const String positiveBalance = 'You are owed';
  static const String negativeBalance = 'You owe';
  static const String settled = 'Settled';
}
