import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/data/models/tour_model.dart';
import 'package:toursplit/data/models/user_model.dart';
import 'package:toursplit/data/models/expense_model.dart';
import 'package:toursplit/core/theme/app_theme.dart';

void main() {
  group('Mistaken Member Removal & Member Lists', () {
    test('Mistakenly added member can be cleanly removed from TourModel', () {
      final initialTour = TourModel(
        id: 'tour_1',
        name: 'Cox\'s Bazar Trip',
        currency: 'BDT',
        currencySymbol: '৳',
        adminId: 'admin_1',
        memberIds: ['admin_1', 'mistaken_member'],
        inviteCode: 'TRP123',
        status: TourStatus.active,
        startDate: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(initialTour.memberIds.length, 2);
      expect(initialTour.isMember('mistaken_member'), isTrue);

      // Clean removal of mistakenly added member
      final updatedMembers = List<String>.from(initialTour.memberIds)
        ..remove('mistaken_member');
      final updatedTour = initialTour.copyWith(memberIds: updatedMembers);

      expect(updatedTour.memberIds.length, 1);
      expect(updatedTour.isMember('mistaken_member'), isFalse);
      expect(updatedTour.memberIds, contains('admin_1'));
    });
  });

  group('UserModel Username & Privacy Display', () {
    test('Username replaces email in privacy-safe handles', () {
      final user = UserModel(
        uid: 'u1',
        email: 'alex.smith@example.com',
        username: 'alexsmith',
        firstName: 'Alex Smith',
        lastName: '',
        createdAt: DateTime.now(),
      );

      expect(user.username, 'alexsmith');
      expect(user.displayName, 'Alex Smith');

      // Handle without exposing domain
      final handle = user.username.isNotEmpty
          ? user.username
          : user.email.split('@').first;
      expect(handle, 'alexsmith');
      expect('@$handle', '@alexsmith');
    });

    test('Fallback to email prefix when username is not set', () {
      final user = UserModel(
        uid: 'u2',
        email: 'traveler99@domain.org',
        username: '',
        firstName: 'Traveler',
        lastName: '',
        createdAt: DateTime.now(),
      );

      final handle = user.username.isNotEmpty
          ? user.username
          : user.email.split('@').first;
      expect(handle, 'traveler99');
      expect('@$handle', '@traveler99');
    });
  });

  group('Typography & Font Fallbacks', () {
    test('AppTheme includes Apple San Francisco in fontFallbacks', () {
      final lightTheme = AppTheme.lightTheme;
      final darkTheme = AppTheme.darkTheme;

      expect(lightTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('.SF Pro Text'));
      expect(lightTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('Outfit'));

      expect(darkTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('.SF Pro Text'));
      expect(darkTheme.textTheme.bodyMedium?.fontFamilyFallback,
          contains('Outfit'));
    });
  });

  group('Expense Added By Column & Immutability Tests', () {
    test('ExpenseModel serializes and deserializes addedBy and addedByName', () {
      final expense = ExpenseModel(
        id: 'exp_123',
        tourId: 'tour_1',
        title: 'Dinner at Beach',
        amount: 1500.0,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'user_alice',
        paidByName: 'Alice Wonder',
        splitType: SplitType.equal,
        splitAmong: ['user_alice', 'user_bob'],
        date: DateTime(2026, 9, 26, 19, 0),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_bob',
        addedByName: 'Bob Builder',
        createdAt: DateTime(2026, 9, 26, 19, 5),
      );

      final map = expense.toFirestore();
      expect(map['addedBy'], 'user_bob');
      expect(map['addedByName'], 'Bob Builder');
      expect(map['paidBy'], 'user_alice');

      final restored = ExpenseModel.fromMap(map, 'exp_123');
      expect(restored.addedByUserId, 'user_bob');
      expect(restored.addedByName, 'Bob Builder');
      expect(restored.paidByUserId, 'user_alice');
      expect(restored.paidByName, 'Alice Wonder');
    });

    test('resolveAddedByName handles cachedName, addedByName, and paidByName fallback', () {
      final expWithBoth = ExpenseModel(
        id: 'exp_1',
        tourId: 'tour_1',
        title: 'Snacks',
        amount: 200.0,
        currency: 'BDT',
        category: 'Food',
        paidByUserId: 'user_alice',
        paidByName: 'Alice Wonder',
        splitType: SplitType.equal,
        splitAmong: ['user_alice'],
        date: DateTime.now(),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_alice',
        addedByName: 'Alice W',
        createdAt: DateTime.now(),
      );

      expect(expWithBoth.resolveAddedByName(), 'Alice W');
      expect(expWithBoth.resolveAddedByName('Alice FullName'), 'Alice FullName');

      final expWithoutAddedName = expWithBoth.copyWith(addedByName: '');
      expect(expWithoutAddedName.resolveAddedByName(), 'Alice Wonder');

      final expDifferentPayerWithoutAddedName = expWithoutAddedName.copyWith(
        addedByUserId: 'user_stranger',
        paidByUserId: 'user_alice',
      );
      expect(expDifferentPayerWithoutAddedName.resolveAddedByName(), 'Unknown');
    });

    test('Editing an expense preserves original addedByUserId and addedByName', () {
      final original = ExpenseModel(
        id: 'exp_orig',
        tourId: 'tour_1',
        title: 'Kayak Rental',
        amount: 800.0,
        currency: 'BDT',
        category: 'Activities',
        paidByUserId: 'user_alice',
        paidByName: 'Alice',
        splitType: SplitType.equal,
        splitAmong: ['user_alice'],
        date: DateTime(2026, 9, 26, 10, 0),
        status: ExpenseStatus.approved,
        addedByUserId: 'user_bob',
        addedByName: 'Bob Original Creator',
        createdAt: DateTime(2026, 9, 26, 10, 5),
      );

      // Current user editing is Charlie
      const currentEditorId = 'user_charlie';
      const currentEditorName = 'Charlie Editor';

      // Immutable logic as implemented in AddExpenseScreen
      final originalAddedByUserId = original.addedByUserId;
      final effectiveAddedByUserId = (originalAddedByUserId.isNotEmpty)
          ? originalAddedByUserId
          : currentEditorId;

      final originalAddedByName = original.addedByName;
      final effectiveAddedByName = (originalAddedByName.isNotEmpty)
          ? originalAddedByName
          : currentEditorName;

      final editedExpense = original.copyWith(
        title: 'Updated Kayak Rental',
        amount: 900.0,
        addedByUserId: effectiveAddedByUserId,
        addedByName: effectiveAddedByName,
      );

      // Creator details remain Bob, NOT Charlie
      expect(editedExpense.title, 'Updated Kayak Rental');
      expect(editedExpense.amount, 900.0);
      expect(editedExpense.addedByUserId, 'user_bob');
      expect(editedExpense.addedByName, 'Bob Original Creator');
    });
  });
}
